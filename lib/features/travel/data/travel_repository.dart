import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/constants/roles.dart';
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

  /// 내가 active 멤버인 여행 목록
  Future<List<Travel>> fetchMyTravels() async {
    final client = _requireClient;
    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw TravelException('로그인이 필요합니다.');
    }

    try {
      final rows = await client
          .from('travel_members')
          .select('role, travels(*)')
          .eq('user_id', userId)
          .eq('status', 'active')
          .order('joined_at', ascending: false);

      final list = <Travel>[];
      for (final row in rows as List) {
        final map = Map<String, dynamic>.from(row as Map);
        final travelJson = map['travels'];
        if (travelJson == null) continue;
        final travelMap = Map<String, dynamic>.from(travelJson as Map);
        final status = travelMap['status'] as String? ?? 'active';
        if (status == 'trashed') continue;

        list.add(
          Travel.fromJson(
            travelMap,
            myRole: TravelRoleX.fromDb(map['role'] as String? ?? 'member'),
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
      return Travel.fromJson(map, myRole: TravelRole.owner);
    } on PostgrestException catch (e) {
      throw TravelException(_mapError(e.message));
    } catch (e) {
      if (e is TravelException) rethrow;
      throw TravelException('여행 생성에 실패했습니다.');
    }
  }

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
      return Travel.fromJson(map, myRole: TravelRole.member);
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
          .select('role, travels(*)')
          .eq('travel_id', travelId)
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      if (row == null) {
        throw TravelException('여행을 찾을 수 없거나 권한이 없습니다.');
      }

      final map = Map<String, dynamic>.from(row);
      final travelMap = Map<String, dynamic>.from(map['travels'] as Map);
      return Travel.fromJson(
        travelMap,
        myRole: TravelRoleX.fromDb(map['role'] as String? ?? 'member'),
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
          .eq('status', 'active')
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

  Future<Travel> reissueInviteCode(String travelId) async {
    final client = _requireClient;
    try {
      final result = await client.rpc(
        'reissue_invite_code',
        params: {'p_travel_id': travelId},
      );
      final map = Map<String, dynamic>.from(result as Map);
      return Travel.fromJson(map, myRole: TravelRole.owner);
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
    return raw;
  }
}
