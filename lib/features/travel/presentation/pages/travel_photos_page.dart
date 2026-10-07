import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/travel.dart';
import '../../domain/travel_photo.dart';
import '../providers/travel_providers.dart';

class TravelPhotosPage extends ConsumerWidget {
  const TravelPhotosPage({super.key, required this.travelId});

  final String travelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final travelAsync = ref.watch(travelDetailProvider(travelId));
    final photosAsync = ref.watch(travelPhotosProvider(travelId));

    return travelAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('사진')),
        body: Center(child: Text('$e')),
      ),
      data: (travel) {
        final canEdit = travel.status == TravelStatus.active &&
            travel.myRole != null &&
            !travel.isJoinPending;

        return Scaffold(
          appBar: AppBar(
            title: const Text('사진'),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: '사진 추가',
                  onPressed: () => _addPhoto(context, ref),
                  icon: const Icon(Icons.add_a_photo_outlined),
                ),
            ],
          ),
          body: photosAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$e', textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Storage 버킷 SQL 적용 여부를 확인해 주세요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(travelPhotosProvider(travelId)),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            ),
            data: (photos) {
              if (photos.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_library_outlined, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          '여행 사진이 없어요',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '제목·메모와 함께 사진을 남겨 두세요.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        if (canEdit) ...[
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => _addPhoto(context, ref),
                            icon: const Icon(Icons.add_a_photo_outlined),
                            label: const Text('사진 추가'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(travelPhotosProvider(travelId));
                  await ref.read(travelPhotosProvider(travelId).future);
                },
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: photos.length,
                  itemBuilder: (context, index) {
                    final photo = photos[index];
                    return _PhotoCard(
                      photo: photo,
                      canEdit: canEdit,
                      onTap: () => _showDetail(context, ref, photo, canEdit),
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _addPhoto(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null || !context.mounted) return;

    final titleController = TextEditingController();
    final memoController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사진 등록'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '제목'),
            ),
            TextField(
              controller: memoController,
              decoration: const InputDecoration(labelText: '메모'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('업로드'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    try {
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ?? 'image/jpeg';
      final ext = switch (mime) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/heic' => 'heic',
        _ => 'jpg',
      };
      await ref.read(travelRepositoryProvider).createTravelPhoto(
            travelId: travelId,
            bytes: bytes,
            contentType: mime,
            ext: ext,
            title: titleController.text,
            memo: memoController.text,
          );
      ref.invalidate(travelPhotosProvider(travelId));
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _showDetail(
    BuildContext context,
    WidgetRef ref,
    TravelPhoto photo,
    bool canEdit,
  ) async {
    final url = await ref
        .read(travelRepositoryProvider)
        .signedMediaUrl(photo.storagePath);
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (url != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(url, fit: BoxFit.cover),
                )
              else
                const SizedBox(
                  height: 160,
                  child: Center(child: Text('이미지를 불러오지 못했습니다')),
                ),
              const SizedBox(height: 12),
              Text(
                photo.title?.trim().isNotEmpty == true
                    ? photo.title!
                    : '제목 없음',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (photo.memo?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(photo.memo!),
              ],
              if (photo.uploader != null) ...[
                const SizedBox(height: 4),
                Text(
                  '업로드: ${photo.uploader!.displayName}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
              if (canEdit) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _editMeta(context, ref, photo);
                        },
                        child: const Text('제목·메모 수정'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          await _delete(context, ref, photo);
                        },
                        child: const Text(
                          '삭제',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _editMeta(
    BuildContext context,
    WidgetRef ref,
    TravelPhoto photo,
  ) async {
    final titleController = TextEditingController(text: photo.title ?? '');
    final memoController = TextEditingController(text: photo.memo ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사진 정보'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '제목'),
            ),
            TextField(
              controller: memoController,
              decoration: const InputDecoration(labelText: '메모'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(travelRepositoryProvider).updateTravelPhoto(
            photo: photo,
            title: titleController.text,
            memo: memoController.text,
          );
      ref.invalidate(travelPhotosProvider(travelId));
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    TravelPhoto photo,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사진 삭제'),
        content: const Text('이 사진을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(travelRepositoryProvider).deleteTravelPhoto(photo);
      ref.invalidate(travelPhotosProvider(travelId));
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}

class _PhotoCard extends ConsumerWidget {
  const _PhotoCard({
    required this.photo,
    required this.canEdit,
    required this.onTap,
  });

  final TravelPhoto photo;
  final bool canEdit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FutureBuilder<String?>(
                future: ref
                    .read(travelRepositoryProvider)
                    .signedMediaUrl(photo.storagePath),
                builder: (context, snap) {
                  if (snap.data == null) {
                    return const ColoredBox(
                      color: AppColors.surfaceMuted,
                      child: Center(child: Icon(Icons.image_outlined)),
                    );
                  }
                  return Image.network(snap.data!, fit: BoxFit.cover);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    photo.title?.trim().isNotEmpty == true
                        ? photo.title!
                        : '제목 없음',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (photo.memo?.trim().isNotEmpty == true)
                    Text(
                      photo.memo!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
