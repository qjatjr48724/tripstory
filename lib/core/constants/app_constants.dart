/// tripstory 앱 전역 상수
class AppConstants {
  AppConstants._();

  static const String appName = 'tripstory';
  static const String appTagline = '여행을 계획하고 함께 관리하는 여행 일정 관리 앱';

  /// 초대코드: 영문 대·소문자 + 숫자, 6자리, 대소문자 구분
  static const int inviteCodeLength = 6;
  static const String inviteCodeCharset =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  /// 휴지통 보관 기간 (일)
  static const int trashRetentionDays = 7;

  /// 여행 종료일 이후 자동 완료까지 대기 일수
  static const int autoCompleteAfterEndDays = 7;

  /// 계정 탈퇴 후 복구 가능 기간 (일)
  static const int accountRecoveryDays = 30;

  /// 여행당 최대 백업 스냅샷 수
  static const int maxBackupsPerTravel = 3;

  /// Plan B 최대 개수 (주요 목적지당)
  static const int maxPlanBPerSchedule = 2;

  /// 기본 통화
  static const String defaultCurrency = 'KRW';

  /// 지원 통화
  static const List<String> supportedCurrencies = [
    'KRW',
    'JPY',
    'USD',
    'EUR',
    'CNY',
  ];

  /// 일정 시작 알림: N분 전
  static const int scheduleReminderMinutes = 30;

  /// 예약 시작 알림: N분 전
  static const int reservationReminderMinutes = 60;
}
