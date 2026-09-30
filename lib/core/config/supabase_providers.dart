import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Supabase 클라이언트. 초기화가 끝난 뒤에만 사용한다.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (!Env.isSupabaseReady) {
    throw StateError(
      'Supabase가 준비되지 않았습니다. .env와 초기화를 확인하세요.',
    );
  }
  return Supabase.instance.client;
});
