import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/env.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/google_places_client.dart';
import '../../data/naver_local_client.dart';

final googlePlacesClientProvider = Provider<GooglePlacesClient>((ref) {
  return GooglePlacesClient();
});

final naverLocalClientProvider = Provider<NaverLocalClient>((ref) {
  return NaverLocalClient();
});

enum PlaceSearchRegion {
  /// 국내 — 네이버 지역 검색
  korea,

  /// 해외 — Google Places
  overseas,
}

class _SearchUi {
  const _SearchUi({
    this.loading = false,
    this.error,
    this.googleSuggestions = const [],
    this.naverResults = const [],
    this.hint = '2글자 이상 입력해 검색하세요',
  });

  final bool loading;
  final String? error;
  final List<PlaceSuggestion> googleSuggestions;
  final List<PlaceSelection> naverResults;
  final String hint;

  bool get isEmpty => googleSuggestions.isEmpty && naverResults.isEmpty;
}

/// 지역에 맞는 지도 서비스로 장소를 검색·선택한다.
class PlaceSearchPage extends ConsumerStatefulWidget {
  const PlaceSearchPage({
    super.key,
    required this.region,
  });

  final PlaceSearchRegion region;

  @override
  ConsumerState<PlaceSearchPage> createState() => _PlaceSearchPageState();
}

class _PlaceSearchPageState extends ConsumerState<PlaceSearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _ui = ValueNotifier<_SearchUi>(const _SearchUi());
  final _loadingDetails = ValueNotifier<bool>(false);
  Timer? _debounce;

  bool get _isKorea => widget.region == PlaceSearchRegion.korea;

  bool get _configured => _isKorea
      ? Env.isNaverSearchConfigured
      : Env.isGooglePlacesConfigured;

  String get _title => _isKorea ? '국내 장소 검색' : '해외 장소 검색';

  String get _hintText =>
      _isKorea ? '장소 이름·주소 (네이버)' : '장소 이름·주소 (Google)';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focusNode.dispose();
    _ui.dispose();
    _loadingDetails.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final value = _controller.value;
    if (value.isComposingRangeValid) {
      _debounce?.cancel();
      return;
    }
    _scheduleSearch(value.text);
  }

  void _scheduleSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _search(text);
    });
  }

  Future<void> _search(String raw) async {
    final query = raw.trim();
    if (query.length < 2) {
      _ui.value = const _SearchUi();
      return;
    }

    _ui.value = _SearchUi(
      loading: true,
      hint: '검색 중…',
      googleSuggestions: _ui.value.googleSuggestions,
      naverResults: _ui.value.naverResults,
    );

    try {
      if (_isKorea) {
        final results =
            await ref.read(naverLocalClientProvider).search(query);
        if (!mounted) return;
        if (_controller.value.isComposingRangeValid) return;
        if (_controller.text.trim() != query) return;
        _ui.value = _SearchUi(
          naverResults: results,
          hint: results.isEmpty ? '검색 결과가 없습니다' : '',
        );
      } else {
        final results =
            await ref.read(googlePlacesClientProvider).autocomplete(query);
        if (!mounted) return;
        if (_controller.value.isComposingRangeValid) return;
        if (_controller.text.trim() != query) return;
        _ui.value = _SearchUi(
          googleSuggestions: results,
          hint: results.isEmpty ? '검색 결과가 없습니다' : '',
        );
      }
    } on PlaceSearchException catch (e) {
      if (!mounted) return;
      if (_controller.value.isComposingRangeValid) return;
      _ui.value = _SearchUi(error: e.message, hint: '검색 결과가 없습니다');
    } catch (_) {
      if (!mounted) return;
      if (_controller.value.isComposingRangeValid) return;
      _ui.value = const _SearchUi(
        error: '장소 검색 중 오류가 발생했습니다.',
        hint: '검색 결과가 없습니다',
      );
    }
  }

  Future<void> _selectGoogle(PlaceSuggestion suggestion) async {
    _loadingDetails.value = true;
    try {
      final detail = await ref
          .read(googlePlacesClientProvider)
          .fetchDetails(suggestion.placeId);
      if (!mounted) return;
      Navigator.of(context).pop(detail);
    } on PlaceSearchException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      _loadingDetails.value = false;
    }
  }

  void _selectNaver(PlaceSelection place) {
    Navigator.of(context).pop(place);
  }

  void _clearQuery() {
    _debounce?.cancel();
    _controller.clear();
    _ui.value = const _SearchUi();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(_title),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  autofocus: _configured,
                  enabled: _configured,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: _hintText,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: _clearQuery,
                      icon: const Icon(Icons.clear),
                    ),
                  ),
                ),
              ),
              if (!_configured)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.vpn_key_outlined,
                          size: 40,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isKorea
                              ? '네이버 검색 API 키가 필요합니다'
                              : 'Google Places API 키가 필요합니다',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isKorea
                              ? '.env에 NAVER_CLIENT_ID / NAVER_CLIENT_SECRET을\n'
                                  '넣은 뒤 앱을 다시 시작해 주세요.\n\n'
                                  '네이버 클라우드 → NAVER API HUB에서\n'
                                  '「지역」검색 API를 등록하세요.'
                              : '.env에 GOOGLE_PLACES_API_KEY를 넣은 뒤\n'
                                  '앱을 다시 시작해 주세요.\n\n'
                                  'Google Cloud에서 Places API (New)를 활성화해야 합니다.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ValueListenableBuilder<_SearchUi>(
                    valueListenable: _ui,
                    builder: (context, ui, _) {
                      return Column(
                        children: [
                          SizedBox(
                            height: 2,
                            child: ui.loading
                                ? const LinearProgressIndicator(minHeight: 2)
                                : const SizedBox.expand(),
                          ),
                          if (ui.error != null)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                ui.error!,
                                style: const TextStyle(color: AppColors.error),
                              ),
                            ),
                          Expanded(
                            child: ui.isEmpty
                                ? Center(
                                    child: Text(
                                      ui.hint,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  )
                                : _isKorea
                                    ? ListView.separated(
                                        itemCount: ui.naverResults.length,
                                        separatorBuilder: (context, index) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final item = ui.naverResults[index];
                                          return ListTile(
                                            leading: const Icon(
                                              Icons.place_outlined,
                                            ),
                                            title: Text(item.name),
                                            subtitle: item.address == null
                                                ? null
                                                : Text(item.address!),
                                            onTap: () => _selectNaver(item),
                                          );
                                        },
                                      )
                                    : ListView.separated(
                                        itemCount:
                                            ui.googleSuggestions.length,
                                        separatorBuilder: (context, index) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, index) {
                                          final item =
                                              ui.googleSuggestions[index];
                                          return ValueListenableBuilder<bool>(
                                            valueListenable: _loadingDetails,
                                            builder: (context, busy, _) {
                                              return ListTile(
                                                leading: const Icon(
                                                  Icons.place_outlined,
                                                ),
                                                title: Text(item.primaryText),
                                                subtitle: item.subtitle.isEmpty
                                                    ? null
                                                    : Text(item.subtitle),
                                                onTap: busy
                                                    ? null
                                                    : () =>
                                                        _selectGoogle(item),
                                              );
                                            },
                                          );
                                        },
                                      ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _loadingDetails,
            builder: (context, busy, _) {
              if (!busy) return const SizedBox.shrink();
              return const ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              );
            },
          ),
        ],
      ),
    );
  }
}
