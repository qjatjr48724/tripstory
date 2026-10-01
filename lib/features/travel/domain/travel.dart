import '../../../core/constants/roles.dart';
import 'travel_member.dart';

enum TravelStatus {
  active,
  completed,
  trashed;

  static TravelStatus fromDb(String value) => switch (value) {
        'completed' => TravelStatus.completed,
        'trashed' => TravelStatus.trashed,
        _ => TravelStatus.active,
      };

  String get label => switch (this) {
        TravelStatus.active => '진행 중',
        TravelStatus.completed => '완료',
        TravelStatus.trashed => '휴지통',
      };
}

class Travel {
  const Travel({
    required this.id,
    required this.name,
    required this.startDate,
    required this.endDate,
    required this.region,
    required this.status,
    this.memo,
    this.inviteCode,
    this.myRole,
    this.myMemberStatus,
  });

  final String id;
  final String name;
  final DateTime startDate;
  final DateTime endDate;
  final String region;
  final TravelStatus status;
  final String? memo;
  final String? inviteCode;
  final TravelRole? myRole;
  final MemberStatus? myMemberStatus;

  bool get isJoinPending => myMemberStatus == MemberStatus.pending;

  factory Travel.fromJson(
    Map<String, dynamic> json, {
    TravelRole? myRole,
    MemberStatus? myMemberStatus,
  }) {
    return Travel(
      id: json['id'] as String,
      name: json['name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      region: json['region'] as String,
      status: TravelStatus.fromDb(json['status'] as String? ?? 'active'),
      memo: json['memo'] as String?,
      inviteCode: json['invite_code'] as String?,
      myRole: myRole,
      myMemberStatus: myMemberStatus,
    );
  }

  Travel copyWith({
    TravelRole? myRole,
    MemberStatus? myMemberStatus,
  }) {
    return Travel(
      id: id,
      name: name,
      startDate: startDate,
      endDate: endDate,
      region: region,
      status: status,
      memo: memo,
      inviteCode: inviteCode,
      myRole: myRole ?? this.myRole,
      myMemberStatus: myMemberStatus ?? this.myMemberStatus,
    );
  }
}
