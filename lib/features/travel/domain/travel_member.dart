import '../../../core/constants/roles.dart';

enum MemberStatus {
  active,
  pending,
  left,
  kicked;

  static MemberStatus fromDb(String value) => switch (value) {
        'pending' => MemberStatus.pending,
        'left' => MemberStatus.left,
        'kicked' => MemberStatus.kicked,
        _ => MemberStatus.active,
      };

  String get dbValue => switch (this) {
        MemberStatus.active => 'active',
        MemberStatus.pending => 'pending',
        MemberStatus.left => 'left',
        MemberStatus.kicked => 'kicked',
      };

  String get label => switch (this) {
        MemberStatus.active => '참가 중',
        MemberStatus.pending => '승인 대기',
        MemberStatus.left => '나감',
        MemberStatus.kicked => '퇴장',
      };
}

class TravelMember {
  const TravelMember({
    required this.id,
    required this.travelId,
    required this.role,
    required this.status,
    required this.displayName,
    required this.colorHex,
    this.userId,
    this.isMe = false,
  });

  final String id;
  final String travelId;
  final String? userId;
  final TravelRole role;
  final MemberStatus status;
  final String displayName;
  final String colorHex;
  final bool isMe;

  factory TravelMember.fromJson(
    Map<String, dynamic> json, {
    String? currentUserId,
  }) {
    final userId = json['user_id'] as String?;
    return TravelMember(
      id: json['id'] as String,
      travelId: json['travel_id'] as String,
      userId: userId,
      role: TravelRoleX.fromDb(json['role'] as String? ?? 'member'),
      status: MemberStatus.fromDb(json['status'] as String? ?? 'active'),
      displayName: json['display_name_snapshot'] as String? ?? '구성원',
      colorHex: json['color_hex'] as String? ?? '#0D7377',
      isMe: currentUserId != null && userId == currentUserId,
    );
  }
}

class OwnershipTransferRequest {
  const OwnershipTransferRequest({
    required this.id,
    required this.travelId,
    required this.fromMemberId,
    required this.toMemberId,
    required this.status,
  });

  final String id;
  final String travelId;
  final String fromMemberId;
  final String toMemberId;
  final String status;

  bool get isPending => status == 'pending';

  factory OwnershipTransferRequest.fromJson(Map<String, dynamic> json) {
    return OwnershipTransferRequest(
      id: json['id'] as String,
      travelId: json['travel_id'] as String,
      fromMemberId: json['from_member_id'] as String,
      toMemberId: json['to_member_id'] as String,
      status: json['status'] as String? ?? 'pending',
    );
  }
}
