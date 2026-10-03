import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/settlement.dart';
import '../../domain/travel.dart';
import '../../domain/travel_member.dart';
import '../providers/travel_providers.dart';

class TravelSettlementsPage extends ConsumerWidget {
  const TravelSettlementsPage({super.key, required this.travelId});

  final String travelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final travelAsync = ref.watch(travelDetailProvider(travelId));
    final expensesAsync = ref.watch(travelExpensesProvider(travelId));
    final settlementsAsync = ref.watch(travelSettlementsProvider(travelId));
    final membersAsync = ref.watch(travelMembersProvider(travelId));
    final amountFormat = NumberFormat('#,###');

    return travelAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('정산')),
        body: Center(child: Text('$e')),
      ),
      data: (travel) {
        final role = travel.myRole;
        final canEdit = travel.status == TravelStatus.active &&
            role != null &&
            !travel.isJoinPending;
        final canConfirm = role?.canConfirmSettlement ?? false;
        final canProxy = role?.canProxyPaymentConfirm ?? false;

        return Scaffold(
          appBar: AppBar(
            title: const Text('정산'),
            actions: [
              IconButton(
                tooltip: '새로고침',
                onPressed: () {
                  ref.invalidate(travelExpensesProvider(travelId));
                  ref.invalidate(travelSettlementsProvider(travelId));
                  ref.invalidate(travelMembersProvider(travelId));
                },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: expensesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (expenses) {
              return settlementsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
                data: (settlements) {
                  return membersAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('$e')),
                    data: (members) {
                      final membersById = {
                        for (final m in members) m.id: m,
                      };
                      final me = members.where((m) => m.isMe).firstOrNull;
                      final plan = buildSettlementPlan(
                        expenses: expenses,
                        membersById: membersById,
                      );
                      final allConfirmed = settlements.isNotEmpty &&
                          settlements.every((s) => s.isFullyConfirmed);

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          _SectionCard(
                            title: '잔액 요약',
                            child: plan.balances.isEmpty
                                ? Text(
                                    plan.openExpenseCount == 0
                                        ? '정산할 진행 중 비용이 없습니다.'
                                        : '구성원 간 주고받을 금액이 없습니다.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  )
                                : Column(
                                    children: plan.balances.map((b) {
                                      final name =
                                          b.member?.displayName ?? '구성원';
                                      final positive = b.net > 0;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Row(
                                          children: [
                                            Expanded(child: Text(name)),
                                            Text(
                                              positive
                                                  ? '받을 돈 ${b.currency} ${amountFormat.format(b.net)}'
                                                  : '낼 돈 ${b.currency} ${amountFormat.format(-b.net)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: positive
                                                    ? AppColors.success
                                                    : AppColors.error,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                          if (plan.hasUndistributedRemainder) ...[
                            const SizedBox(height: 12),
                            Card(
                              color: AppColors.surfaceMuted,
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  '미배분 잔액이 있습니다: '
                                  '${plan.undistributedRemainderByCurrency.entries.map((e) => '${e.key} ${amountFormat.format(e.value)}').join(', ')}. '
                                  '비용 화면에서 직접 분담으로 나눠 주세요.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          _SectionCard(
                            title: '추천 송금',
                            child: plan.transfers.isEmpty
                                ? Text(
                                    '추천 송금이 없습니다.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  )
                                : Column(
                                    children: plan.transfers.map((t) {
                                      final from =
                                          t.fromMember?.displayName ?? '구성원';
                                      final to =
                                          t.toMember?.displayName ?? '구성원';
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          '$from → $to  '
                                          '${t.currency} ${amountFormat.format(t.amount)}',
                                        ),
                                      );
                                    }).toList(),
                                  ),
                          ),
                          if (canEdit && canConfirm) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: plan.transfers.isEmpty
                                  ? null
                                  : () => _syncSettlements(context, ref),
                              icon: const Icon(Icons.playlist_add_check),
                              label: Text(
                                settlements.isEmpty
                                    ? '송금 목록 만들기'
                                    : '송금 목록 다시 만들기',
                              ),
                            ),
                            if (settlements.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '확인이 시작되면 목록을 다시 만들 수 없습니다.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.textSecondary,
                                      ),
                                ),
                              ),
                          ],
                          const SizedBox(height: 20),
                          Text(
                            '송금 확인',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          if (settlements.isEmpty)
                            Text(
                              '여행장·총무가 「송금 목록 만들기」를 누르면 확인을 시작할 수 있습니다.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            )
                          else
                            ...settlements.map(
                              (s) => _SettlementTile(
                                settlement: s,
                                amountFormat: amountFormat,
                                me: me,
                                canEdit: canEdit,
                                canProxy: canProxy,
                                onSent: () => _confirmSent(
                                  context,
                                  ref,
                                  s,
                                  me: me,
                                  asProxy: canProxy &&
                                      me != null &&
                                      s.fromMemberId != me.id,
                                ),
                                onReceived: () => _confirmReceived(
                                  context,
                                  ref,
                                  s,
                                  me: me,
                                  asProxy: canProxy &&
                                      me != null &&
                                      s.toMemberId != me.id,
                                ),
                              ),
                            ),
                          if (canEdit && canConfirm && settlements.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            OutlinedButton.icon(
                              onPressed: allConfirmed
                                  ? () => _completeSettlements(context, ref)
                                  : null,
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('정산 완료 (비용 잠금)'),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              allConfirmed
                                  ? '모든 송금·수령 확인이 끝났습니다. 완료하면 관련 비용을 수정·삭제할 수 없습니다.'
                                  : '모든 항목의 송금·수령 확인이 끝나면 완료할 수 있습니다.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                            ),
                          ],
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _syncSettlements(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('송금 목록 만들기'),
        content: const Text(
          '진행 중 비용 기준으로 송금 목록을 만듭니다.\n'
          '아직 확인되지 않은 기존 목록은 덮어씁니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('만들기'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(travelRepositoryProvider)
          .syncSettlementsFromExpenses(travelId);
      ref.invalidate(travelSettlementsProvider(travelId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('송금 목록을 만들었습니다')),
      );
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _confirmSent(
    BuildContext context,
    WidgetRef ref,
    Settlement settlement, {
    required TravelMember? me,
    required bool asProxy,
  }) async {
    final canSelf = me != null && settlement.fromMemberId == me.id;
    if (!canSelf && !asProxy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('송금한 본인 또는 여행장·총무만 확인할 수 있어요')),
      );
      return;
    }
    try {
      await ref.read(travelRepositoryProvider).confirmSettlementSent(
            settlement: settlement,
            proxyMemberId: asProxy && !canSelf ? me?.id : null,
          );
      ref.invalidate(travelSettlementsProvider(travelId));
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _confirmReceived(
    BuildContext context,
    WidgetRef ref,
    Settlement settlement, {
    required TravelMember? me,
    required bool asProxy,
  }) async {
    final canSelf = me != null && settlement.toMemberId == me.id;
    if (!canSelf && !asProxy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('수령한 본인 또는 여행장·총무만 확인할 수 있어요')),
      );
      return;
    }
    try {
      await ref.read(travelRepositoryProvider).confirmSettlementReceived(
            settlement: settlement,
            proxyMemberId: asProxy && !canSelf ? me?.id : null,
          );
      ref.invalidate(travelSettlementsProvider(travelId));
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _completeSettlements(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('정산 완료'),
        content: const Text(
          '진행 중 비용을 정산 완료로 잠급니다.\n이후 해당 비용은 수정·삭제할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('완료'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final count = await ref
          .read(travelRepositoryProvider)
          .completeOpenExpenseSettlements(travelId);
      ref.invalidate(travelExpensesProvider(travelId));
      ref.invalidate(travelSettlementsProvider(travelId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('비용 $count건을 정산 완료 처리했습니다')),
      );
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _SettlementTile extends StatelessWidget {
  const _SettlementTile({
    required this.settlement,
    required this.amountFormat,
    required this.me,
    required this.canEdit,
    required this.canProxy,
    required this.onSent,
    required this.onReceived,
  });

  final Settlement settlement;
  final NumberFormat amountFormat;
  final TravelMember? me;
  final bool canEdit;
  final bool canProxy;
  final VoidCallback onSent;
  final VoidCallback onReceived;

  @override
  Widget build(BuildContext context) {
    final from = settlement.fromMember?.displayName ?? '구성원';
    final to = settlement.toMember?.displayName ?? '구성원';
    final isSender = me?.id == settlement.fromMemberId;
    final isReceiver = me?.id == settlement.toMemberId;
    final canMarkSent = canEdit &&
        !settlement.sentConfirmed &&
        (isSender || canProxy);
    final canMarkReceived = canEdit &&
        settlement.sentConfirmed &&
        !settlement.receivedConfirmed &&
        (isReceiver || canProxy);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$from → $to',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${settlement.currency} ${amountFormat.format(settlement.amount)}',
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(
                    settlement.sentConfirmed
                        ? (settlement.sentByProxyMemberId != null
                            ? '송금 확인(대행)'
                            : '송금 확인')
                        : '송금 대기',
                  ),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: settlement.sentConfirmed
                      ? AppColors.success.withValues(alpha: 0.15)
                      : null,
                ),
                Chip(
                  label: Text(
                    settlement.receivedConfirmed
                        ? (settlement.receivedByProxyMemberId != null
                            ? '수령 확인(대행)'
                            : '수령 확인')
                        : '수령 대기',
                  ),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: settlement.receivedConfirmed
                      ? AppColors.success.withValues(alpha: 0.15)
                      : null,
                ),
              ],
            ),
            if (canMarkSent || canMarkReceived) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (canMarkSent)
                    FilledButton.tonal(
                      onPressed: onSent,
                      child: Text(isSender ? '보냈어요!' : '송금 대행 확인'),
                    ),
                  if (canMarkReceived) ...[
                    if (canMarkSent) const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: onReceived,
                      child: Text(isReceiver ? '수령 확인' : '수령 대행 확인'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
