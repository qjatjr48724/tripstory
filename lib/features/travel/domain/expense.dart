import 'travel_member.dart';

enum ExpenseCategory {
  food,
  transport,
  lodging,
  sightseeing,
  shopping,
  prep,
  other;

  static ExpenseCategory fromDb(String value) => switch (value) {
        'food' => ExpenseCategory.food,
        'transport' => ExpenseCategory.transport,
        'lodging' => ExpenseCategory.lodging,
        'sightseeing' => ExpenseCategory.sightseeing,
        'shopping' => ExpenseCategory.shopping,
        'prep' => ExpenseCategory.prep,
        _ => ExpenseCategory.other,
      };

  String get dbValue => switch (this) {
        ExpenseCategory.food => 'food',
        ExpenseCategory.transport => 'transport',
        ExpenseCategory.lodging => 'lodging',
        ExpenseCategory.sightseeing => 'sightseeing',
        ExpenseCategory.shopping => 'shopping',
        ExpenseCategory.prep => 'prep',
        ExpenseCategory.other => 'other',
      };

  String get label => switch (this) {
        ExpenseCategory.food => '식비',
        ExpenseCategory.transport => '교통',
        ExpenseCategory.lodging => '숙박',
        ExpenseCategory.sightseeing => '관광/입장',
        ExpenseCategory.shopping => '쇼핑',
        ExpenseCategory.prep => '여행 준비',
        ExpenseCategory.other => '기타',
      };
}

enum PaymentMethod {
  cash,
  card,
  mobile,
  other;

  static PaymentMethod fromDb(String value) => switch (value) {
        'cash' => PaymentMethod.cash,
        'mobile' => PaymentMethod.mobile,
        'other' => PaymentMethod.other,
        _ => PaymentMethod.card,
      };

  String get dbValue => switch (this) {
        PaymentMethod.cash => 'cash',
        PaymentMethod.card => 'card',
        PaymentMethod.mobile => 'mobile',
        PaymentMethod.other => 'other',
      };

  String get label => switch (this) {
        PaymentMethod.cash => '현금',
        PaymentMethod.card => '카드',
        PaymentMethod.mobile => '모바일 결제',
        PaymentMethod.other => '기타',
      };
}

enum SplitType {
  equal,
  custom;

  static SplitType fromDb(String value) =>
      value == 'custom' ? SplitType.custom : SplitType.equal;

  String get dbValue => this == SplitType.custom ? 'custom' : 'equal';

  String get label =>
      this == SplitType.custom ? '직접 금액' : '1/N 균등';
}

enum ExpenseSettlementStatus {
  inProgress,
  completed;

  static ExpenseSettlementStatus fromDb(String value) =>
      value == 'completed'
          ? ExpenseSettlementStatus.completed
          : ExpenseSettlementStatus.inProgress;

  String get dbValue =>
      this == ExpenseSettlementStatus.completed ? 'completed' : 'in_progress';

  String get label =>
      this == ExpenseSettlementStatus.completed ? '정산 완료' : '정산 진행';
}

class ExpenseParticipant {
  const ExpenseParticipant({
    required this.id,
    required this.expenseId,
    required this.memberId,
    required this.shareAmount,
    this.member,
  });

  final String id;
  final String expenseId;
  final String memberId;
  final int shareAmount;
  final TravelMember? member;

  factory ExpenseParticipant.fromJson(
    Map<String, dynamic> json, {
    TravelMember? member,
  }) {
    return ExpenseParticipant(
      id: json['id'] as String,
      expenseId: json['expense_id'] as String,
      memberId: json['member_id'] as String,
      shareAmount: json['share_amount'] as int? ?? 0,
      member: member,
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.travelId,
    required this.category,
    required this.amount,
    required this.currency,
    required this.payerMemberId,
    required this.paymentMethod,
    required this.paidAt,
    required this.splitType,
    required this.excludeFromSettlement,
    required this.settlementStatus,
    required this.undistributedRemainder,
    required this.version,
    this.description,
    this.payer,
    this.participants = const [],
  });

  final String id;
  final String travelId;
  final ExpenseCategory category;
  final String? description;
  final int amount;
  final String currency;
  final String payerMemberId;
  final PaymentMethod paymentMethod;
  final DateTime paidAt;
  final SplitType splitType;
  final bool excludeFromSettlement;
  final ExpenseSettlementStatus settlementStatus;
  final int undistributedRemainder;
  final int version;
  final TravelMember? payer;
  final List<ExpenseParticipant> participants;

  bool get isSettlementCompleted =>
      settlementStatus == ExpenseSettlementStatus.completed;

  factory Expense.fromJson(
    Map<String, dynamic> json, {
    Map<String, TravelMember>? membersById,
  }) {
    final payerId = json['payer_member_id'] as String;
    final participantsRaw = json['expense_participants'];
    final participants = <ExpenseParticipant>[];
    if (participantsRaw is List) {
      for (final row in participantsRaw) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final memberId = map['member_id'] as String;
        participants.add(
          ExpenseParticipant.fromJson(
            map,
            member: membersById?[memberId],
          ),
        );
      }
    }

    return Expense(
      id: json['id'] as String,
      travelId: json['travel_id'] as String,
      category: ExpenseCategory.fromDb(json['category'] as String? ?? 'other'),
      description: json['description'] as String?,
      amount: json['amount'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'KRW',
      payerMemberId: payerId,
      paymentMethod:
          PaymentMethod.fromDb(json['payment_method'] as String? ?? 'card'),
      paidAt: DateTime.parse(json['paid_at'] as String),
      splitType: SplitType.fromDb(json['split_type'] as String? ?? 'equal'),
      excludeFromSettlement:
          json['exclude_from_settlement'] as bool? ?? false,
      settlementStatus: ExpenseSettlementStatus.fromDb(
        json['settlement_status'] as String? ?? 'in_progress',
      ),
      undistributedRemainder: json['undistributed_remainder'] as int? ?? 0,
      version: json['version'] as int? ?? 1,
      payer: membersById?[payerId],
      participants: participants,
    );
  }
}

/// 1/N 균등: 나머지는 미배분 잔액으로 남긴다 (임의로 1원 몰아주지 않음).
({List<int> shares, int remainder}) equalSplitShares(int amount, int count) {
  if (count <= 0) return (shares: const <int>[], remainder: amount);
  final each = amount ~/ count;
  final remainder = amount - each * count;
  return (shares: List<int>.filled(count, each), remainder: remainder);
}

const supportedCurrencies = ['KRW', 'JPY', 'CNY', 'USD', 'EUR'];
