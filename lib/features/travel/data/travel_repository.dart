import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/constants/roles.dart';
import '../domain/travel.dart';

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
        // 목록에서는 진행 중 / 완료만 (휴지통은 별도)
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
    return raw;
  }
}
