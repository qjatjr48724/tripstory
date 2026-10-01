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

      return PlaceSelection(
        name: name.isEmpty ? query : name,
        address: address.isEmpty ? null : address,
        countryCode: 'KR',
        latitude: lat,
        longitude: lng,
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
