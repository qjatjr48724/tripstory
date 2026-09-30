import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Env.load();

  if (Env.isSupabaseConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
    Env.supabaseInitialized = true;
  } else if (kDebugMode) {
    debugPrint(
      '[tripstory] Supabase 미설정: .env의 SUPABASE_URL / SUPABASE_ANON_KEY를 확인하세요.',
    );
  }

  runApp(
    const ProviderScope(
      child: TripStoryApp(),
    ),
  );
}
