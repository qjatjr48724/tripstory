import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/expense.dart';
import '../../domain/reservation.dart';
import '../../domain/travel_member.dart';
import '../providers/travel_providers.dart';

class ReservationFormPage extends ConsumerStatefulWidget {
  const ReservationFormPage({
    super.key,
    required this.travelId,
    this.reservation,
    this.initialType,
  });

  final String travelId;
  final Reservation? reservation;

  /// 목록 탭에서 넘어올 때 기본 유형 (신규 등록만)
  final ReservationType? initialType;

  @override
  ConsumerState<ReservationFormPage> createState() =>
      _ReservationFormPageState();
}

class _ReservationFormPageState extends ConsumerState<ReservationFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _confirmationController;
  late final TextEditingController _costController;
  late final TextEditingController _urlController;
  late final TextEditingController _memoController;
  late final TextEditingController _addressController;
  late final TextEditingController _roomController;

  late ReservationType _type;
  late String _currency;
  String? _bookerMemberId;
  DateTime? _startsAt;
  bool _saving = false;

  final _removeImageIds = <String>{};
  final _newImages =
      <({Uint8List bytes, String contentType, String ext})>[];

  bool get _isEdit => widget.reservation != null;

  @override
  void initState() {
    super.initState();
    final r = widget.reservation;
    _titleController = TextEditingController(text: r?.title ?? '');
    _confirmationController =
        TextEditingController(text: r?.confirmationNumber ?? '');
    _costController = TextEditingController(
      text: r?.costAmount != null ? '${r!.costAmount}' : '',
    );
    _urlController = TextEditingController(text: r?.confirmationUrl ?? '');
    _memoController = TextEditingController(text: r?.memo ?? '');
    _addressController = TextEditingController(text: r?.lodgingAddress ?? '');
    _roomController = TextEditingController(text: r?.lodgingRoomInfo ?? '');
    _type = r?.type ?? widget.initialType ?? ReservationType.transport;
    _currency = r?.costCurrency ?? 'KRW';
    _bookerMemberId = r?.bookerMemberId;
    _startsAt = r?.startsAt?.toLocal();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _confirmationController.dispose();
    _costController.dispose();
    _urlController.dispose();
    _memoController.dispose();
    _addressController.dispose();
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _pickStartsAt() async {
    final now = DateTime.now();
    final initial = _startsAt ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      _startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? 'image/jpeg';
    final ext = switch (mime) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      _ => 'jpg',
    };
    setState(() {
      _newImages.add((bytes: bytes, contentType: mime, ext: ext));
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);

    final costRaw = _costController.text.replaceAll(',', '').trim();
    final cost = costRaw.isEmpty ? null : int.tryParse(costRaw);
    final repo = ref.read(travelRepositoryProvider);

    try {
      if (_isEdit) {
        await repo.updateReservation(
          reservation: widget.reservation!,
          type: _type,
          title: _titleController.text,
          bookerMemberId: _bookerMemberId,
          confirmationNumber: _confirmationController.text,
          costAmount: cost,
          costCurrency: _currency,
          startsAt: _startsAt,
          confirmationUrl: _urlController.text,
          memo: _memoController.text,
          lodgingAddress: _addressController.text,
          lodgingRoomInfo: _roomController.text,
          newImages: _newImages,
          removeImageIds: _removeImageIds.toList(),
        );
      } else {
        await repo.createReservation(
          travelId: widget.travelId,
          type: _type,
          title: _titleController.text,
          bookerMemberId: _bookerMemberId,
          confirmationNumber: _confirmationController.text,
          costAmount: cost,
          costCurrency: _currency,
          startsAt: _startsAt,
          confirmationUrl: _urlController.text,
          memo: _memoController.text,
          lodgingAddress: _addressController.text,
          lodgingRoomInfo: _roomController.text,
          images: _newImages,
        );
      }
      ref.invalidate(travelReservationsProvider(widget.travelId));
      ref.invalidate(travelExpensesProvider(widget.travelId));
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
    final membersAsync = ref.watch(travelMembersProvider(widget.travelId));
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm', 'ko');
    final existingImages = (widget.reservation?.images ?? [])
        .where((i) => !_removeImageIds.contains(i.id))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '예약 수정' : '예약 추가'),
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
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (members) {
          final active =
              members.where((m) => m.status == MemberStatus.active).toList();
          _bookerMemberId ??=
              active.where((m) => m.isMe).firstOrNull?.id ??
                  active.firstOrNull?.id;

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                DropdownMenu<ReservationType>(
                  key: ValueKey(_type),
                  initialSelection: _type,
                  label: const Text('유형 *'),
                  expandedInsets: EdgeInsets.zero,
                  requestFocusOnTap: false,
                  dropdownMenuEntries: ReservationType.values
                      .map(
                        (t) => DropdownMenuEntry(value: t, label: t.label),
                      )
                      .toList(),
                  onSelected: (v) {
                    if (v != null) setState(() => _type = v);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '제목 *',
                    hintText: '예: 인천 → 오사카, OO호텔',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '제목을 입력하세요' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _bookerMemberId,
                  decoration: const InputDecoration(labelText: '예약자'),
                  items: active
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(
                            m.isMe ? '${m.displayName} (나)' : m.displayName,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _bookerMemberId = v),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmationController,
                  decoration: const InputDecoration(
                    labelText: '예약번호',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _costController,
                        decoration: const InputDecoration(labelText: '비용'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: const InputDecoration(labelText: '통화'),
                        items: supportedCurrencies
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(c),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _currency = v);
                        },
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Text(
                    '비용을 입력하면 비용 탭에 자동 등록됩니다. '
                    '(결제자=예약자, 활성 구성원 1/N · 분담은 비용에서 수정 가능)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('시작 일시 (선택)'),
                  subtitle: Text(
                    _startsAt == null
                        ? '없음'
                        : dateFormat.format(_startsAt!),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_startsAt != null)
                        IconButton(
                          onPressed: () => setState(() => _startsAt = null),
                          icon: const Icon(Icons.clear),
                        ),
                      const Icon(Icons.schedule_outlined),
                    ],
                  ),
                  onTap: _pickStartsAt,
                ),
                TextFormField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: '예약 확인 링크',
                    hintText: 'https://...',
                  ),
                  keyboardType: TextInputType.url,
                ),
                if (_type == ReservationType.lodging) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(labelText: '숙소 주소'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _roomController,
                    decoration: const InputDecoration(labelText: '객실 정보'),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _memoController,
                  decoration: const InputDecoration(labelText: '메모'),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      '확인 이미지',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('추가'),
                    ),
                  ],
                ),
                if (existingImages.isEmpty && _newImages.isEmpty)
                  Text(
                    '스크린샷 등 확인 이미지를 첨부할 수 있어요. (선택, 장당 최대 5MB)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ...existingImages.map((img) {
                  return FutureBuilder<String?>(
                    future: ref
                        .read(travelRepositoryProvider)
                        .signedMediaUrl(img.storagePath),
                    builder: (context, snap) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: snap.data != null
                            ? Image.network(
                                snap.data!,
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.image_outlined),
                        title: const Text('첨부 이미지'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () =>
                              setState(() => _removeImageIds.add(img.id)),
                        ),
                      );
                    },
                  );
                }),
                ..._newImages.asMap().entries.map((e) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Image.memory(
                      e.value.bytes,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                    title: Text('새 이미지 ${e.key + 1}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          setState(() => _newImages.removeAt(e.key)),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }
}
