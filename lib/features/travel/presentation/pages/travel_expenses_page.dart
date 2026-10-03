import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/constants/roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/expense.dart';
import '../../domain/travel.dart';
import '../providers/travel_providers.dart';

class TravelExpensesPage extends ConsumerWidget {
  const TravelExpensesPage({super.key, required this.travelId});

  final String travelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final travelAsync = ref.watch(travelDetailProvider(travelId));
    final expensesAsync = ref.watch(travelExpensesProvider(travelId));
    final amountFormat = NumberFormat('#,###');
    final dateFormat = DateFormat('M.d (E) HH:mm', 'ko');

    return travelAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('비용')),
        body: Center(child: Text('$e')),
      ),
      data: (travel) {
        final canEdit = travel.status == TravelStatus.active &&
            travel.myRole != null &&
            !travel.isJoinPending &&
            (travel.myRole?.canEditExpense ?? false);
        final canDelete = travel.myRole?.canDeleteExpense ?? false;

        return Scaffold(
          appBar: AppBar(
            title: const Text('비용'),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: '비용 추가',
                  onPressed: () => context.push(
                    '${AppRoutes.travels}/$travelId/expenses/new',
                  ),
                  icon: const Icon(Icons.add),
                ),
            ],
          ),
          body: expensesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$e', textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(travelExpensesProvider(travelId)),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
            ),
            data: (expenses) {
              if (expenses.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '아직 등록된 비용이 없어요',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '식사·교통 등 지출을 기록해 보세요.\n정산은 다음 단계에서 이어집니다.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        if (canEdit) ...[
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: () => context.push(
                              '${AppRoutes.travels}/$travelId/expenses/new',
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('비용 추가'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }

              final totals = _totalsByCurrency(expenses);
              final settlementExcluded = expenses
                  .where((e) => e.excludeFromSettlement)
                  .length;

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(travelExpensesProvider(travelId));
                  await ref.read(travelExpensesProvider(travelId).future);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '합계',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            const SizedBox(height: 8),
                            ...totals.entries.map(
                              (e) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '${e.key} ${amountFormat.format(e.value)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            if (settlementExcluded > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                '정산 제외 $settlementExcluded건',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...expenses.map((expense) {
                      final payerName =
                          expense.payer?.displayName ?? '결제자 없음';
                      final subtitle = [
                        expense.category.label,
                        payerName,
                        dateFormat.format(expense.paidAt.toLocal()),
                      ].join(' · ');

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            expense.description?.trim().isNotEmpty == true
                                ? expense.description!.trim()
                                : expense.category.label,
                          ),
                          subtitle: Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${expense.currency} ${amountFormat.format(expense.amount)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                expense.excludeFromSettlement
                                    ? '정산 제외'
                                    : expense.settlementStatus.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: expense.isSettlementCompleted
                                          ? AppColors.textSecondary
                                          : AppColors.primary,
                                    ),
                              ),
                            ],
                          ),
                          onTap: canEdit && !expense.isSettlementCompleted
                              ? () => context.push(
                                    '${AppRoutes.travels}/$travelId/expenses/${expense.id}/edit',
                                    extra: expense,
                                  )
                              : () => _showReadonlySheet(
                                    context,
                                    expense,
                                    amountFormat,
                                  ),
                          onLongPress: canDelete &&
                                  !expense.isSettlementCompleted
                              ? () => _confirmDelete(
                                    context,
                                    ref,
                                    expense,
                                  )
                              : null,
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Map<String, int> _totalsByCurrency(List<Expense> expenses) {
    final map = <String, int>{};
    for (final e in expenses) {
      map[e.currency] = (map[e.currency] ?? 0) + e.amount;
    }
    return map;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final label = expense.description?.trim().isNotEmpty == true
        ? expense.description!.trim()
        : expense.category.label;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('비용 삭제'),
        content: Text('「$label」을(를) 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(travelRepositoryProvider).deleteExpense(expense);
      ref.invalidate(travelExpensesProvider(travelId));
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  void _showReadonlySheet(
    BuildContext context,
    Expense expense,
    NumberFormat amountFormat,
  ) {
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm', 'ko');
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense.description?.trim().isNotEmpty == true
                    ? expense.description!.trim()
                    : expense.category.label,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                '${expense.currency} ${amountFormat.format(expense.amount)}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text('항목: ${expense.category.label}'),
              Text('결제자: ${expense.payer?.displayName ?? '-'}'),
              Text('수단: ${expense.paymentMethod.label}'),
              Text('일시: ${dateFormat.format(expense.paidAt.toLocal())}'),
              Text('분담: ${expense.splitType.label}'),
              if (expense.excludeFromSettlement)
                const Text('정산 제외')
              else
                Text('상태: ${expense.settlementStatus.label}'),
              if (expense.undistributedRemainder > 0)
                Text(
                  '미배분 잔액: ${amountFormat.format(expense.undistributedRemainder)}',
                ),
              if (expense.participants.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('참여자'),
                ...expense.participants.map(
                  (p) => Text(
                    '· ${p.member?.displayName ?? '구성원'}: '
                    '${amountFormat.format(p.shareAmount)}',
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
