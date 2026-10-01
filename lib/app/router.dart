import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/config/env.dart';
import '../features/auth/presentation/pages/login_page.dart';
import '../features/auth/presentation/pages/signup_page.dart';
import '../features/auth/presentation/pages/splash_page.dart';
import '../features/auth/presentation/providers/auth_providers.dart';
import '../features/travel/domain/place.dart';
import '../features/travel/presentation/pages/create_travel_page.dart';
import '../features/travel/presentation/pages/place_form_page.dart';
import '../features/travel/presentation/pages/travel_detail_page.dart';
import '../features/travel/presentation/pages/travel_list_page.dart';
import '../features/travel/presentation/pages/travel_members_page.dart';
import '../features/travel/presentation/pages/travel_places_page.dart';

/// 라우트 경로 상수
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String travels = '/travels';
  static const String createTravel = '/travels/create';
}

/// 목록 등에서 하위 화면 복귀 시 새로고침용
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(authRefreshListenableProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    observers: [appRouteObserver],
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
        routes: [
          GoRoute(
            path: 'create',
            name: 'createTravel',
            builder: (context, state) => const CreateTravelPage(),
          ),
          GoRoute(
            path: ':travelId',
            name: 'travelDetail',
            builder: (context, state) {
              final id = state.pathParameters['travelId']!;
              return TravelDetailPage(travelId: id);
            },
            routes: [
              GoRoute(
                path: 'members',
                name: 'travelMembers',
                builder: (context, state) {
                  final id = state.pathParameters['travelId']!;
                  return TravelMembersPage(travelId: id);
                },
              ),
              GoRoute(
                path: 'places',
                name: 'travelPlaces',
                builder: (context, state) {
                  final id = state.pathParameters['travelId']!;
                  return TravelPlacesPage(travelId: id);
                },
                routes: [
                  GoRoute(
                    path: 'new',
                    name: 'placeCreate',
                    builder: (context, state) {
                      final id = state.pathParameters['travelId']!;
                      return PlaceFormPage(travelId: id);
                    },
                  ),
                  GoRoute(
                    path: ':placeId/edit',
                    name: 'placeEdit',
                    builder: (context, state) {
                      final id = state.pathParameters['travelId']!;
                      final place = state.extra;
                      if (place is! Place) {
                        return Scaffold(
                          appBar: AppBar(),
                          body: const Center(
                            child: Text('장소 정보를 불러오지 못했습니다.'),
                          ),
                        );
                      }
                      return PlaceFormPage(travelId: id, place: place);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('페이지를 찾을 수 없습니다.\n${state.uri}'),
      ),
    ),
  );
});
