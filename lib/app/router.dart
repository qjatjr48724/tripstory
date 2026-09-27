import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/env.dart';
import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/pages/signup_page.dart';
import '../features/auth/presentation/pages/splash_page.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import '../features/travel/presentation/pages/travel_list_page.dart';

/// 라우트 경로 상수
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String travels = '/travels';
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(authRefreshListenableProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final hasSession = Env.isSupabaseReady &&
          ref.read(authRepositoryProvider).currentSession != null;
      final loc = state.matchedLocation;

      final isSplash = loc == AppRoutes.splash;
      final isAuthRoute =
          loc == AppRoutes.login || loc == AppRoutes.signup;

      if (isSplash) return null;

      if (!hasSession && !isAuthRoute) {
        return AppRoutes.login;
      }
      if (hasSession && isAuthRoute) {
        return AppRoutes.travels;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        name: 'signup',
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: AppRoutes.travels,
        name: 'travels',
        builder: (context, state) => const TravelListPage(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('페이지를 찾을 수 없습니다.\n${state.uri}'),
      ),
    ),
  );
});
