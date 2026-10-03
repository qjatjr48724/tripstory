import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/schedule.dart';
import '../../domain/travel.dart';
import '../providers/travel_providers.dart';

class TravelSchedulesPage extends ConsumerStatefulWidget {
  const TravelSchedulesPage({super.key, required this.travelId});

  final String travelId;

  @override
  ConsumerState<TravelSchedulesPage> createState() =>
      _TravelSchedulesPageState();
}

class _TravelSchedulesPageState extends ConsumerState<TravelSchedulesPage> {
  DateTime? _selectedDate;

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DateTime> _travelDates(Travel travel) {
    final start = _dateOnly(travel.startDate);
    final end = _dateOnly(travel.endDate);
    final days = <DateTime>[];
    for (var d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    return days;
  }

  List<ScheduleItem> _forDate(List<ScheduleItem> all, DateTime date) {
    final key = _dateOnly(date);
    return all
        .where((s) => _dateOnly(s.scheduleDate) == key)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<void> _toggleVisited(ScheduleItem item) async {
    try {
      await ref.read(travelRepositoryProvider).setScheduleVisited(
            schedule: item,
            isVisited: !item.isVisited,
          );
      ref.invalidate(travelSchedulesProvider(widget.travelId));
    } on TravelException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  Future<void> _onReorder(
    DateTime date,
    List<ScheduleItem> items,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final reordered = [...items];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    try {
      await ref.read(travelRepositoryProvider).reorderSchedules(
            travelId: widget.travelId,
            scheduleDate: date,
            orderedIds: reordered.map((e) => e.id).toList(),
          );
      ref.invalidate(travelSchedulesProvider(widget.travelId));
    } on TravelException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
      ref.invalidate(travelSchedulesProvider(widget.travelId));
    }
  }

  Future<void> _confirmDelete(ScheduleItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('일정 삭제'),
        content: Text('「${item.title}」 일정을 삭제할까요?'),
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
    if (ok != true || !mounted) return;
    try {
      await ref.read(travelRepositoryProvider).deleteSchedule(item.id);
      ref.invalidate(travelSchedulesProvider(widget.travelId));
    } on TravelException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final travelId = widget.travelId;
    final travelAsync = ref.watch(travelDetailProvider(travelId));
    final schedulesAsync = ref.watch(travelSchedulesProvider(travelId));
    final dateFormat = DateFormat('M월 d일 (E)', 'ko');

    return travelAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('일정')),
        body: Center(child: Text('$e')),
      ),
      data: (travel) {
        final days = _travelDates(travel);
        final selected = _selectedDate != null &&
                days.any((d) => _dateOnly(d) == _dateOnly(_selectedDate!))
            ? _dateOnly(_selectedDate!)
            : (days.isNotEmpty ? days.first : null);
        final canEdit = travel.status == TravelStatus.active &&
            travel.myRole != null &&
            !travel.isJoinPending;

        return Scaffold(
          appBar: AppBar(title: const Text('일정')),
          floatingActionButton: canEdit && selected != null
              ? FloatingActionButton.extended(
                  onPressed: () => context.push(
                    '${AppRoutes.travels}/$travelId/schedules/new'
                    '?date=${selected.toIso8601String().split('T').first}',
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('일정 추가'),
                )
              : null,
          body: Column(
            children: [
              if (days.isNotEmpty)
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: days.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final day = days[index];
                      final selectedDay =
                          selected != null && _dateOnly(day) == selected;
                      return ChoiceChip(
                        label: Text(dateFormat.format(day)),
                        selected: selectedDay,
                        onSelected: (_) =>
                            setState(() => _selectedDate = day),
                      );
                    },
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: schedulesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('$e')),
                  data: (all) {
                    if (selected == null) {
                      return const Center(child: Text('여행 기간이 없습니다.'));
                    }
                    final items = _forDate(all, selected);
                    if (items.isEmpty) {
                      return Center(
                        child: Text(
                          canEdit
                              ? '이 날짜에 일정이 없습니다.\n아래 + 로 추가해 보세요.'
                              : '이 날짜에 일정이 없습니다.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(travelSchedulesProvider(travelId));
                        await ref
                            .read(travelSchedulesProvider(travelId).future);
                      },
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                        itemCount: items.length,
                        buildDefaultDragHandles: false,
                        onReorder: canEdit
                            ? (oldIndex, newIndex) => _onReorder(
                                  selected,
                                  items,
                                  oldIndex,
                                  newIndex,
                                )
                            : (_, _) {},
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _ScheduleTile(
                            key: ValueKey(item.id),
                            item: item,
                            index: index,
                            canEdit: canEdit,
                            onToggleVisited: () => _toggleVisited(item),
                            onEdit: () => context.push(
                              '${AppRoutes.travels}/$travelId/schedules/${item.id}/edit',
                              extra: item,
                            ),
                            onDelete: () => _confirmDelete(item),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScheduleTile extends StatelessWidget {
  const _ScheduleTile({
    super.key,
    required this.item,
    required this.index,
    required this.canEdit,
    required this.onToggleVisited,
    required this.onEdit,
    required this.onDelete,
  });

  final ScheduleItem item;
  final int index;
  final bool canEdit;
  final VoidCallback onToggleVisited;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final planB1 = item.planBAt(1);
    final planB2 = item.planBAt(2);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (canEdit)
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(top: 10, left: 4, right: 4),
                  child: Icon(Icons.drag_handle, color: AppColors.textSecondary),
                ),
              )
            else
              const SizedBox(width: 12),
            Checkbox(
              value: item.isVisited,
              onChanged: canEdit ? (_) => onToggleVisited() : null,
            ),
            Expanded(
              child: InkWell(
                onTap: canEdit ? onEdit : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (item.startTimeLabel != null) ...[
                            Text(
                              item.startTimeLabel!,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: AppColors.primary),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              item.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    decoration: item.isVisited
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      if (item.place != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.place!.name,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      if (planB1 != null || planB2 != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (planB1?.place != null)
                              'B1 ${planB1!.place!.name}',
                            if (planB2?.place != null)
                              'B2 ${planB2!.place!.name}',
                          ].join(' · '),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                        ),
                      ],
                      if (item.memo != null && item.memo!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.memo!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (canEdit)
              IconButton(
                tooltip: '삭제',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
