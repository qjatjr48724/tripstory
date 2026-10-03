import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';
import 'google_places_client.dart';

/// 네이버 지역 검색 — NAVER API HUB (NCP)
/// https://api.ncloud-docs.com/docs/naver-api-hub-search-local
///
/// 2026-07-31 이후 개발자센터에서는 검색 API 신규 신청이 불가하고
/// NAVER Cloud Platform > NAVER API HUB에서 발급합니다.
class NaverLocalClient {
  NaverLocalClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const _searchUrl =
      'https://naverapihub.apigw.ntruss.com/search/v1/local';

  bool get isConfigured =>
      Env.naverClientId.isNotEmpty && Env.naverClientSecret.isNotEmpty;

  /// 검색 결과 항목을 바로 [PlaceSelection]으로 반환 (추가 Details 호출 없음)
  Future<List<PlaceSelection>> search(String input) async {
    final id = Env.naverClientId;
    final secret = Env.naverClientSecret;
    if (id.isEmpty || secret.isEmpty) {
      throw PlaceSearchException(
        '네이버 API 키가 없습니다. .env에 NAVER_CLIENT_ID / NAVER_CLIENT_SECRET을 설정하세요.',
      );
    }

    final query = input.trim();
    if (query.length < 2) return [];

    final uri = Uri.parse(_searchUrl).replace(queryParameters: {
      'query': query,
      'display': '5',
      'start': '1',
      'sort': 'random',
      'format': 'json',
    });

    final response = await _http.get(
      uri,
      headers: {
        'X-NCP-APIGW-API-KEY-ID': id,
        'X-NCP-APIGW-API-KEY': secret,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlaceSearchException(_httpError(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = body['items'] as List? ?? [];

    return items.map((raw) {
      final item = Map<String, dynamic>.from(raw as Map);
      final name = _stripHtml(item['title'] as String? ?? '').trim();
      final road = (item['roadAddress'] as String?)?.trim() ?? '';
      final jibun = (item['address'] as String?)?.trim() ?? '';
      final address = road.isNotEmpty ? road : jibun;

      // WGS84 — 소수점이 없는 정수면 /1e7, 이미 소수면 그대로
      final lng = _coord(item['mapx']);
      final lat = _coord(item['mapy']);
      // item['link']는 업체 홈페이지인 경우가 많아 지도 URL로 쓰지 않는다.
      final placeName = name.isEmpty ? query : name;

      return PlaceSelection(
        name: placeName,
        address: address.isEmpty ? null : address,
        countryCode: 'KR',
        latitude: lat,
        longitude: lng,
        // mapsUrl은 사용자가 붙여넣는 플레이스 상세 링크(B)용.
        // 검색 API에는 Place ID가 없어 여기서는 채우지 않는다.
        mapsUrl: null,
      );
    }).where((p) => p.name.isNotEmpty).toList();
  }

  static double? _coord(Object? raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    if (s.contains('.')) return double.tryParse(s);
    final n = int.tryParse(s);
    if (n == null) return null;
    return n / 1e7;
  }

  static String _stripHtml(String input) {
    return input.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  String _httpError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final message = body['errorMessage'] as String? ??
          body['message'] as String? ??
          body['error']?['message'] as String?;
      if (message != null && message.isNotEmpty) return message;
    } catch (_) {}
    if (response.statusCode == 401 || response.statusCode == 403) {
      return '네이버 API 인증에 실패했습니다. Client ID/Secret을 확인하세요.';
    }
    return '네이버 장소 검색에 실패했습니다. (${response.statusCode})';
  }
}

/// tripstory Android applicationId / iOS bundle용 appname
const kNaverMapAppName = 'com.tripstory.tripstory';

/// 네이버 지도 앱에 등록 좌표+이름 마커를 표시하는 URL Scheme.
/// https://guide.ncloud-docs.com/docs/maps-url-scheme
Uri? naverMapAppPlaceUri({
  required String name,
  double? latitude,
  double? longitude,
}) {
  if (latitude == null || longitude == null) return null;
  final encoded = Uri.encodeComponent(name.trim().isEmpty ? '장소' : name.trim());
  return Uri.parse(
    'nmap://place?lat=$latitude&lng=$longitude'
    '&name=$encoded&appname=$kNaverMapAppName',
  );
}

/// 네이버 지도 앱이 없을 때 Play 스토어로 보내는 Android Intent URL
Uri? naverMapAndroidIntentUri({
  required String name,
  double? latitude,
  double? longitude,
}) {
  if (latitude == null || longitude == null) return null;
  final encoded = Uri.encodeComponent(name.trim().isEmpty ? '장소' : name.trim());
  return Uri.parse(
    'intent://place?lat=$latitude&lng=$longitude'
    '&name=$encoded&appname=$kNaverMapAppName'
    '#Intent;scheme=nmap;action=android.intent.action.VIEW;'
    'category=android.intent.category.BROWSABLE;'
    'package=com.nhn.android.nmap;end',
  );
}

/// 웹 폴백: 네이버 지도에서 해당 좌표에 장소 핀 (검색 목록 아님)
String? naverPlacePinUrl({
  required String name,
  double? latitude,
  double? longitude,
}) {
  if (latitude == null || longitude == null) return null;
  final encoded = Uri.encodeComponent(name.trim().isEmpty ? '장소' : name.trim());
  return 'https://map.naver.com/v5/entry/address/$longitude,$latitude/$encoded';
}

/// 네이버 플레이스 상세 URL인지 (`/place/{id}` 등)
bool isNaverPlaceDetailUrl(String? url) {
  if (url == null) return false;
  final u = url.trim().toLowerCase();
  if (u.isEmpty) return false;
  final isNaverHost =
      u.contains('map.naver.com') || u.contains('naver.me') || u.contains('place.naver.com');
  if (!isNaverHost) return false;
  return u.contains('naver.me') ||
      u.contains('/place/') ||
      u.contains('placepath') ||
      u.contains('/entry/place');
}
