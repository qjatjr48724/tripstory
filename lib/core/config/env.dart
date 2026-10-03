import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 환경 변수 접근 (Supabase 등)
///
/// `.env` 파일을 사용하며, 실제 키는 저장소에 커밋하지 않는다.
/// 템플릿은 `.env.example`을 참고한다.
class Env {
  Env._();

  /// [main]에서 [Supabase.initialize] 성공 시 true
  static bool supabaseInitialized = false;

  static String _read(String key) {
    if (!dotenv.isInitialized) return '';
    var value = dotenv.env[key]?.trim() ?? '';
    // .env에서 "값" 형태로 넣은 경우 따옴표 제거
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }

  static String get supabaseUrl => _read('SUPABASE_URL');

  static String get supabaseAnonKey => _read('SUPABASE_ANON_KEY');

  /// Google Places API (New) 키 — 해외 장소 검색
  static String get googlePlacesApiKey => _read('GOOGLE_PLACES_API_KEY');

  static bool get isGooglePlacesConfigured => googlePlacesApiKey.isNotEmpty;

  /// 네이버 검색 API (지역) — 국내 장소 검색
  static String get naverClientId => _read('NAVER_CLIENT_ID');

  static String get naverClientSecret => _read('NAVER_CLIENT_SECRET');

  static bool get isNaverSearchConfigured =>
      naverClientId.isNotEmpty && naverClientSecret.isNotEmpty;

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// `.env` 설정과 Supabase 초기화가 모두 완료된 경우
  static bool get isSupabaseReady =>
      isSupabaseConfigured && supabaseInitialized;

  static Future<void> load() async {
    await dotenv.load(fileName: '.env', isOptional: true);
    if (!isSupabaseConfigured) {
      await dotenv.load(fileName: '.env.example', isOptional: true);
    }
  }
}
