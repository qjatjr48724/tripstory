import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/country_flag.dart';
import '../../data/naver_local_client.dart';
import '../../data/travel_repository.dart';
import '../../domain/place.dart';
import '../../domain/travel.dart';
import '../providers/travel_providers.dart';

class TravelPlacesPage extends ConsumerStatefulWidget {
  const TravelPlacesPage({super.key, required this.travelId});

  final String travelId;

  @override
  ConsumerState<TravelPlacesPage> createState() => _TravelPlacesPageState();
}

class _TravelPlacesPageState extends ConsumerState<TravelPlacesPage> {
  bool _mineOnly = false;
  String? _myMemberId;

  @override
  void initState() {
    super.initState();
    _loadMyMemberId();
  }

  Future<void> _loadMyMemberId() async {
    try {
      final id = await ref
          .read(travelRepositoryProvider)
          .fetchMyMemberId(widget.travelId);
      if (!mounted) return;
      setState(() => _myMemberId = id);
    } catch (_) {
      // 필터만 비활성 — 목록은 그대로 표시
    }
  }

  Color _parseColor(String? hex) {
    final cleaned = (hex ?? '#0D7377').replaceFirst('#', '');
    final value = int.tryParse(cleaned, radix: 16) ?? 0x0D7377;
    return Color(0xFF000000 | value);
  }

  Future<void> _openMap(Place place) async {
    if (!place.canOpenMap && !isNaverPlaceDetailUrl(place.mapsUrl)) return;

    // 국내: 네이버 지도 앱에 좌표+이름 마커 (붙여넣기 없음)
    if (place.isKorea) {
      if (!place.hasCoordinates) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('좌표가 없어 지도를 열 수 없습니다')),
        );
        return;
      }

      final appUri = naverMapAppPlaceUri(
        name: place.name,
        latitude: place.latitude,
        longitude: place.longitude,
      );
      if (appUri != null && await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return;
      }

      // Android: 앱 없으면 스토어로
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        final intentUri = naverMapAndroidIntentUri(
          name: place.name,
          latitude: place.latitude,
          longitude: place.longitude,
        );
        if (intentUri != null && await canLaunchUrl(intentUri)) {
          await launchUrl(intentUri, mode: LaunchMode.externalApplication);
          return;
        }
      }

      // 웹 폴백
      final web = naverPlacePinUrl(
        name: place.name,
        latitude: place.latitude,
        longitude: place.longitude,
      );
      if (web == null) return;
      await launchUrl(
        Uri.parse(web),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    final Uri uri;
    if (place.googlePlaceId != null && place.googlePlaceId!.isNotEmpty) {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1'
        '&query=place_id:${place.googlePlaceId}',
      );
    } else {
      final mapsUrl = place.mapsUrl?.trim();
      final isGoogleMapUrl = mapsUrl != null &&
          mapsUrl.isNotEmpty &&
          (mapsUrl.contains('google.com/maps') ||
              mapsUrl.contains('maps.google') ||
              mapsUrl.contains('goo.gl/maps'));

      if (isGoogleMapUrl) {
        uri = Uri.parse(mapsUrl);
      } else if (place.hasCoordinates) {
        final lat = place.latitude!;
        final lng = place.longitude!;
        uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
        );
      } else if (mapsUrl != null && mapsUrl.isNotEmpty) {
        uri = Uri.parse(mapsUrl);
      } else {
        return;
      }
    }

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _canEdit(Travel travel, Place place) {
    final role = travel.myRole;
    if (role == null || travel.status != TravelStatus.active) return false;
    if (role.canEditOthersPlace) return true;
    return _myMemberId != null && place.createdByMemberId == _myMemberId;
  }

  @override
  Widget build(BuildContext context) {
    final travelId = widget.travelId;
    final travelAsync = ref.watch(travelDetailProvider(travelId));
    final placesAsync = ref.watch(travelPlacesProvider(travelId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('장소 후보'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('${AppRoutes.travels}/$travelId'),
        ),
      ),
      floatingActionButton: travelAsync.maybeWhen(
        data: (travel) => travel.status == TravelStatus.active
            ? FloatingActionButton.extended(
                onPressed: () => context.push(
                  '${AppRoutes.travels}/$travelId/places/new',
                ),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('장소 추가'),
              )
            : null,
        orElse: () => null,
      ),
      body: travelAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (travel) {
          return placesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$e', textAlign: TextAlign.center),
              ),
            ),
            data: (places) {
              final filtered = _mineOnly && _myMemberId != null
                  ? places
                      .where((p) => p.createdByMemberId == _myMemberId)
                      .toList()
                  : places;

              if (places.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '아직 장소 후보가 없어요.\n가고 싶은 장소를 먼저 저장해 보세요.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('전체'),
                          icon: Icon(Icons.groups_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('내 장소'),
                          icon: Icon(Icons.person_outline, size: 18),
                        ),
                      ],
                      selected: {_mineOnly},
                      onSelectionChanged: (next) {
                        setState(() => _mineOnly = next.first);
                      },
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              '내가 등록한 장소가 없어요.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () async {
                              ref.invalidate(travelPlacesProvider(travelId));
                              await _loadMyMemberId();
                            },
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 88),
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final place = filtered[index];
                                final canEdit = _canEdit(travel, place);
                                final flag =
                                    countryFlagEmoji(place.countryCode);
                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: _parseColor(
                                        place.creatorColorHex,
                                      ),
                                      child: Text(
                                        flag,
                                        style: const TextStyle(fontSize: 22),
                                      ),
                                    ),
                                    title: Text(place.name),
                                    subtitle: Text(
                                      [
                                        if (place.address != null)
                                          place.address!,
                                        if (place.creatorDisplayName != null)
                                          place.creatorDisplayName!,
                                      ].join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: canEdit
                                        ? PopupMenuButton<String>(
                                            onSelected: (value) async {
                                              switch (value) {
                                                case 'edit':
                                                  context.push(
                                                    '${AppRoutes.travels}/$travelId/places/${place.id}/edit',
                                                    extra: place,
                                                  );
                                                case 'map':
                                                  await _openMap(place);
                                                case 'delete':
                                                  await _confirmDelete(
                                                    place,
                                                  );
                                              }
                                            },
                                            itemBuilder: (context) => [
                                              const PopupMenuItem(
                                                value: 'edit',
                                                child: Text('수정'),
                                              ),
                                              if (place.canOpenMap)
                                                const PopupMenuItem(
                                                  value: 'map',
                                                  child: Text('지도에서 보기'),
                                                ),
                                              const PopupMenuItem(
                                                value: 'delete',
                                                child: Text(
                                                  '삭제',
                                                  style: TextStyle(
                                                    color: AppColors.error,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : (place.canOpenMap
                                            ? IconButton(
                                                tooltip: '지도에서 보기',
                                                onPressed: () =>
                                                    _openMap(place),
                                                icon: const Icon(
                                                  Icons.map_outlined,
                                                ),
                                              )
                                            : null),
                                    onTap: canEdit
                                        ? () => context.push(
                                              '${AppRoutes.travels}/$travelId/places/${place.id}/edit',
                                              extra: place,
                                            )
                                        : (place.canOpenMap
                                            ? () => _openMap(place)
                                            : null),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(Place place) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('장소 삭제'),
        content: Text('「${place.name}」을(를) 삭제할까요?'),
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
    if (ok != true || !mounted) return;

    try {
      await ref.read(travelRepositoryProvider).deletePlace(place.id);
      ref.invalidate(travelPlacesProvider(widget.travelId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장소를 삭제했습니다')),
      );
    } on TravelException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}
