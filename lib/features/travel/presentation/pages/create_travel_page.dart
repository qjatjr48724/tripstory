import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/router.dart';
import '../../../../core/date/ymd_slash_calendar_delegate.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../providers/travel_providers.dart';

class CreateTravelPage extends ConsumerStatefulWidget {
  const CreateTravelPage({super.key});

  @override
  ConsumerState<CreateTravelPage> createState() => _CreateTravelPageState();
}

class _CreateTravelPageState extends ConsumerState<CreateTravelPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _regionController = TextEditingController();
  final _memoController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;

  final _dateFormat = DateFormat('yyyy.MM.dd');

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _regionController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  /// 첫 탭 = 시작일, 둘째 탭 = 종료일. 구간은 캘린더에 하이라이트된다.
  /// 종료일 후보는 오늘 이전 날짜를 선택할 수 없다. (시작일은 과거 허용)
  Future<void> _pickDateRange() async {
    final today = _today;
    final initial = (_startDate != null && _endDate != null)
        ? DateTimeRange(start: _startDate!, end: _endDate!)
        : null;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 5),
      initialDateRange: initial,
      currentDate: today,
      locale: const Locale('ko', 'KR'),
      calendarDelegate: const YmdSlashCalendarDelegate(),
      helpText: '여행 기간 선택',
      saveText: '확인',
      cancelText: '취소',
      fieldStartLabelText: '시작일',
      fieldEndLabelText: '종료일',
      fieldStartHintText: '20261002',
      fieldEndHintText: '20261002',
      errorFormatText: '날짜는 2026/10/02 또는 20261002 형식으로 입력해주세요.',
      errorInvalidText: '선택할 수 없는 날짜입니다. 종료일은 오늘 이후여야 해요.',
      errorInvalidRangeText: '종료일은 시작일 이후여야 합니다.',
      selectableDayPredicate: (day, selectedStart, selectedEnd) {
        final d = DateTime(day.year, day.month, day.day);

        DateTime dateOnly(DateTime value) =>
            DateTime(value.year, value.month, value.day);

        // 시작일로 쓰이는 날짜는 과거여도 허용
        if (selectedStart != null && d == dateOnly(selectedStart)) {
          return true;
        }

        // 종료일로 쓰이는 날짜(입력 모드 포함): 오늘 이전 불가
        if (selectedEnd != null && d == dateOnly(selectedEnd)) {
          return !d.isBefore(today);
        }

        // 캘린더: 시작일만 고른 뒤 → 종료일 후보
        if (selectedStart != null && selectedEnd == null) {
          return !d.isBefore(today);
        }

        // 아직 시작 전, 또는 구간 완성 후 새 시작일 다시 고를 때: 과거 허용
        return true;
      },
      builder: (context, child) {
        final base = Theme.of(context);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: AppColors.textOnPrimary,
            ),
            datePickerTheme: base.datePickerTheme.copyWith(
              // 시작·종료일 사이 구간 하이라이트를 더 진하게
              rangeSelectionBackgroundColor:
                  AppColors.primary.withValues(alpha: 0.28),
              rangeSelectionOverlayColor: WidgetStateProperty.resolveWith(
                (states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primary.withValues(alpha: 0.16);
                  }
                  if (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)) {
                    return AppColors.primary.withValues(alpha: 0.12);
                  }
                  return null;
                },
              ),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.primary;
                }
                return null;
              }),
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.textOnPrimary;
                }
                if (states.contains(WidgetState.disabled)) {
                  return AppColors.textSecondary.withValues(alpha: 0.35);
                }
                return AppColors.textPrimary;
              }),
              todayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.textOnPrimary;
                }
                return AppColors.primary;
              }),
              todayBorder: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;

    final start = DateTime(
      picked.start.year,
      picked.start.month,
      picked.start.day,
    );
    final end = DateTime(picked.end.year, picked.end.month, picked.end.day);

    // 안전장치 (predicate로 대부분 차단됨)
    if (end.isBefore(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('종료일은 오늘 이후로 선택해주세요.'),
        ),
      );
      return;
    }

    setState(() {
      _startDate = start;
      _endDate = end;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('여행 기간을 선택해주세요')),
      );
      return;
    }
    if (_endDate!.isBefore(_today)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이미 끝난 여행은 새로 만들 수 없어요. 종료일은 오늘 이후로 선택해주세요.'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final travel = await ref.read(travelRepositoryProvider).createTravel(
            name: _nameController.text,
            startDate: _startDate!,
            endDate: _endDate!,
            region: _regionController.text,
            memo: _memoController.text,
          );
      ref.invalidate(myTravelsProvider);
      if (!mounted) return;
      context.go('${AppRoutes.travels}/${travel.id}');
    } on TravelException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRange = _startDate != null && _endDate != null;
    final nightCount = hasRange
        ? _endDate!.difference(_startDate!).inDays
        : 0;
    final dayCount = hasRange ? nightCount + 1 : 0;
    final rangeLabel = hasRange
        ? '${_dateFormat.format(_startDate!)}  →  ${_dateFormat.format(_endDate!)}'
        : '여행 기간 선택';
    final rangeSubLabel = hasRange
        ? (nightCount == 0 ? '당일 · $dayCount일' : '$nightCount박 $dayCount일')
        : '첫 탭 시작일, 두 번째 탭 종료일';

    return Scaffold(
      appBar: AppBar(
        title: const Text('여행 만들기'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '여행 이름',
                    hintText: '예: 제주 봄 여행',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return '여행 이름을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _regionController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '여행 지역',
                    hintText: '예: 제주도 / 오사카',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return '여행 지역을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _loading ? null : _pickDateRange,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    alignment: Alignment.centerLeft,
                    side: BorderSide(
                      color: hasRange ? AppColors.primary : AppColors.border,
                      width: hasRange ? 1.5 : 1,
                    ),
                    backgroundColor: hasRange
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.date_range,
                        color: hasRange
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '여행 기간',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              rangeLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: hasRange
                                        ? AppColors.textPrimary
                                        : AppColors.textSecondary,
                                    fontWeight: hasRange
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              rangeSubLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontSize: 12,
                                    color: hasRange
                                        ? AppColors.primary
                                        : AppColors.textSecondary,
                                    fontWeight: hasRange
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '종료일로 오늘 이전 날짜는 선택할 수 없습니다.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                      ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _memoController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '간단 메모 (선택)',
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('만들기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
