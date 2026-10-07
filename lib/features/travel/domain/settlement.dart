import 'expense.dart';
import 'travel_member.dart';

class Settlement {
  const Settlement({
    required this.id,
    required this.travelId,
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    required this.currency,
    required this.sentConfirmed,
    required this.receivedConfirmed,
    required this.version,
    this.sentAt,
    this.receivedAt,
    this.sentByProxyMemberId,
    this.receivedByProxyMemberId,
    this.fromMember,
    this.toMember,
  });

  final String id;
  final String travelId;
  final String fromMemberId;
  final String toMemberId;
  final int amount;
  final String currency;
  final bool sentConfirmed;
  final bool receivedConfirmed;
  final DateTime? sentAt;
  final DateTime? receivedAt;
  final String? sentByProxyMemberId;
  final String? receivedByProxyMemberId;
  final int version;
  final TravelMember? fromMember;
  final TravelMember? toMember;

  bool get isFullyConfirmed => sentConfirmed && receivedConfirmed;

  factory Settlement.fromJson(
    Map<String, dynamic> json, {
    Map<String, TravelMember>? membersById,
  }) {
    final fromId = json['from_member_id'] as String;
    final toId = json['to_member_id'] as String;
    return Settlement(
      id: json['id'] as String,
      travelId: json['travel_id'] as String,
      fromMemberId: fromId,
      toMemberId: toId,
      amount: json['amount'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'KRW',
      sentConfirmed: json['sent_confirmed'] as bool? ?? false,
      receivedConfirmed: json['received_confirmed'] as bool? ?? false,
      sentAt: json['sent_at'] != null
          ? DateTime.parse(json['sent_at'] as String)
          : null,
      receivedAt: json['received_at'] != null
          ? DateTime.parse(json['received_at'] as String)
          : null,
      sentByProxyMemberId: json['sent_by_proxy_member_id'] as String?,
      receivedByProxyMemberId: json['received_by_proxy_member_id'] as String?,
      version: json['version'] as int? ?? 1,
      fromMember: membersById?[fromId],
      toMember: membersById?[toId],
    );
  }
}

class MemberCurrencyBalance {
  const MemberCurrencyBalance({
    required this.memberId,
    required this.currency,
    required this.net,
    this.member,
  });

  final String memberId;
  final String currency;

  /// 양수 = 받을 돈, 음수 = 낼 돈
  final int net;
  final TravelMember? member;
}

class SuggestedTransfer {
  const SuggestedTransfer({
    required this.fromMemberId,
    required this.toMemberId,
    required this.amount,
    required this.currency,
    this.fromMember,
    this.toMember,
  });

  final String fromMemberId;
  final String toMemberId;
  final int amount;
  final String currency;
  final TravelMember? fromMember;
  final TravelMember? toMember;
}

class SettlementPlan {
  const SettlementPlan({
    required this.balances,
    required this.transfers,
    required this.openExpenseCount,
    required this.undistributedRemainderByCurrency,
  });

  final List<MemberCurrencyBalance> balances;
  final List<SuggestedTransfer> transfers;
  final int openExpenseCount;
  final Map<String, int> undistributedRemainderByCurrency;

  bool get hasUndistributedRemainder =>
      undistributedRemainderByCurrency.values.any((v) => v > 0);
}

/// 정산 진행 중·정산 제외가 아닌 비용으로 잔액·송금 제안 계산.
SettlementPlan buildSettlementPlan({
  required List<Expense> expenses,
  Map<String, TravelMember>? membersById,
}) {
  final open = expenses
      .where(
        (e) =>
            !e.excludeFromSettlement &&
            !e.isSettlementCompleted,
      )
      .toList();

  final nets = <String, Map<String, int>>{}; // memberId -> currency -> net
  final remainders = <String, int>{};

  for (final expense in open) {
    if (expense.undistributedRemainder > 0) {
      remainders[expense.currency] =
          (remainders[expense.currency] ?? 0) + expense.undistributedRemainder;
    }

    var shareSum = 0;
    for (final p in expense.participants) {
      if (p.shareAmount <= 0) continue;
      shareSum += p.shareAmount;
      final map = nets.putIfAbsent(p.memberId, () => {});
      map[expense.currency] = (map[expense.currency] ?? 0) - p.shareAmount;
    }

    if (shareSum > 0) {
      final map = nets.putIfAbsent(expense.payerMemberId, () => {});
      map[expense.currency] = (map[expense.currency] ?? 0) + shareSum;
    }
  }

  final balances = <MemberCurrencyBalance>[];
  for (final entry in nets.entries) {
    for (final cur in entry.value.entries) {
      if (cur.value == 0) continue;
      balances.add(
        MemberCurrencyBalance(
          memberId: entry.key,
          currency: cur.key,
          net: cur.value,
          member: membersById?[entry.key],
        ),
      );
    }
  }
  balances.sort((a, b) {
    final c = a.currency.compareTo(b.currency);
    if (c != 0) return c;
    return b.net.compareTo(a.net);
  });

  final transfers = <SuggestedTransfer>[];
  final currencies = balances.map((b) => b.currency).toSet();
  for (final currency in currencies) {
    final debtors = balances
        .where((b) => b.currency == currency && b.net < 0)
        .map((b) => MapEntry(b.memberId, -b.net))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final creditors = balances
        .where((b) => b.currency == currency && b.net > 0)
        .map((b) => MapEntry(b.memberId, b.net))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    var i = 0;
    var j = 0;
    while (i < debtors.length && j < creditors.length) {
      final pay = debtors[i].value < creditors[j].value
          ? debtors[i].value
          : creditors[j].value;
      if (pay > 0) {
        transfers.add(
          SuggestedTransfer(
            fromMemberId: debtors[i].key,
            toMemberId: creditors[j].key,
            amount: pay,
            currency: currency,
            fromMember: membersById?[debtors[i].key],
            toMember: membersById?[creditors[j].key],
          ),
        );
      }
      debtors[i] = MapEntry(debtors[i].key, debtors[i].value - pay);
      creditors[j] = MapEntry(creditors[j].key, creditors[j].value - pay);
      if (debtors[i].value == 0) i++;
      if (creditors[j].value == 0) j++;
    }
  }

  return SettlementPlan(
    balances: balances,
    transfers: transfers,
    openExpenseCount: open.length,
    undistributedRemainderByCurrency: remainders,
  );
}

/// 내가 특정 비용에서 결제자에게 내야 하는 항목
class MyPayableItem {
  const MyPayableItem({
    required this.expense,
    required this.shareAmount,
    required this.payToMemberId,
    this.payToMember,
  });

