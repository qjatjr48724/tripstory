import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/travel_repository.dart';
import '../../domain/place.dart';
import '../../domain/travel.dart';
import '../../domain/travel_member.dart';

final travelRepositoryProvider = Provider<TravelRepository>((ref) {
  final client = Env.isSupabaseReady ? Supabase.instance.client : null;
  return TravelRepository(client);
});

/// 내 여행 목록. 로그인 세션이 바뀌면 다시 불러온다.
final myTravelsProvider = FutureProvider.autoDispose<List<Travel>>((ref) async {
  ref.watch(authStateProvider);
  if (!Env.isSupabaseReady) return [];

  final session =
      await ref.read(authRepositoryProvider).ensureValidSession();
  if (session == null) return [];

  return ref.read(travelRepositoryProvider).fetchMyTravels();
});

final travelDetailProvider =
    FutureProvider.autoDispose.family<Travel, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchTravel(travelId);
});

final travelMembersProvider = FutureProvider.autoDispose
    .family<List<TravelMember>, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchMembers(travelId);
});

final pendingOwnershipTransferProvider = FutureProvider.autoDispose
    .family<OwnershipTransferRequest?, String>((ref, travelId) async {
  return ref
      .read(travelRepositoryProvider)
      .fetchPendingOwnershipTransfer(travelId);
});

final travelPlacesProvider =
    FutureProvider.autoDispose.family<List<Place>, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchPlaces(travelId);
});
