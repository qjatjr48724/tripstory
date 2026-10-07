import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/config/env.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../data/travel_repository.dart';
import '../../domain/expense.dart';
import '../../domain/place.dart';
import '../../domain/reservation.dart';
import '../../domain/schedule.dart';
import '../../domain/settlement.dart';
import '../../domain/travel.dart';
import '../../domain/travel_link.dart';
import '../../domain/travel_member.dart';
import '../../domain/travel_photo.dart';

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

final travelSchedulesProvider = FutureProvider.autoDispose
    .family<List<ScheduleItem>, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchSchedules(travelId);
});

final travelExpensesProvider = FutureProvider.autoDispose
    .family<List<Expense>, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchExpenses(travelId);
});

final travelSettlementsProvider = FutureProvider.autoDispose
    .family<List<Settlement>, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchSettlements(travelId);
});

final travelReservationsProvider = FutureProvider.autoDispose
    .family<List<Reservation>, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchReservations(travelId);
});

final travelPhotosProvider = FutureProvider.autoDispose
    .family<List<TravelPhoto>, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchTravelPhotos(travelId);
});

final travelLinksProvider = FutureProvider.autoDispose
    .family<List<TravelLink>, String>((ref, travelId) async {
  return ref.read(travelRepositoryProvider).fetchTravelLinks(travelId);
});
