import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/constants/roles.dart';
import '../domain/place.dart';
import '../domain/schedule.dart';
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

