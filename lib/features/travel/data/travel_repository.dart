import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/constants/roles.dart';
import '../domain/expense.dart';
import '../domain/place.dart';
import '../domain/schedule.dart';
import '../domain/settlement.dart';
import '../domain/travel.dart';
import '../domain/travel_member.dart';

class TravelException implements Exception {
  TravelException(this.message);
  final String message;

  @override
  String toString() => message;
}

class TravelRepository {
  TravelRepository(this._client);

  final SupabaseClient? _client;

  SupabaseClient get _requireClient {
    final client = _client;
    if (client == null || !Env.isSupabaseReady) {
      throw TravelException('Supabase가 준비되지 않았습니다.');
    }
    return client;
  }

  /// 내가 active 또는 pending 멤버인 여행 목록
  Future<List<Travel>> fetchMyTravels() async {
    final client = _requireClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw TravelException('로그인이 필요합니다.');
    }

    try {
      final rows = await client
          .from('travel_members')
          .select('role, member_status:status, travels(*)')
          .eq('user_id', userId)
          .inFilter('status', ['active', 'pending'])
          .order('joined_at', ascending: false);

      final list = <Travel>[];
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final travelJson = map['travels'];
        if (travelJson == null) continue;
        final travelMap = Map<String, dynamic>.from(travelJson as Map);
        final travelStatus = travelMap['status'] as String? ?? 'active';
        if (travelStatus == 'trashed') continue;

        final memberStatus = map['member_status'] as String? ??
            map['status'] as String? ??
            'active';

        list.add(
          Travel.fromJson(
            travelMap,
            myRole: TravelRoleX.fromDb(map['role'] as String? ?? 'member'),
            myMemberStatus: MemberStatus.fromDb(memberStatus),
          ),
        );
      }

