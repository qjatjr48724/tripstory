/// 여행 구성원 역할 (제안서 3.2 / 6.4)
enum TravelRole {
  /// 일반 구성원
  member,

  /// 총무 — 비용·정산 관련 권한
  treasurer,

  /// 여행장 — 소유·구성원·완료 등 전용 권한
  owner,
}

extension TravelRoleX on TravelRole {
  String get label => switch (this) {
        TravelRole.member => '구성원',
        TravelRole.treasurer => '총무',
        TravelRole.owner => '여행장',
      };

  String get dbValue => switch (this) {
        TravelRole.member => 'member',
        TravelRole.treasurer => 'treasurer',
        TravelRole.owner => 'owner',
      };

  static TravelRole fromDb(String value) => switch (value) {
        'owner' => TravelRole.owner,
        'treasurer' => TravelRole.treasurer,
        _ => TravelRole.member,
      };

  /// 자신이 등록한 장소 수정/삭제
  bool get canEditOwnPlace => true;

  /// 다른 구성원의 장소 수정/삭제
  bool get canEditOthersPlace => this == TravelRole.owner;

  /// 일정 수정 / 순서 변경
  bool get canEditSchedule => true;

  /// 비용 등록 / 수정
  bool get canEditExpense => true;

  /// 비용 삭제
  bool get canDeleteExpense =>
      this == TravelRole.owner || this == TravelRole.treasurer;

  /// 정산 참여자 변경
  bool get canChangeSettlementParticipants =>
      this == TravelRole.owner || this == TravelRole.treasurer;

  /// 최종 정산 금액 확정
  bool get canConfirmSettlement =>
      this == TravelRole.owner || this == TravelRole.treasurer;

  /// 송금 / 수령 확인 대행
  bool get canProxyPaymentConfirm =>
      this == TravelRole.owner || this == TravelRole.treasurer;

  /// 여행 삭제
  bool get canDeleteTravel => this == TravelRole.owner;

  /// 구성원 초대
  bool get canInviteMember => this == TravelRole.owner;

  /// 강제 퇴장
  bool get canKickMember => this == TravelRole.owner;

  /// 초대코드 재발급
  bool get canReissueInviteCode => this == TravelRole.owner;

  /// 여행 완료
  bool get canCompleteTravel => this == TravelRole.owner;

  /// 총무 지정
  bool get canAssignTreasurer => this == TravelRole.owner;

  /// 여행장 이전 요청
  bool get canTransferOwnership => this == TravelRole.owner;

  /// 휴지통에서 여행 복원
  bool get canRestoreFromTrash => this == TravelRole.owner;

  /// 백업 생성 / 복원
  bool get canManageBackup => this == TravelRole.owner;
}
