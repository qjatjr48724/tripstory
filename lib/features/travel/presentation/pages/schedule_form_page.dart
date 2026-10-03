import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/place.dart';
import '../../domain/schedule.dart';
import '../../domain/travel.dart';
import '../providers/travel_providers.dart';

class ScheduleFormPage extends ConsumerStatefulWidget {
  const ScheduleFormPage({
    super.key,
    required this.travelId,
    this.schedule,
    this.initialDate,
  });

  final String travelId;
  final ScheduleItem? schedule;
  final DateTime? initialDate;

  @override
  ConsumerState<ScheduleFormPage> createState() => _ScheduleFormPageState();
}

class _ScheduleFormPageState extends ConsumerState<ScheduleFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _memoController;
  late DateTime _date;
  TimeOfDay? _time;
  String? _placeId;
  String? _planB1PlaceId;
  String? _planB2PlaceId;
  bool _saving = false;

  bool get _isEdit => widget.schedule != null;

  @override
  void initState() {
    super.initState();
    final s = widget.schedule;
    _titleController = TextEditingController(text: s?.title ?? '');
    _memoController = TextEditingController(text: s?.memo ?? '');
    _date = _dateOnly(
      s?.scheduleDate ?? widget.initialDate ?? DateTime.now(),
    );
    if (s?.startTime != null) {
      final t = s!.startTime!;
      _time = TimeOfDay(hour: t.inHours, minute: t.inMinutes % 60);
    }
    _placeId = s?.placeId;
    _planB1PlaceId = s?.planBAt(1)?.placeId;
    _planB2PlaceId = s?.planBAt(2)?.placeId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  Duration? get _startDuration {
    final t = _time;
    if (t == null) return null;
    return Duration(hours: t.hour, minutes: t.minute);
  }

  Future<void> _pickDate(Travel travel) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: _dateOnly(travel.startDate),
      lastDate: _dateOnly(travel.endDate),
    );
    if (picked != null) setState(() => _date = _dateOnly(picked));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);

    final repo = ref.read(travelRepositoryProvider);
    try {
      ScheduleItem saved;
      if (_isEdit) {
        saved = await repo.updateSchedule(
          schedule: widget.schedule!,
          scheduleDate: _date,
          title: _titleController.text,
          placeId: _placeId,
          startTime: _startDuration,
          memo: _memoController.text,
        );
      } else {
        saved = await repo.createSchedule(
          travelId: widget.travelId,
          scheduleDate: _date,
          title: _titleController.text,
          placeId: _placeId,
          startTime: _startDuration,
          memo: _memoController.text,
        );
      }

      await repo.setPlanBSlot(
        scheduleId: saved.id,
        slot: 1,
        placeId: _planB1PlaceId,
      );
      await repo.setPlanBSlot(
        scheduleId: saved.id,
        slot: 2,
        placeId: _planB2PlaceId,
      );

      ref.invalidate(travelSchedulesProvider(widget.travelId));
      if (!mounted) return;
      context.pop();
    } on TravelException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final travelAsync = ref.watch(travelDetailProvider(widget.travelId));
    final placesAsync = ref.watch(travelPlacesProvider(widget.travelId));
    final dateFormat = DateFormat('yyyy.MM.dd (E)', 'ko');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '일정 수정' : '일정 추가'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('저장'),
          ),
        ],
      ),
      body: travelAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (travel) {
          return placesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (places) {
              return Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: '제목 *',
                        hintText: '예: 점심, 성 방문',
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return '제목을 입력하세요';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('날짜'),
                      subtitle: Text(dateFormat.format(_date)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () => _pickDate(travel),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('시작 시간'),
                      subtitle: Text(
                        _time == null
                            ? '없음 (시간은 순서와 별개입니다)'
                            : _time!.format(context),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_time != null)
                            IconButton(
                              tooltip: '시간 지우기',
                              onPressed: () => setState(() => _time = null),
                              icon: const Icon(Icons.clear),
                            ),
                          const Icon(Icons.access_time),
                        ],
                      ),
                      onTap: _pickTime,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '순서는 목록에서 드래그로 바꾸고, 시간은 자동으로 바뀌지 않습니다.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String?>(
                      key: ValueKey('place-$_placeId'),
                      initialValue: _placeId,
                      decoration: const InputDecoration(
                        labelText: '연결 장소 (선택)',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('연결 안 함'),
                        ),
                        ...places.map(
                          (p) => DropdownMenuItem(
                            value: p.id,
                            child: Text(p.name, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _placeId = v),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Plan B (대체 장소, 최대 2개)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    _PlanBDropdown(
                      label: 'Plan B 1',
                      value: _planB1PlaceId,
                      places: places,
                      excludePlaceId: _placeId,
                      onChanged: (v) => setState(() => _planB1PlaceId = v),
                    ),
                    const SizedBox(height: 12),
                    _PlanBDropdown(
                      label: 'Plan B 2',
                      value: _planB2PlaceId,
                      places: places,
                      excludePlaceId: _placeId,
                      onChanged: (v) => setState(() => _planB2PlaceId = v),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _memoController,
                      decoration: const InputDecoration(
                        labelText: '메모',
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_isEdit ? '수정 저장' : '일정 추가'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PlanBDropdown extends StatelessWidget {
  const _PlanBDropdown({
    required this.label,
    required this.value,
    required this.places,
    required this.onChanged,
    this.excludePlaceId,
  });

  final String label;
  final String? value;
  final List<Place> places;
  final String? excludePlaceId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = places.where((p) => p.id != excludePlaceId).toList();
    final effectiveValue =
        value != null && options.any((p) => p.id == value) ? value : null;

    return DropdownButtonFormField<String?>(
      key: ValueKey('$label-$effectiveValue'),
      initialValue: effectiveValue,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('없음'),
        ),
        ...options.map(
          (p) => DropdownMenuItem(
            value: p.id,
            child: Text(p.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