      list.sort((a, b) => b.startDate.compareTo(a.startDate));
      return list;
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('여행 목록을 불러오지 못했습니다.');
    }
  }

  Future<Travel> createTravel({
    required String name,
    required DateTime startDate,
    required DateTime endDate,
    required String region,
    String? memo,
  }) async {
    final client = _requireClient;
    try {
      final result = await client.rpc(
        'create_travel',
        params: {
          'p_name': name.trim(),
          'p_start_date': _dateOnly(startDate),
          'p_end_date': _dateOnly(endDate),
          'p_region': region.trim(),
          'p_memo': (memo == null || memo.trim().isEmpty) ? null : memo.trim(),
        },
      );

      final map = Map<String, dynamic>.from(result as Map);
      return Travel.fromJson(
        map,
        myRole: TravelRole.owner,
        myMemberStatus: MemberStatus.active,
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('여행 생성에 실패했습니다.');
    }
  }

  /// 초대코드 참여 결과 (pending이면 승인 대기)
  Future<Travel> joinByInviteCode(String inviteCode) async {
    final client = _requireClient;
    final code = inviteCode.trim();
    if (code.length != 6) {
      throw TravelException('초대코드는 6자리입니다.');
    }

    try {
      final result = await client.rpc(
        'join_travel_by_invite',
        params: {'p_invite_code': code},
      );
      final map = Map<String, dynamic>.from(result as Map);
      final travelId = map['id'] as String;
      return fetchTravel(travelId);
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('여행 참여에 실패했습니다.');
    }
  }

  Future<Travel> fetchTravel(String travelId) async {
    final client = _requireClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw TravelException('로그인이 필요합니다.');
    }

    try {
      final row = await client
          .from('travel_members')
          .select('role, member_status:status, travels(*)')
          .eq('travel_id', travelId)
          .eq('user_id', userId)
          .inFilter('status', ['active', 'pending'])
          .maybeSingle();

      if (row == null) {
        throw TravelException('여행을 찾을 수 없거나 권한이 없습니다.');
      }

      final map = Map<String, dynamic>.from(row);
      final travelMap = Map<String, dynamic>.from(map['travels'] as Map);
      final memberStatus = map['member_status'] as String? ??
          map['status'] as String? ??
          'active';
      return Travel.fromJson(
        travelMap,
        myRole: TravelRoleX.fromDb(map['role'] as String? ?? 'member'),
        myMemberStatus: MemberStatus.fromDb(memberStatus),
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('여행 정보를 불러오지 못했습니다.');
    }
  }

  Future<List<TravelMember>> fetchMembers(String travelId) async {
    final client = _requireClient;
    final userId = client.auth.currentUser?.id;

    try {
      final rows = await client
          .from('travel_members')
          .select()
          .eq('travel_id', travelId)
          .inFilter('status', ['active', 'pending'])
          .order('joined_at');

      return (rows as List)
          .map(
            (row) => TravelMember.fromJson(
              Map<String, dynamic>.from(row as Map),
              currentUserId: userId,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('구성원 목록을 불러오지 못했습니다.');
    }
  }

  Future<void> acceptTravelJoin(String memberId) async {
    final client = _requireClient;
    try {
      await client.rpc(
        'accept_travel_join',
        params: {'p_member_id': memberId},
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('참가 수락에 실패했습니다.');
    }
  }

  Future<void> rejectTravelJoin(String memberId) async {
    final client = _requireClient;
    try {
      await client.rpc(
        'reject_travel_join',
        params: {'p_member_id': memberId},
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('참가 거절에 실패했습니다.');
    }
  }

  Future<Travel> reissueInviteCode(String travelId) async {
    final client = _requireClient;
    try {
      final result = await client.rpc(
        'reissue_invite_code',
        params: {'p_travel_id': travelId},
      );
      final map = Map<String, dynamic>.from(result as Map);
      return Travel.fromJson(
        map,
        myRole: TravelRole.owner,
        myMemberStatus: MemberStatus.active,
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('초대코드 재발급에 실패했습니다.');
    }
  }

  Future<void> assignTreasurer({
    required String travelId,
    String? memberId,
  }) async {
    final client = _requireClient;
    try {
      await client.rpc(
        'assign_treasurer',
        params: {
          'p_travel_id': travelId,
          'p_member_id': memberId,
        },
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('총무 지정에 실패했습니다.');
    }
  }

  Future<void> kickMember({
    required String travelId,
    required String memberId,
  }) async {
    final client = _requireClient;
    try {
      await client.rpc(
        'kick_member',
        params: {
          'p_travel_id': travelId,
          'p_member_id': memberId,
        },
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('구성원 퇴장 처리에 실패했습니다.');
    }
  }

  Future<void> leaveTravel(String travelId) async {
    final client = _requireClient;
    try {
      await client.rpc(
        'leave_travel',
        params: {'p_travel_id': travelId},
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('여행 나가기에 실패했습니다.');
    }
  }

  Future<OwnershipTransferRequest?> fetchPendingOwnershipTransfer(
    String travelId,
  ) async {
    final client = _requireClient;
    try {
      final row = await client
          .from('ownership_transfer_requests')
          .select()
          .eq('travel_id', travelId)
          .eq('status', 'pending')
          .maybeSingle();

      if (row == null) return null;
      return OwnershipTransferRequest.fromJson(
        Map<String, dynamic>.from(row),
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('이전 요청을 불러오지 못했습니다.');
    }
  }

  Future<OwnershipTransferRequest> requestOwnershipTransfer({
    required String travelId,
    required String toMemberId,
  }) async {
    final client = _requireClient;
    try {
      final result = await client.rpc(
        'request_ownership_transfer',
        params: {
          'p_travel_id': travelId,
          'p_to_member_id': toMemberId,
        },
      );
      return OwnershipTransferRequest.fromJson(
        Map<String, dynamic>.from(result as Map),
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('여행장 이전 요청에 실패했습니다.');
    }
  }

  Future<void> respondOwnershipTransfer({
    required String requestId,
    required bool accept,
  }) async {
    final client = _requireClient;
    try {
      await client.rpc(
        'respond_ownership_transfer',
        params: {
          'p_request_id': requestId,
          'p_accept': accept,
        },
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('여행장 이전 응답에 실패했습니다.');
    }
  }

  Future<void> cancelOwnershipTransfer(String requestId) async {
    final client = _requireClient;
    try {
      await client.rpc(
        'cancel_ownership_transfer',
        params: {'p_request_id': requestId},
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('이전 요청 취소에 실패했습니다.');
    }
  }

  Future<String> fetchMyMemberId(String travelId) async {
    final client = _requireClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw TravelException('로그인이 필요합니다.');
    }

    try {
      final row = await client
          .from('travel_members')
          .select('id')
          .eq('travel_id', travelId)
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (row == null) {
        throw TravelException('이 여행의 구성원이 아닙니다.');
      }
      return row['id'] as String;
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('구성원 정보를 불러오지 못했습니다.');
    }
  }

  Future<List<Place>> fetchPlaces(String travelId) async {
    final client = _requireClient;
    try {
      final rows = await client
          .from('places')
          .select(
            '*, travel_members(display_name_snapshot, color_hex)',
          )
          .eq('travel_id', travelId)
          .order('created_at', ascending: false);

      return (rows as List)
          .map((row) => Place.fromJson(Map<String, dynamic>.from(row as Map)))
          .toList();
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('장소 목록을 불러오지 못했습니다.');
    }
  }

  Future<Place> createPlace({
    required String travelId,
    required String name,
    String? address,
    String? countryCode,
    double? latitude,
    double? longitude,
    String? memo,
    String? googlePlaceId,
    String? mapsUrl,
  }) async {
    final client = _requireClient;
    final memberId = await fetchMyMemberId(travelId);

    try {
      final row = await client
          .from('places')
          .insert({
            'travel_id': travelId,
            'created_by_member_id': memberId,
            'name': name.trim(),
            'address': _nullIfEmpty(address),
            'country_code': _nullIfEmpty(countryCode)?.toUpperCase(),
            'latitude': latitude,
            'longitude': longitude,
            'memo': _nullIfEmpty(memo),
            'google_place_id': _nullIfEmpty(googlePlaceId),
            'maps_url': _nullIfEmpty(mapsUrl),
          })
          .select(
            '*, travel_members(display_name_snapshot, color_hex)',
          )
          .single();

      return Place.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('장소 등록에 실패했습니다.');
    }
  }

  Future<Place> updatePlace({
    required Place place,
    required String name,
    String? address,
    String? countryCode,
    double? latitude,
    double? longitude,
    String? memo,
    String? googlePlaceId,
    String? mapsUrl,
  }) async {
    final client = _requireClient;
    try {
      final rows = await client
          .from('places')
          .update({
            'name': name.trim(),
            'address': _nullIfEmpty(address),
            'country_code': _nullIfEmpty(countryCode)?.toUpperCase(),
            'latitude': latitude,
            'longitude': longitude,
            'memo': _nullIfEmpty(memo),
            'google_place_id':
                _nullIfEmpty(googlePlaceId) ?? place.googlePlaceId,
            'maps_url': _nullIfEmpty(mapsUrl),
            'version': place.version + 1,
          })
          .eq('id', place.id)
          .eq('version', place.version)
          .select('*, travel_members(display_name_snapshot, color_hex)');

      final list = rows as List;
      if (list.isEmpty) {
        throw TravelException(
          '다른 구성원이 이 내용을 수정했습니다. 최신 내용을 확인한 후 다시 수정해주세요.',
        );
      }
      return Place.fromJson(Map<String, dynamic>.from(list.first as Map));
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('장소 수정에 실패했습니다.');
    }
  }

  Future<void> deletePlace(String placeId) async {
    final client = _requireClient;
    try {
      final linked = await client
          .from('schedules')
          .select('id')
          .eq('place_id', placeId)
          .limit(1);

      if ((linked as List).isNotEmpty) {
        throw TravelException(
          '일정에 연결된 장소입니다. 일정에서 연결을 해제한 뒤 삭제해주세요.',
        );
      }

      final planBLinked = await client
          .from('plan_b')
          .select('id')
          .eq('place_id', placeId)
          .limit(1);
      if ((planBLinked as List).isNotEmpty) {
        throw TravelException(
          'Plan B에 연결된 장소입니다. Plan B에서 해제한 뒤 삭제해주세요.',
        );
      }

      await client.from('places').delete().eq('id', placeId);
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('장소 삭제에 실패했습니다.');
    }
  }

  static const _scheduleSelect =
      '*, places(*), plan_b(*, places(*))';

  Future<List<ScheduleItem>> fetchSchedules(String travelId) async {
    final client = _requireClient;
    try {
      final rows = await client
          .from('schedules')
          .select(_scheduleSelect)
          .eq('travel_id', travelId)
          .order('schedule_date')
          .order('sort_order');

      return (rows as List)
          .map(
            (row) =>
                ScheduleItem.fromJson(Map<String, dynamic>.from(row as Map)),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('일정 목록을 불러오지 못했습니다.');
    }
  }

  Future<ScheduleItem> createSchedule({
    required String travelId,
    required DateTime scheduleDate,
    required String title,
    String? placeId,
    Duration? startTime,
    String? memo,
  }) async {
    final client = _requireClient;
    try {
      final dateStr = _dateOnly(scheduleDate);
      final existing = await client
          .from('schedules')
          .select('sort_order')
          .eq('travel_id', travelId)
          .eq('schedule_date', dateStr)
          .order('sort_order', ascending: false)
          .limit(1);

      var nextOrder = 0;
      if ((existing as List).isNotEmpty) {
        nextOrder =
            ((existing.first as Map)['sort_order'] as int? ?? 0) + 1;
      }

      final row = await client
          .from('schedules')
          .insert({
            'travel_id': travelId,
            'schedule_date': dateStr,
            'title': title.trim(),
            'place_id': placeId,
            'start_time': ScheduleItem.formatTimeForDb(startTime),
            'memo': _nullIfEmpty(memo),
            'sort_order': nextOrder,
          })
          .select(_scheduleSelect)
          .single();

      return ScheduleItem.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('일정 등록에 실패했습니다.');
    }
  }

  Future<ScheduleItem> updateSchedule({
    required ScheduleItem schedule,
    required DateTime scheduleDate,
    required String title,
    String? placeId,
    Duration? startTime,
    String? memo,
  }) async {
    final client = _requireClient;
    try {
      final rows = await client
          .from('schedules')
          .update({
            'schedule_date': _dateOnly(scheduleDate),
            'title': title.trim(),
            'place_id': placeId,
            'start_time': ScheduleItem.formatTimeForDb(startTime),
            'memo': _nullIfEmpty(memo),
            'version': schedule.version + 1,
          })
          .eq('id', schedule.id)
          .eq('version', schedule.version)
          .select(_scheduleSelect);

      final list = rows as List;
      if (list.isEmpty) {
        throw TravelException(
          '다른 구성원이 이 내용을 수정했습니다. 최신 내용을 확인한 후 다시 수정해주세요.',
        );
      }
      return ScheduleItem.fromJson(Map<String, dynamic>.from(list.first as Map));
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('일정 수정에 실패했습니다.');
    }
  }

  Future<ScheduleItem> setScheduleVisited({
    required ScheduleItem schedule,
    required bool isVisited,
  }) async {
    final client = _requireClient;
    try {
      final rows = await client
          .from('schedules')
          .update({
            'is_visited': isVisited,
            'version': schedule.version + 1,
          })
          .eq('id', schedule.id)
          .eq('version', schedule.version)
          .select(_scheduleSelect);

      final list = rows as List;
      if (list.isEmpty) {
        throw TravelException(
          '다른 구성원이 이 내용을 수정했습니다. 최신 내용을 확인한 후 다시 시도해주세요.',
        );
      }
      return ScheduleItem.fromJson(Map<String, dynamic>.from(list.first as Map));
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('방문 상태 변경에 실패했습니다.');
    }
  }

  /// 같은 날짜 안 순서만 변경. start_time은 건드리지 않는다.
  Future<void> reorderSchedules({
    required String travelId,
    required DateTime scheduleDate,
    required List<String> orderedIds,
  }) async {
    final client = _requireClient;
    try {
      final dateStr = _dateOnly(scheduleDate);
      for (var i = 0; i < orderedIds.length; i++) {
        await client
            .from('schedules')
            .update({'sort_order': i})
            .eq('id', orderedIds[i])
            .eq('travel_id', travelId)
            .eq('schedule_date', dateStr);
      }
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('일정 순서 변경에 실패했습니다.');
    }
  }

  Future<void> deleteSchedule(String scheduleId) async {
    final client = _requireClient;
    try {
      await client.from('schedules').delete().eq('id', scheduleId);
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('일정 삭제에 실패했습니다.');
    }
  }

  /// slot 1 또는 2. placeId가 null이면 해당 슬롯 삭제.
  Future<void> setPlanBSlot({
    required String scheduleId,
    required int slot,
    String? placeId,
  }) async {
    if (slot != 1 && slot != 2) {
      throw TravelException('Plan B는 1·2번 슬롯만 사용할 수 있습니다.');
    }
    final client = _requireClient;
    try {
      if (placeId == null) {
        await client
            .from('plan_b')
            .delete()
            .eq('schedule_id', scheduleId)
            .eq('slot', slot);
        return;
      }

      final existing = await client
          .from('plan_b')
          .select('id')
          .eq('schedule_id', scheduleId)
          .eq('slot', slot)
          .maybeSingle();

      if (existing == null) {
        await client.from('plan_b').insert({
          'schedule_id': scheduleId,
          'place_id': placeId,
          'slot': slot,
        });
      } else {
        await client.from('plan_b').update({
          'place_id': placeId,
        }).eq('id', existing['id'] as String);
      }
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('Plan B 저장에 실패했습니다.');
    }
  }

  Future<Map<String, TravelMember>> _membersById(String travelId) async {
    final members = await fetchMembers(travelId);
    return {for (final m in members) m.id: m};
  }

  Future<List<Expense>> fetchExpenses(String travelId) async {
    final client = _requireClient;
    try {
      final membersById = await _membersById(travelId);
      final rows = await client
          .from('expenses')
          .select('*, expense_participants(*)')
          .eq('travel_id', travelId)
          .order('paid_at', ascending: false);

      return (rows as List)
          .map(
            (row) => Expense.fromJson(
              Map<String, dynamic>.from(row as Map),
              membersById: membersById,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('비용 목록을 불러오지 못했습니다.');
    }
  }

  Future<Expense> fetchExpense(String travelId, String expenseId) async {
    final client = _requireClient;
    try {
      final membersById = await _membersById(travelId);
      final row = await client
          .from('expenses')
          .select('*, expense_participants(*)')
          .eq('id', expenseId)
          .eq('travel_id', travelId)
          .maybeSingle();
      if (row == null) {
        throw TravelException('비용을 찾을 수 없습니다.');
      }
      return Expense.fromJson(
        Map<String, dynamic>.from(row),
        membersById: membersById,
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('비용 정보를 불러오지 못했습니다.');
    }
  }

  Future<Expense> createExpense({
    required String travelId,
    required ExpenseCategory category,
    required int amount,
    required String currency,
    required String payerMemberId,
    required PaymentMethod paymentMethod,
    required DateTime paidAt,
    required SplitType splitType,
    required List<String> participantMemberIds,
    Map<String, int>? customShares,
    String? description,
    bool excludeFromSettlement = false,
  }) async {
    final client = _requireClient;
    if (amount < 0) {
      throw TravelException('금액은 0 이상이어야 합니다.');
    }
    if (participantMemberIds.isEmpty && !excludeFromSettlement) {
      throw TravelException('정산 참여자를 한 명 이상 선택하세요.');
    }

    final split = _resolveShares(
      amount: amount,
      splitType: splitType,
      participantMemberIds: participantMemberIds,
      customShares: customShares,
      excludeFromSettlement: excludeFromSettlement,
    );

    try {
      final row = await client
          .from('expenses')
          .insert({
            'travel_id': travelId,
            'category': category.dbValue,
            'description': _nullIfEmpty(description),
            'amount': amount,
            'currency': currency,
            'payer_member_id': payerMemberId,
            'payment_method': paymentMethod.dbValue,
            'paid_at': paidAt.toUtc().toIso8601String(),
            'split_type': splitType.dbValue,
            'exclude_from_settlement': excludeFromSettlement,
            'undistributed_remainder': split.remainder,
          })
          .select()
          .single();

      final expenseId = row['id'] as String;
      if (split.shares.isNotEmpty) {
        await client.from('expense_participants').insert(
              split.shares.entries
                  .map(
                    (e) => {
                      'expense_id': expenseId,
                      'member_id': e.key,
                      'share_amount': e.value,
                    },
                  )
                  .toList(),
            );
      }

      return fetchExpense(travelId, expenseId);
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('비용 등록에 실패했습니다.');
    }
  }

  Future<Expense> updateExpense({
    required Expense expense,
    required ExpenseCategory category,
    required int amount,
    required String currency,
    required String payerMemberId,
    required PaymentMethod paymentMethod,
    required DateTime paidAt,
    required SplitType splitType,
    required List<String> participantMemberIds,
    Map<String, int>? customShares,
    String? description,
    bool excludeFromSettlement = false,
  }) async {
    final client = _requireClient;
    if (expense.isSettlementCompleted) {
      throw TravelException('정산이 완료된 비용은 수정할 수 없습니다.');
    }
    if (amount < 0) {
      throw TravelException('금액은 0 이상이어야 합니다.');
    }
    if (participantMemberIds.isEmpty && !excludeFromSettlement) {
      throw TravelException('정산 참여자를 한 명 이상 선택하세요.');
    }

    final split = _resolveShares(
      amount: amount,
      splitType: splitType,
      participantMemberIds: participantMemberIds,
      customShares: customShares,
      excludeFromSettlement: excludeFromSettlement,
    );

    try {
      final rows = await client
          .from('expenses')
          .update({
            'category': category.dbValue,
            'description': _nullIfEmpty(description),
            'amount': amount,
            'currency': currency,
            'payer_member_id': payerMemberId,
            'payment_method': paymentMethod.dbValue,
            'paid_at': paidAt.toUtc().toIso8601String(),
            'split_type': splitType.dbValue,
            'exclude_from_settlement': excludeFromSettlement,
            'undistributed_remainder': split.remainder,
            'version': expense.version + 1,
          })
          .eq('id', expense.id)
          .eq('version', expense.version)
          .select();

      if ((rows as List).isEmpty) {
        throw TravelException(
          '다른 구성원이 이 내용을 수정했습니다. 최신 내용을 확인한 후 다시 수정해주세요.',
        );
      }

      await client
          .from('expense_participants')
          .delete()
          .eq('expense_id', expense.id);

      if (split.shares.isNotEmpty) {
        await client.from('expense_participants').insert(
              split.shares.entries
                  .map(
                    (e) => {
                      'expense_id': expense.id,
                      'member_id': e.key,
                      'share_amount': e.value,
                    },
                  )
                  .toList(),
            );
      }

      return fetchExpense(expense.travelId, expense.id);
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('비용 수정에 실패했습니다.');
    }
  }

  Future<void> deleteExpense(Expense expense) async {
    final client = _requireClient;
    if (expense.isSettlementCompleted) {
      throw TravelException('정산이 완료된 비용은 삭제할 수 없습니다.');
    }
    try {
      await client.from('expenses').delete().eq('id', expense.id);
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('비용 삭제에 실패했습니다.');
    }
  }

  Future<List<Settlement>> fetchSettlements(String travelId) async {
    final client = _requireClient;
    try {
      final membersById = await _membersById(travelId);
      final rows = await client
          .from('settlements')
          .select()
          .eq('travel_id', travelId)
          .order('created_at');

      return (rows as List)
          .map(
            (row) => Settlement.fromJson(
              Map<String, dynamic>.from(row as Map),
              membersById: membersById,
            ),
          )
          .toList();
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('정산 목록을 불러오지 못했습니다.');
    }
  }

  /// 미확인 송금 행을 지우고, 진행 중 비용 기준으로 송금 목록을 다시 만든다.
  Future<List<Settlement>> syncSettlementsFromExpenses(String travelId) async {
    final client = _requireClient;
    try {
      final expenses = await fetchExpenses(travelId);
      final membersById = await _membersById(travelId);
      final plan = buildSettlementPlan(
        expenses: expenses,
        membersById: membersById,
      );

      if (plan.openExpenseCount == 0) {
        throw TravelException('정산할 진행 중 비용이 없습니다.');
      }
      if (plan.transfers.isEmpty) {
        throw TravelException(
          '송금이 필요한 금액이 없습니다. 미배분 잔액이 있으면 비용에서 먼저 나눠 주세요.',
        );
      }

      final existing = await fetchSettlements(travelId);
      final locked = existing.where((s) => s.sentConfirmed || s.receivedConfirmed);
      if (locked.isNotEmpty) {
        throw TravelException(
          '이미 확인이 시작된 송금이 있어 목록을 다시 만들 수 없습니다. '
          '확인을 모두 끝낸 뒤 정산 완료 처리하세요.',
        );
      }

      if (existing.isNotEmpty) {
        await client.from('settlements').delete().eq('travel_id', travelId);
      }

      await client.from('settlements').insert(
            plan.transfers
                .map(
                  (t) => {
                    'travel_id': travelId,
                    'from_member_id': t.fromMemberId,
                    'to_member_id': t.toMemberId,
                    'amount': t.amount,
                    'currency': t.currency,
                  },
                )
                .toList(),
          );

      return fetchSettlements(travelId);
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('송금 목록 만들기에 실패했습니다.');
    }
  }

  Future<Settlement> confirmSettlementSent({
    required Settlement settlement,
    String? proxyMemberId,
  }) async {
    final client = _requireClient;
    if (settlement.sentConfirmed) {
      throw TravelException('이미 송금 확인된 항목입니다.');
    }
    try {
      final rows = await client
          .from('settlements')
          .update({
            'sent_confirmed': true,
            'sent_at': DateTime.now().toUtc().toIso8601String(),
            'sent_by_proxy_member_id': ?proxyMemberId,
            'version': settlement.version + 1,
          })
          .eq('id', settlement.id)
          .eq('version', settlement.version)
          .select();

      if ((rows as List).isEmpty) {
        throw TravelException(
          '다른 구성원이 이 내용을 수정했습니다. 다시 불러온 후 시도해주세요.',
        );
      }
      final membersById = await _membersById(settlement.travelId);
      return Settlement.fromJson(
        Map<String, dynamic>.from(rows.first as Map),
        membersById: membersById,
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('송금 확인에 실패했습니다.');
    }
  }

  Future<Settlement> confirmSettlementReceived({
    required Settlement settlement,
    String? proxyMemberId,
  }) async {
    final client = _requireClient;
    if (settlement.receivedConfirmed) {
      throw TravelException('이미 수령 확인된 항목입니다.');
    }
    if (!settlement.sentConfirmed) {
      throw TravelException('송금 확인이 먼저 필요합니다.');
    }
    try {
      final rows = await client
          .from('settlements')
          .update({
            'received_confirmed': true,
            'received_at': DateTime.now().toUtc().toIso8601String(),
            'received_by_proxy_member_id': ?proxyMemberId,
            'version': settlement.version + 1,
          })
          .eq('id', settlement.id)
          .eq('version', settlement.version)
          .select();

      if ((rows as List).isEmpty) {
        throw TravelException(
          '다른 구성원이 이 내용을 수정했습니다. 다시 불러온 후 시도해주세요.',
        );
      }
      final membersById = await _membersById(settlement.travelId);
      return Settlement.fromJson(
        Map<String, dynamic>.from(rows.first as Map),
        membersById: membersById,
      );
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('수령 확인에 실패했습니다.');
    }
  }

  /// 모든 송금이 송금·수령 확인되면 진행 중 비용을 정산 완료로 잠근다.
  Future<int> completeOpenExpenseSettlements(String travelId) async {
    final client = _requireClient;
    try {
      final settlements = await fetchSettlements(travelId);
      if (settlements.isEmpty) {
        throw TravelException('송금 목록이 없습니다. 먼저 송금 목록을 만드세요.');
      }
      if (!settlements.every((s) => s.isFullyConfirmed)) {
        throw TravelException('아직 확인되지 않은 송금이 있습니다.');
      }

      final expenses = await fetchExpenses(travelId);
      final openIds = expenses
          .where((e) => !e.excludeFromSettlement && !e.isSettlementCompleted)
          .map((e) => e.id)
          .toList();
      if (openIds.isEmpty) {
        throw TravelException('완료 처리할 비용이 없습니다.');
      }

      await client
          .from('expenses')
          .update({'settlement_status': 'completed'})
          .inFilter('id', openIds);

      return openIds.length;
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('정산 완료 처리에 실패했습니다.');
    }
  }

  ({Map<String, int> shares, int remainder}) _resolveShares({
    required int amount,
    required SplitType splitType,
    required List<String> participantMemberIds,
    Map<String, int>? customShares,
    required bool excludeFromSettlement,
  }) {
    if (excludeFromSettlement || participantMemberIds.isEmpty) {
      return (shares: <String, int>{}, remainder: 0);
    }

    if (splitType == SplitType.equal) {
      final result = equalSplitShares(amount, participantMemberIds.length);
      final shares = <String, int>{};
      for (var i = 0; i < participantMemberIds.length; i++) {
        shares[participantMemberIds[i]] = result.shares[i];
      }
      return (shares: shares, remainder: result.remainder);
    }

    final shares = <String, int>{};
    var sum = 0;
    for (final id in participantMemberIds) {
      final value = customShares?[id] ?? 0;
      if (value < 0) {
        throw TravelException('분담 금액은 0 이상이어야 합니다.');
      }
      shares[id] = value;
      sum += value;
    }
    if (sum > amount) {
      throw TravelException('분담 합계가 총액보다 클 수 없습니다.');
    }
    return (shares: shares, remainder: amount - sum);
  }

  String? _nullIfEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _mapError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid or expired invite')) {
      return '유효하지 않거나 만료된 초대코드입니다.';
    }
    if (lower.contains('not authenticated')) {
      return '로그인이 필요합니다.';
    }
    if (lower.contains('end_date')) {
      return '종료일은 시작일 이후여야 합니다.';
    }
    if (lower.contains('only owner')) {
      return '여행장만 할 수 있는 작업입니다.';
    }
    if (lower.contains('owner must transfer')) {
      return '여행장은 소유권을 이전한 뒤에만 나갈 수 있습니다.';
    }
    if (lower.contains('cannot kick owner')) {
      return '여행장은 퇴장시킬 수 없습니다.';
    }
    if (lower.contains('cannot assign owner as treasurer')) {
      return '여행장을 총무로 지정할 수 없습니다.';
    }
    if (lower.contains('member not found')) {
      return '구성원을 찾을 수 없습니다.';
    }
    if (lower.contains('travel is not editable')) {
      return '완료되었거나 편집할 수 없는 여행입니다.';
    }
    if (lower.contains('only target member')) {
      return '이전 대상 구성원만 응답할 수 있습니다.';
    }
    if (lower.contains('request not found')) {
      return '이전 요청을 찾을 수 없습니다.';
    }
    if (lower.contains('member is not pending')) {
      return '승인 대기 중인 요청이 아닙니다.';
    }
    if (lower.contains('only owner can accept') ||
        lower.contains('only owner can reject')) {
      return '여행장만 할 수 있는 작업입니다.';
    }
    return raw;
  }
}

