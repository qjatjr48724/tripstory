import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/google_places_client.dart';
import '../../data/travel_repository.dart';
import '../../domain/place.dart';
import '../providers/travel_providers.dart';
import 'place_search_page.dart';

class PlaceFormPage extends ConsumerStatefulWidget {
  const PlaceFormPage({
    super.key,
    required this.travelId,
    this.place,
  });

  final String travelId;
  final Place? place;

  bool get isEditing => place != null;

  @override
  ConsumerState<PlaceFormPage> createState() => _PlaceFormPageState();
}

class _PlaceFormPageState extends ConsumerState<PlaceFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _countryController;
  late final TextEditingController _memoController;
  late final TextEditingController _naverLinkController;
  double? _latitude;
  double? _longitude;
  String? _googlePlaceId;
  String? _mapsUrl;
  bool _loading = false;
  bool _pickedFromMap = false;

  bool get _isKorea {
    final code = _countryController.text.trim().toUpperCase();
    return code == 'KR' || code == 'KOR';
  }

  @override
  void initState() {
    super.initState();
    final p = widget.place;
    _nameController = TextEditingController(text: p?.name ?? '');
    _addressController = TextEditingController(text: p?.address ?? '');
    _countryController = TextEditingController(text: p?.countryCode ?? '');
    _memoController = TextEditingController(text: p?.memo ?? '');
    final existingMaps = p?.mapsUrl ?? '';
    // 국내: maps_url을 플레이스 링크(B)로 사용. 핀 URL은 저장하지 않음.
    _naverLinkController = TextEditingController(
      text: (p != null &&
              ((p.countryCode ?? '').toUpperCase() == 'KR' ||
                  (p.countryCode ?? '').toUpperCase() == 'KOR') &&
              existingMaps.isNotEmpty)
          ? existingMaps
          : '',
    );
    _latitude = p?.latitude;
    _longitude = p?.longitude;
    _googlePlaceId = p?.googlePlaceId;
    _mapsUrl = p?.mapsUrl;
    _pickedFromMap = p?.canOpenMap == true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _countryController.dispose();
    _memoController.dispose();
    _naverLinkController.dispose();
    super.dispose();
  }

  Future<void> _openPlaceSearch(PlaceSearchRegion region) async {
    final result = await Navigator.of(context).push<PlaceSelection>(
      MaterialPageRoute(
        builder: (_) => PlaceSearchPage(region: region),
      ),
    );
    if (result == null || !mounted) return;

    setState(() {
      _nameController.text = result.name;
      _addressController.text = result.address ?? '';
      _countryController.text = result.countryCode ?? '';
      _latitude = result.latitude;
      _longitude = result.longitude;
      _googlePlaceId = result.googlePlaceId;
      if (region == PlaceSearchRegion.korea) {
        // A는 좌표로 열고, B는 사용자가 따로 붙여넣음
        _mapsUrl = null;
        _naverLinkController.clear();
      } else {
        _mapsUrl = result.mapsUrl;
      }
      _pickedFromMap = true;
    });
  }

  Future<void> _chooseRegionAndSearch() async {
    final region = await showModalBottomSheet<PlaceSearchRegion>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '어디서 검색할까요?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '국내는 네이버, 해외는 Google로 검색합니다.\n'
                  '지도에서 보기와도 같은 서비스로 열립니다.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('국내'),
                  subtitle: const Text('네이버 지도 검색'),
                  onTap: () =>
                      Navigator.pop(context, PlaceSearchRegion.korea),
                ),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('해외'),
                  subtitle: const Text('Google 지도 검색'),
                  onTap: () =>
                      Navigator.pop(context, PlaceSearchRegion.overseas),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (region == null || !mounted) return;
    await _openPlaceSearch(region);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('장소를 검색해 선택해주세요')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = ref.read(travelRepositoryProvider);
      final mapsUrl = _isKorea
          ? (_naverLinkController.text.trim().isEmpty
              ? null
              : _naverLinkController.text.trim())
          : _mapsUrl;

      if (widget.isEditing) {
        await repo.updatePlace(
          place: widget.place!,
          name: _nameController.text,
          address: _addressController.text,
          countryCode: _countryController.text,
          latitude: _latitude,
          longitude: _longitude,
          memo: _memoController.text,
          googlePlaceId: _googlePlaceId,
          mapsUrl: mapsUrl,
        );
        ref.invalidate(travelPlacesProvider(widget.travelId));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('장소를 수정했습니다')),
        );
        context.pop();
      } else {
        final created = await repo.createPlace(
          travelId: widget.travelId,
          name: _nameController.text,
          address: _addressController.text,
          countryCode: _countryController.text,
          latitude: _latitude,
          longitude: _longitude,
          memo: _memoController.text,
          googlePlaceId: _googlePlaceId,
          mapsUrl: mapsUrl,
        );
        ref.invalidate(travelPlacesProvider(widget.travelId));
        if (!mounted) return;

        final addToSchedule = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('일정에 추가할까요?'),
            content: Text(
              '「${created.name}」을(를) 일정에도 넣을까요?\n'
              '일정 연결은 다음 단계에서 본격적으로 제공됩니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('아니오'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('예'),
              ),
            ],
          ),
        );

        if (!mounted) return;
        context.go('${AppRoutes.travels}/${widget.travelId}/places');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              addToSchedule == true
                  ? '장소를 저장했습니다. 일정 추가는 7단계에서 이어집니다.'
                  : '장소 후보로 저장했습니다.',
            ),
          ),
        );
      }
    } on TravelException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _nameController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? '장소 수정' : '장소 추가'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              ElevatedButton.icon(
                onPressed: _loading ? null : _chooseRegionAndSearch,
                icon: const Icon(Icons.map_outlined),
                label: Text(
                  hasSelection ? '다른 장소 검색' : '국내/해외 장소 검색·선택',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '국내 → 네이버 검색, 해외 → Google 검색.\n'
                '선택한 장소의 이름·주소·좌표가 자동으로 채워집니다.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (!hasSelection)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '아직 선택된 장소가 없습니다.\n위에서 장소를 검색해 주세요.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              else ...[
                if (_pickedFromMap)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      avatar: const Icon(Icons.check_circle, size: 18),
                      label: const Text('지도에서 선택됨'),
                      backgroundColor: AppColors.surfaceMuted,
                      side: BorderSide.none,
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: '장소 이름',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return '장소를 선택해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  readOnly: true,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '주소',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _countryController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: '국가',
                    helperText: 'KR이면 네이버 지도, 그 외는 Google 지도로 엽니다',
                  ),
                ),
                if (_latitude != null && _longitude != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '좌표: ${_latitude!.toStringAsFixed(5)}, '
                    '${_longitude!.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (_isKorea) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _naverLinkController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '네이버 지도 링크 (선택)',
                      hintText: 'map.naver.com/.../place/숫자',
                      helperText:
                          '지도에서 보기는 좌표로 네이버 지도 앱을 엽니다.\n'
                          '리뷰·사진 상세가 필요할 때만 공유 링크를 붙여넣으세요.',
                      helperMaxLines: 3,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _memoController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '메모',
                  ),
                ),
                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(widget.isEditing ? '저장' : '등록'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
