import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/travel_repository.dart';
import '../../domain/travel.dart';

final travelRepositoryProvider = Provider<TravelRepository>((ref) {
  final client = Env.isSupabaseReady ? Supabase.instance.client : null;
  return TravelRepository(client);
});

/// 내 여행 목록. 로그인 세션이 바뀌면 다시 불러온다.
final myTravelsProvider = FutureProvider.autoDispose<List<Travel>>((ref) async {
  ref.watch(authStateProvider);
  if (!Env.isSupabaseReady) return [];
  return ref.read(travelRepositoryProvider).fetchMyTravels();
});

final travelDetailProvider =
    FutureProvider.autoDispose.family<Travel, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchTravel(travelId);
});
