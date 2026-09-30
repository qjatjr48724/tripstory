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
    return dotenv.env[key]?.trim() ?? '';
  }

  static String get supabaseUrl => _read('SUPABASE_URL');

  static String get supabaseAnonKey => _read('SUPABASE_ANON_KEY');

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
