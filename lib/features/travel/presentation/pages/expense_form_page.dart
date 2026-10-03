import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/roles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/travel_repository.dart';
import '../../domain/expense.dart';
import '../../domain/travel_member.dart';
import '../providers/travel_providers.dart';

class ExpenseFormPage extends ConsumerStatefulWidget {
  const ExpenseFormPage({
    super.key,
    required this.travelId,
    this.expense,
  });

  final String travelId;
  final Expense? expense;

  @override
  ConsumerState<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  final Map<String, TextEditingController> _customShareControllers = {};

  late ExpenseCategory _category;
  late PaymentMethod _paymentMethod;
  late SplitType _splitType;
  late String _currency;
  late DateTime _paidAt;
  late bool _excludeFromSettlement;
  String? _payerMemberId;
  final Set<String> _participantIds = {};
  bool _saving = false;
  bool _initializedMembers = false;

  bool get _isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _amountController = TextEditingController(
      text: e != null ? '${e.amount}' : '',
    );
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _category = e?.category ?? ExpenseCategory.food;
    _paymentMethod = e?.paymentMethod ?? PaymentMethod.card;
    _splitType = e?.splitType ?? SplitType.equal;
    _currency = e?.currency ?? 'KRW';
    _paidAt = e?.paidAt.toLocal() ?? DateTime.now();
    _excludeFromSettlement = e?.excludeFromSettlement ?? false;
    _payerMemberId = e?.payerMemberId;
    if (e != null) {
      for (final p in e.participants) {
        _participantIds.add(p.memberId);
        _customShareControllers[p.memberId] = TextEditingController(
          text: '${p.shareAmount}',
        );
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    for (final c in _customShareControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureMemberState(List<TravelMember> activeMembers) {
    if (_initializedMembers) return;
    _initializedMembers = true;

    if (_payerMemberId == null ||
        !activeMembers.any((m) => m.id == _payerMemberId)) {
      final me = activeMembers.where((m) => m.isMe).firstOrNull;
      _payerMemberId = me?.id ?? activeMembers.firstOrNull?.id;
    }

    if (!_isEdit && _participantIds.isEmpty) {
      _participantIds.addAll(activeMembers.map((m) => m.id));
    }

    for (final m in activeMembers) {
      _customShareControllers.putIfAbsent(
        m.id,
        () => TextEditingController(text: '0'),
      );
    }
  }

  int get _amount {
    final raw = _amountController.text.replaceAll(',', '').trim();
    return int.tryParse(raw) ?? 0;
  }

  Map<String, int> get _customShares {
    final map = <String, int>{};
    for (final id in _participantIds) {
      final raw =
          _customShareControllers[id]?.text.replaceAll(',', '').trim() ?? '0';
      map[id] = int.tryParse(raw) ?? 0;
    }
    return map;
  }

  ({int each, int remainder, int customSum}) _previewSplit() {
    final amount = _amount;
    if (_excludeFromSettlement || _participantIds.isEmpty) {
      return (each: 0, remainder: 0, customSum: 0);
    }
    if (_splitType == SplitType.equal) {
      final r = equalSplitShares(amount, _participantIds.length);
      return (
        each: r.shares.isEmpty ? 0 : r.shares.first,
        remainder: r.remainder,
        customSum: 0,
      );
    }
    final sum = _customShares.values.fold<int>(0, (a, b) => a + b);
    return (each: 0, remainder: amount - sum, customSum: sum);
  }

  Future<void> _pickPaidAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _paidAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_paidAt),
    );
    if (time == null) return;
    setState(() {
      _paidAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save({
    required bool canChangeParticipants,
  }) async {
    if (!_formKey.currentState!.validate() || _saving) return;

    final payerId = _payerMemberId;
    if (payerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('결제자를 선택하세요')),
      );
      return;
    }

    if (!_excludeFromSettlement && _participantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정산 참여자를 한 명 이상 선택하세요')),
      );
      return;
    }

    if (_isEdit &&
        !canChangeParticipants &&
        !_participantsUnchanged(widget.expense!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정산 참여자 변경은 여행장·총무만 할 수 있어요')),
      );
      return;
    }

    if (_splitType == SplitType.custom && !_excludeFromSettlement) {
      final preview = _previewSplit();
      if (preview.customSum > _amount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('분담 합계가 총액보다 클 수 없습니다')),
        );
        return;
      }
    }

    setState(() => _saving = true);
    final repo = ref.read(travelRepositoryProvider);
    try {
      if (_isEdit) {
        await repo.updateExpense(
          expense: widget.expense!,
          category: _category,
          amount: _amount,
          currency: _currency,
          payerMemberId: payerId,
          paymentMethod: _paymentMethod,
          paidAt: _paidAt,
          splitType: _splitType,
          participantMemberIds: _participantIds.toList(),
          customShares: _splitType == SplitType.custom ? _customShares : null,
          description: _descriptionController.text,
          excludeFromSettlement: _excludeFromSettlement,
        );
      } else {
        await repo.createExpense(
          travelId: widget.travelId,
          category: _category,
          amount: _amount,
          currency: _currency,
          payerMemberId: payerId,
          paymentMethod: _paymentMethod,
          paidAt: _paidAt,
          splitType: _splitType,
          participantMemberIds: _participantIds.toList(),
          customShares: _splitType == SplitType.custom ? _customShares : null,
          description: _descriptionController.text,
          excludeFromSettlement: _excludeFromSettlement,
        );
      }
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

  bool _participantsUnchanged(Expense original) {
    if (original.excludeFromSettlement != _excludeFromSettlement) {
      return false;
    }
    if (_excludeFromSettlement) return true;

    final originalIds = original.participants.map((p) => p.memberId).toSet();
    if (!_setEquals(originalIds, _participantIds)) return false;
    if (original.splitType != _splitType) return false;
    if (_splitType == SplitType.custom) {
      for (final p in original.participants) {
        if ((_customShares[p.memberId] ?? 0) != p.shareAmount) return false;
      }
    }
    return true;
  }

  bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(travelMembersProvider(widget.travelId));
    final travelAsync = ref.watch(travelDetailProvider(widget.travelId));
    final dateFormat = DateFormat('yyyy.MM.dd HH:mm', 'ko');
    final amountFormat = NumberFormat('#,###');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '비용 수정' : '비용 추가'),
        actions: [
          travelAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (travel) {
              final role = travel.myRole;
              final canChangeParticipants =
                  role?.canChangeSettlementParticipants ?? false;
              return TextButton(
                onPressed: _saving
                    ? null
                    : () => _save(
                          canChangeParticipants: canChangeParticipants,
                        ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('저장'),
              );
            },
          ),
        ],
      ),
      body: membersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (members) {
          final active =
              members.where((m) => m.status == MemberStatus.active).toList();
          if (active.isEmpty) {
            return const Center(child: Text('활성 구성원이 없습니다.'));
          }
          _ensureMemberState(active);

          final role = travelAsync.asData?.value.myRole;
          final canChangeParticipants =
              !_isEdit || (role?.canChangeSettlementParticipants ?? false);
          final preview = _previewSplit();

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                DropdownMenu<ExpenseCategory>(
                  key: ValueKey(_category),
                  initialSelection: _category,
                  label: const Text('항목 *'),
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: false,
                  requestFocusOnTap: false,
                  dropdownMenuEntries: ExpenseCategory.values
                      .map(
                        (c) => DropdownMenuEntry(
                          value: c,
                          label: c.label,
                        ),
                      )
                      .toList(),
                  onSelected: (v) {
                    if (v != null) setState(() => _category = v);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: '설명',
                    hintText: '예: 저녁 식사, 지하철',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _amountController,
                        decoration: const InputDecoration(labelText: '금액 *'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = int.tryParse(v?.trim() ?? '');
                          if (n == null) return '금액을 입력하세요';
                          if (n < 0) return '0 이상이어야 합니다';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _currency,
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
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _payerMemberId,
                  decoration: const InputDecoration(labelText: '실제 결제자 *'),
                  items: active
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(m.isMe ? '${m.displayName} (나)' : m.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _payerMemberId = v);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PaymentMethod>(
                  value: _paymentMethod,
                  decoration: const InputDecoration(labelText: '결제 수단'),
                  items: PaymentMethod.values
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(m.label),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _paymentMethod = v);
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('결제 일시'),
                  subtitle: Text(dateFormat.format(_paidAt)),
                  trailing: const Icon(Icons.schedule_outlined),
                  onTap: _pickPaidAt,
                ),
                const Divider(height: 32),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('정산 제외'),
                  subtitle: const Text('개인 지출 등 정산에 넣지 않을 때'),
                  value: _excludeFromSettlement,
                  onChanged: canChangeParticipants
                      ? (v) => setState(() => _excludeFromSettlement = v)
                      : null,
                ),
                if (!_excludeFromSettlement) ...[
                  const SizedBox(height: 8),
                  Text(
                    '정산 참여자',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (!canChangeParticipants)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        '참여자·분담 변경은 여행장·총무만 가능합니다.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ),
                  ...active.map((m) {
                    final selected = _participantIds.contains(m.id);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: selected,
                      title: Text(m.isMe ? '${m.displayName} (나)' : m.displayName),
                      onChanged: canChangeParticipants
                          ? (v) {
                              setState(() {
                                if (v == true) {
                                  _participantIds.add(m.id);
                                } else {
                                  _participantIds.remove(m.id);
                                }
                              });
                            }
                          : null,
                    );
                  }),
                  const SizedBox(height: 8),
                  SegmentedButton<SplitType>(
                    segments: SplitType.values
                        .map(
                          (s) => ButtonSegment(
                            value: s,
                            label: Text(s.label),
                          ),
                        )
                        .toList(),
                    selected: {_splitType},
                    onSelectionChanged: canChangeParticipants
                        ? (set) => setState(() => _splitType = set.first)
                        : null,
                  ),
                  const SizedBox(height: 12),
                  if (_splitType == SplitType.equal)
                    Text(
                      _participantIds.isEmpty
                          ? '참여자를 선택하면 1인 분담이 계산됩니다.'
                          : '1인 ${amountFormat.format(preview.each)}'
                              '${preview.remainder > 0 ? ' · 미배분 ${amountFormat.format(preview.remainder)}' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    )
                  else ...[
                    ..._participantIds.map((id) {
                      final member =
                          active.where((m) => m.id == id).firstOrNull;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextFormField(
                          controller: _customShareControllers[id],
                          enabled: canChangeParticipants,
                          decoration: InputDecoration(
                            labelText: member?.displayName ?? '구성원',
                            suffixText: _currency,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                        ),
                      );
                    }),
                    Text(
                      '합계 ${amountFormat.format(preview.customSum)}'
                      ' / 총액 ${amountFormat.format(_amount)}'
                      '${preview.remainder != 0 ? ' · 미배분 ${amountFormat.format(preview.remainder)}' : ''}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: preview.remainder < 0
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