  final Expense expense;
  final int shareAmount;
  final String payToMemberId;
  final TravelMember? payToMember;
}

/// 내가 한 사람에게 받아야 하는 합계 (+ 비용 항목). 통화가 달라도 구성원 단위로 묶는다.
class MyReceivableFromPerson {
  const MyReceivableFromPerson({
    required this.fromMemberId,
    required this.totalsByCurrency,
    required this.items,
    this.fromMember,
  });

  final String fromMemberId;
  final Map<String, int> totalsByCurrency;
  final List<MyPayableItem> items;
  final TravelMember? fromMember;

  int get itemCount => items.length;
}

/// 로그인한 구성원 기준 개인 정산 뷰
class MySettlementView {
  const MySettlementView({
    required this.payables,
    required this.receivables,
    required this.payableTotalsByCurrency,
    required this.receivableTotalsByCurrency,
  });

  /// 내가 낼 항목 (비용 단위)
  final List<MyPayableItem> payables;

  /// 내가 받을 금액 (상대방 단위)
  final List<MyReceivableFromPerson> receivables;

  final Map<String, int> payableTotalsByCurrency;
  final Map<String, int> receivableTotalsByCurrency;

  bool get hasPayables => payables.isNotEmpty;
  bool get hasReceivables => receivables.isNotEmpty;
  bool get isEmpty => !hasPayables && !hasReceivables;
}

MySettlementView buildMySettlementView({
  required String myMemberId,
  required List<Expense> expenses,
  Map<String, TravelMember>? membersById,
}) {
  final open = expenses
      .where((e) => !e.excludeFromSettlement && !e.isSettlementCompleted)
      .toList();

  final payables = <MyPayableItem>[];
  final receivableMap = <String, MyReceivableFromPerson>{};
  // key: fromMemberId (통화와 무관하게 구성원만)

  for (final expense in open) {
    for (final p in expense.participants) {
      if (p.shareAmount <= 0) continue;

      // 내가 참여자이고 결제자가 아니면 → 낼 돈 (비용 항목)
      if (p.memberId == myMemberId && expense.payerMemberId != myMemberId) {
        payables.add(
          MyPayableItem(
            expense: expense,
            shareAmount: p.shareAmount,
            payToMemberId: expense.payerMemberId,
            payToMember: membersById?[expense.payerMemberId] ?? expense.payer,
          ),
        );
      }

      // 내가 결제자이고 상대가 참여자면 → 받을 돈 (상대방별)
      if (expense.payerMemberId == myMemberId && p.memberId != myMemberId) {
        final key = p.memberId;
        final existing = receivableMap[key];
        final item = MyPayableItem(
          expense: expense,
          shareAmount: p.shareAmount,
          payToMemberId: myMemberId,
          payToMember: membersById?[myMemberId],
        );
        if (existing == null) {
          receivableMap[key] = MyReceivableFromPerson(
            fromMemberId: p.memberId,
            totalsByCurrency: {expense.currency: p.shareAmount},
            items: [item],
            fromMember: membersById?[p.memberId] ?? p.member,
          );
        } else {
          final totals = Map<String, int>.from(existing.totalsByCurrency);
          totals[expense.currency] =
              (totals[expense.currency] ?? 0) + p.shareAmount;
          receivableMap[key] = MyReceivableFromPerson(
            fromMemberId: existing.fromMemberId,
            totalsByCurrency: totals,
            items: [...existing.items, item],
            fromMember: existing.fromMember,
          );
        }
      }
    }
  }

  payables.sort((a, b) => b.expense.paidAt.compareTo(a.expense.paidAt));

  final receivables = receivableMap.values.toList()
    ..sort((a, b) {
      final aName = a.fromMember?.displayName ?? '';
      final bName = b.fromMember?.displayName ?? '';
      return aName.compareTo(bName);
    });

  final payableTotals = <String, int>{};
  for (final p in payables) {
    payableTotals[p.expense.currency] =
        (payableTotals[p.expense.currency] ?? 0) + p.shareAmount;
  }
  final receivableTotals = <String, int>{};
  for (final r in receivables) {
    for (final e in r.totalsByCurrency.entries) {
      receivableTotals[e.key] = (receivableTotals[e.key] ?? 0) + e.value;
    }
  }

  return MySettlementView(
    payables: payables,
    receivables: receivables,
    payableTotalsByCurrency: payableTotals,
    receivableTotalsByCurrency: receivableTotals,
  );
}
