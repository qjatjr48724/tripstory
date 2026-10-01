import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/env.dart';

class PlaceSearchException implements Exception {
  PlaceSearchException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Google Places에서 선택한 장소 결과
class PlaceSelection {
  const PlaceSelection({
    required this.name,
    this.address,
    this.countryCode,
    this.latitude,
    this.longitude,
    this.googlePlaceId,
    this.mapsUrl,
  });

  final String name;
  final String? address;
  final String? countryCode;
  final double? latitude;
  final double? longitude;
  final String? googlePlaceId;
  /// Google Maps / 네이버 등 해당 장소 상세로 바로 여는 URL
  final String? mapsUrl;
}

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    this.secondaryText,
  });

  final String placeId;
  final String primaryText;
  final String? secondaryText;

  String get subtitle => secondaryText ?? '';
}

/// Google Places API (New) — Autocomplete + Place Details
class GooglePlacesClient {
  GooglePlacesClient({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const _autocompleteUrl =
      'https://places.googleapis.com/v1/places:autocomplete';

  bool get isConfigured => Env.googlePlacesApiKey.isNotEmpty;

  Future<List<PlaceSuggestion>> autocomplete(String input) async {
    final key = Env.googlePlacesApiKey;
    if (key.isEmpty) {
      throw PlaceSearchException(
        'Google Places API 키가 없습니다. .env에 GOOGLE_PLACES_API_KEY를 설정하세요.',
      );
    }

    final query = input.trim();
    if (query.length < 2) return [];

    final response = await _http.post(
      Uri.parse(_autocompleteUrl),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': key,
      },
      body: jsonEncode({
        'input': query,
        'languageCode': 'ko',
        'regionCode': 'KR',
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlaceSearchException(_httpError(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final suggestions = body['suggestions'] as List? ?? [];

    return suggestions
        .map((raw) {
          final map = Map<String, dynamic>.from(raw as Map);
          final prediction =
              Map<String, dynamic>.from(map['placePrediction'] as Map? ?? {});
          final placeId = prediction['placeId'] as String?;
          if (placeId == null || placeId.isEmpty) return null;

          final text =
              Map<String, dynamic>.from(prediction['text'] as Map? ?? {});
          final structured = Map<String, dynamic>.from(
            prediction['structuredFormat'] as Map? ?? {},
          );
          final main = Map<String, dynamic>.from(
            structured['mainText'] as Map? ?? {},
          );
          final secondary = Map<String, dynamic>.from(
            structured['secondaryText'] as Map? ?? {},
          );

          return PlaceSuggestion(
            placeId: placeId,
            primaryText: (main['text'] as String?) ??
                (text['text'] as String?) ??
                placeId,
            secondaryText: secondary['text'] as String?,
          );
        })
        .whereType<PlaceSuggestion>()
        .toList();
  }

  Future<PlaceSelection> fetchDetails(String placeId) async {
    final key = Env.googlePlacesApiKey;
    if (key.isEmpty) {
      throw PlaceSearchException(
        'Google Places API 키가 없습니다. .env에 GOOGLE_PLACES_API_KEY를 설정하세요.',
      );
    }

    // languageCode는 헤더가 아니라 쿼리 파라미터 (미지정 시 기본 en)
    final uri = Uri.parse(
      'https://places.googleapis.com/v1/places/$placeId',
    ).replace(queryParameters: {
      'languageCode': 'ko',
      'regionCode': 'KR',
    });
    final response = await _http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask':
            'id,displayName,formattedAddress,location,addressComponents,googleMapsUri',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PlaceSearchException(_httpError(response));
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final displayName =
        Map<String, dynamic>.from(body['displayName'] as Map? ?? {});
    final location =
        Map<String, dynamic>.from(body['location'] as Map? ?? {});
    final components = body['addressComponents'] as List? ?? [];

    String? countryCode;
    for (final raw in components) {
      final c = Map<String, dynamic>.from(raw as Map);
      final types = (c['types'] as List? ?? []).cast<String>();
      if (types.contains('country')) {
        countryCode = c['shortText'] as String? ?? c['shortName'] as String?;
        break;
      }
    }

    final name = (displayName['text'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      throw PlaceSearchException('장소 이름을 가져오지 못했습니다.');
    }

    final rawId = body['id'] as String? ?? placeId;
    // Places API (New) id 는 "places/ChIJ..." 형태일 수 있음
    final placeIdOnly = rawId.startsWith('places/')
        ? rawId.substring('places/'.length)
        : rawId;

    return PlaceSelection(
      name: name,
      address: body['formattedAddress'] as String?,
      countryCode: countryCode?.toUpperCase(),
      latitude: (location['latitude'] as num?)?.toDouble(),
      longitude: (location['longitude'] as num?)?.toDouble(),
      googlePlaceId: placeIdOnly,
      mapsUrl: body['googleMapsUri'] as String?,
    );
  }

  String _httpError(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'] as Map<String, dynamic>?;
      final message = error?['message'] as String?;
      if (message != null && message.isNotEmpty) {
        if (message.toLowerCase().contains('api key')) {
          return 'Places API 키 또는 API 활성화 설정을 확인해주세요.';
        }
        return message;
      }
    } catch (_) {}
    return '장소 검색에 실패했습니다. (${response.statusCode})';
  }
}
