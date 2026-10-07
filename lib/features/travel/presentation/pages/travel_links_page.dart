import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/travel.dart';
import '../../domain/travel_link.dart';
import '../providers/travel_providers.dart';

class TravelLinksPage extends ConsumerWidget {
  const TravelLinksPage({super.key, required this.travelId});

  final String travelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final travelAsync = ref.watch(travelDetailProvider(travelId));
    final linksAsync = ref.watch(travelLinksProvider(travelId));

    return travelAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('링크')),
        body: Center(child: Text('$e')),
      ),
      data: (travel) {
        final canEdit = travel.status == TravelStatus.active &&
            travel.myRole != null &&
            !travel.isJoinPending;

        return Scaffold(
          appBar: AppBar(
            title: const Text('링크'),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: '링크 추가',
                  onPressed: () => _editLink(context, ref),
                  icon: const Icon(Icons.add_link),
                ),
            ],
          ),
          body: linksAsync.when(
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
                      'travel_links 테이블 SQL을 대시보드에 적용했는지 확인해 주세요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(travelLinksProvider(travelId)),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            ),
            data: (links) {
              if (links.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          '저장된 링크가 없어요',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '맛집·티켓·공지 등 자주 여는 링크를 모아 두세요.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        if (canEdit) ...[
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => _editLink(context, ref),
                            icon: const Icon(Icons.add_link),
                            label: const Text('링크 추가'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(travelLinksProvider(travelId));
                  await ref.read(travelLinksProvider(travelId).future);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: links.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final link = links[index];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        title: Text(link.title),
                        subtitle: Text(
                          [
                            link.url,
                            if (link.memo?.trim().isNotEmpty == true)
                              link.memo!,
                          ].join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: link.memo?.trim().isNotEmpty == true,
                        trailing: const Icon(Icons.open_in_new, size: 20),
                        onTap: () => _openUrl(context, link.url),
                        onLongPress: canEdit
                            ? () => _showActions(context, ref, link)
                            : null,
                      ),
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

  Future<void> _openUrl(BuildContext context, String raw) async {
    var value = raw.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 링크가 아닙니다')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _editLink(
    BuildContext context,
    WidgetRef ref, {
    TravelLink? link,
  }) async {
    final titleController = TextEditingController(text: link?.title ?? '');
    final urlController = TextEditingController(text: link?.url ?? '');
    final memoController = TextEditingController(text: link?.memo ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(link == null ? '링크 추가' : '링크 수정'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: '제목 *'),
            ),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'URL *',
                hintText: 'https://...',
              ),
              keyboardType: TextInputType.url,
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
      final repo = ref.read(travelRepositoryProvider);
      if (link == null) {
        await repo.createTravelLink(
          travelId: travelId,
          title: titleController.text,
          url: urlController.text,
          memo: memoController.text,
        );
      } else {
        await repo.updateTravelLink(
          link: link,
          title: titleController.text,
          url: urlController.text,
          memo: memoController.text,
        );
      }
      ref.invalidate(travelLinksProvider(travelId));
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _showActions(
    BuildContext context,
    WidgetRef ref,
    TravelLink link,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('수정'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text('삭제', style: TextStyle(color: AppColors.error)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      await _editLink(context, ref, link: link);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('링크 삭제'),
        content: Text('「${link.title}」을(를) 삭제할까요?'),
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
      await ref.read(travelRepositoryProvider).deleteTravelLink(link);
      ref.invalidate(travelLinksProvider(travelId));
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}
