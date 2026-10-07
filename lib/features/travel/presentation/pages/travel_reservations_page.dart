import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/reservation.dart';
import '../../domain/travel.dart';
import '../providers/travel_providers.dart';

class TravelReservationsPage extends ConsumerWidget {
  const TravelReservationsPage({super.key, required this.travelId});

  final String travelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final travelAsync = ref.watch(travelDetailProvider(travelId));
    final reservationsAsync = ref.watch(travelReservationsProvider(travelId));

    return travelAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('예약')),
        body: Center(child: Text('$e')),
      ),
      data: (travel) {
        final canEdit = travel.status == TravelStatus.active &&
            travel.myRole != null &&
            !travel.isJoinPending;

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('예약'),
              actions: [
                if (canEdit)
                  Builder(
                    builder: (context) {
                      return IconButton(
                        tooltip: '예약 추가',
                        onPressed: () => _openCreate(
                          context,
                          travelId: travelId,
                        ),
                        icon: const Icon(Icons.add),
                      );
                    },
                  ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: '전체'),
                  Tab(text: '교통'),
                  Tab(text: '숙소'),
                  Tab(text: '기타'),
                ],
              ),
            ),
            body: reservationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$e', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(
                        'travel_links·Storage SQL을 대시보드에 적용했는지 확인해 주세요.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => ref
                            .invalidate(travelReservationsProvider(travelId)),
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return _EmptyReservations(
                    canEdit: canEdit,
                    onAdd: () => _openCreate(
                      context,
                      travelId: travelId,
                    ),
                  );
                }

                return TabBarView(
                  children: [
                    _ReservationTabBody(
                      travelId: travelId,
                      all: items,
                      typeFilter: null,
                      canEdit: canEdit,
                    ),
                    _ReservationTabBody(
                      travelId: travelId,
                      all: items,
                      typeFilter: ReservationType.transport,
                      canEdit: canEdit,
                    ),
                    _ReservationTabBody(
                      travelId: travelId,
                      all: items,
                      typeFilter: ReservationType.lodging,
                      canEdit: canEdit,
                    ),
                    _ReservationTabBody(
                      travelId: travelId,
                      all: items,
                      typeFilter: ReservationType.other,
                      canEdit: canEdit,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

void _openCreate(
  BuildContext context, {
  required String travelId,
  ReservationType? typeOverride,
}) {
  ReservationType? type = typeOverride;
  if (type == null) {
    final controller = DefaultTabController.maybeOf(context);
    // 0 전체, 1 교통, 2 숙소, 3 기타
    type = switch (controller?.index) {
      1 => ReservationType.transport,
      2 => ReservationType.lodging,
      3 => ReservationType.other,
      _ => null,
    };
  }
  final query = type == null ? '' : '?type=${type.dbValue}';
  context.push('${AppRoutes.travels}/$travelId/reservations/new$query');
}

class _EmptyReservations extends StatelessWidget {
  const _EmptyReservations({required this.canEdit, required this.onAdd});

  final bool canEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.airplane_ticket_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              '아직 등록된 예약이 없어요',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '항공·숙소 등 외부 예약의 최소 정보와\n확인 링크·이미지를 모아 두세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            if (canEdit) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('예약 추가'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReservationTabBody extends ConsumerWidget {
  const _ReservationTabBody({
    required this.travelId,
    required this.all,
    required this.typeFilter,
    required this.canEdit,
  });

  final String travelId;
  final List<Reservation> all;

  /// null이면 전체
  final ReservationType? typeFilter;
  final bool canEdit;

  List<Reservation> get _filtered {
    if (typeFilter == null) return all;
    return all.where((r) => r.type == typeFilter).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = _filtered;
    final dateFormat = DateFormat('M월 d일 (E) HH:mm', 'ko');
    final amountFormat = NumberFormat('#,###');

    if (items.isEmpty) {
      final emptyLabel = switch (typeFilter) {
        null => '표시할 예약이 없어요',
        ReservationType.transport => '교통 예약이 없어요',
        ReservationType.lodging => '숙소 예약이 없어요',
        ReservationType.other => '기타 예약이 없어요',
      };
      return Center(
        child: Text(
          emptyLabel,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      );
    }

    final media = MediaQuery.of(context);
    final cardHeight = ((media.size.height - media.padding.vertical - 160) / 2)
        .clamp(220.0, 320.0);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(travelReservationsProvider(travelId));
        await ref.read(travelReservationsProvider(travelId).future);
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final r = items[index];

          return SizedBox(
            height: cardHeight,
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push(
                  '${AppRoutes.travels}/$travelId/reservations/${r.id}/edit',
                  extra: r,
                ),
                onLongPress:
                    canEdit ? () => _confirmDelete(context, ref, r) : null,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              r.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(r.type.label),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (r.booker != null)
                        _InfoRow(
                          icon: Icons.person_outline,
                          text: '예약자 ${r.booker!.displayName}',
                        ),
                      if (r.confirmationNumber?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        _InfoRow(
                          icon: Icons.confirmation_number_outlined,
                          text: '예약번호 ${r.confirmationNumber!.trim()}',
                        ),
                      ],
                      if (r.startsAt != null) ...[
                        const SizedBox(height: 6),
                        _InfoRow(
                          icon: Icons.schedule_outlined,
                          text: dateFormat.format(r.startsAt!.toLocal()),
                        ),
                      ],
                      if (r.costAmount != null && r.costAmount! > 0) ...[
                        const SizedBox(height: 6),
                        _InfoRow(
                          icon: Icons.payments_outlined,
                          text:
                              '${r.costCurrency ?? 'KRW'} ${amountFormat.format(r.costAmount)}',
                        ),
                      ],
                      if (r.type == ReservationType.lodging &&
                          r.lodgingAddress?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 6),
                        _InfoRow(
                          icon: Icons.place_outlined,
                          text: r.lodgingAddress!.trim(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (r.confirmationUrl != null &&
                              r.confirmationUrl!.trim().isNotEmpty)
                            TextButton.icon(
                              onPressed: () =>
                                  _openUrl(context, r.confirmationUrl!),
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: const Text('확인 링크'),
                            ),
                          if (r.images.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '이미지 ${r.images.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                          const Spacer(),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String raw) async {
    var value = raw.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('올바른 링크가 아닙니다')),
      );
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Reservation reservation,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('예약 삭제'),
        content: Text('「${reservation.title}」을(를) 삭제할까요?'),
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
      await ref.read(travelRepositoryProvider).deleteReservation(reservation);
      ref.invalidate(travelReservationsProvider(travelId));
      ref.invalidate(travelExpensesProvider(travelId));
    } on TravelException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
