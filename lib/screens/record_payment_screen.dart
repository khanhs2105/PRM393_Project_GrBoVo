import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/money.dart';
import '../models/activity.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/settlement.dart';
import '../data/settlement_repository.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import '../widgets/app_icons.dart';

/// Ghi nhận một lần trả tiền bất kỳ ("Settle up"): chọn ai trả, ai nhận,
/// bao nhiêu. Dùng cho trả một phần hoặc trả bằng tiền mặt. Không ghi được
/// quá số người trả đang nợ (và người nhận đang được nợ).
class RecordPaymentScreen extends StatefulWidget {
  final Group group;
  final List<Member> members;

  /// Gợi ý thanh toán hiện tại, để điền sẵn số tiền khi chọn 2 người.
  final List<Transfer> transfers;
  final int? fromId;
  final int? toId;
  final int? amount;

  const RecordPaymentScreen({
    super.key,
    required this.group,
    required this.members,
    this.transfers = const [],
    this.fromId,
    this.toId,
    this.amount,
  });

  @override
  State<RecordPaymentScreen> createState() => _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends State<RecordPaymentScreen> {
  late int? _from = widget.fromId;
  late int? _to = widget.toId;
  late final _amount = TextEditingController(
      text: widget.amount == null ? '' : '${widget.amount}');
  final _note = TextEditingController();
  DateTime _date = DateTime.now();

  int get _amountValue => parseVnd(_amount.text) ?? 0;

  /// Số tối đa còn trả được giữa 2 người đang chọn, null khi chưa chọn đủ
  /// hoặc đang tải.
  int? _max;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _loadMax();
  }

  Future<void> _loadMax() async {
    final from = _from, to = _to;
    _max = null; // Gọi từ initState/_pick nên không cần setState ở đây.
    if (from == null || to == null) return;
    final max = await App.settlements.maxPayable(widget.group.id!, from, to);
    if (!mounted || from != _from || to != _to) return;
    setState(() => _max = max);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Số tiền gợi ý từ [_from] sang [_to], 0 nếu không có.
  int get _suggested {
    for (final t in widget.transfers) {
      if (t.fromId == _from && t.toId == _to) return t.amount;
    }
    return 0;
  }

  void _pick({int? from, int? to}) {
    setState(() {
      if (from != null) _from = from;
      if (to != null) _to = to;
      if (_from == _to) {
        if (from != null) _to = null;
        if (to != null) _from = null;
      }
    });
    // Chọn đủ 2 người mà chưa gõ số tiền thì điền sẵn số đang nợ.
    if (_amount.text.isEmpty && _suggested > 0) {
      _amount.text = '$_suggested';
    }
    _loadMax();
  }

  String _name(int id) => widget.members.firstWhere((m) => m.id == id).name;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _doSave();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _doSave() async {
    if (_from == null || _to == null) {
      showSnack(context, 'Chọn người trả và người nhận');
      return;
    }
    if (_amountValue <= 0) {
      showSnack(context, 'Nhập số tiền');
      return;
    }
    final note = _note.text.trim();
    try {
      await App.settlements.record(
        groupId: widget.group.id!,
        fromId: _from!,
        toId: _to!,
        amount: _amountValue,
        paidAt: _date,
        note: note.isEmpty ? null : note,
      );
    } on OverpaymentException catch (e) {
      if (!mounted) return;
      setState(() => _max = e.maxPayable);
      showSnack(
          context,
          e.maxPayable == 0
              ? '${_name(_from!)} không còn nợ ${_name(_to!)}'
              : 'Chỉ còn nợ ${formatVnd(e.maxPayable)}, không ghi quá số này');
      return;
    }
    await App.activities.log(
      groupId: widget.group.id,
      groupName: widget.group.name,
      kind: ActivityKind.settled,
      message: '${_name(_from!)} trả ${_name(_to!)}',
      amount: _amountValue,
    );
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    showSnack(context, 'Đã ghi nhận thanh toán ✓');
    Navigator.pop(context, true);
  }

  Widget _people(int? selected, ValueChanged<int> onPick, {int? disabled}) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final m in widget.members)
        ChoiceChip(
          avatar: MemberAvatar(m.name, radius: 12),
          label: Text(m.name),
          selected: selected == m.id,
          showCheckmark: false,
          onSelected: m.id == disabled ? null : (_) => onPick(m.id!),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final suggested = _from != null && _to != null ? _suggested : 0;
    final max = _max;
    final over = max != null && _amountValue > max;
    return Scaffold(
      appBar: AppBar(title: const Text('Ghi nhận thanh toán')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          const SectionHeader('Ai trả?'),
          _people(_from, (id) => _pick(from: id)),
          const SectionHeader('Trả cho ai?'),
          _people(_to, (id) => _pick(to: id), disabled: _from),
          const SectionHeader('Số tiền'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(
                  controller: _amount,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary),
                  decoration: InputDecoration(
                    hintText: '0',
                    filled: false,
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    suffixText: '₫',
                    helperText: _amountValue > 0 ? formatVnd(_amountValue) : null,
                    errorText: max != null && over && max > 0
                        ? 'Chỉ còn nợ ${formatVnd(max)}, không trả quá'
                        : null,
                  ),
                ),
                if (max == 0)
                  Text(
                    '${_name(_from!)} hiện không nợ ${_name(_to!)}, '
                    'không cần ghi nhận thanh toán.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error, fontSize: 12),
                  )
                else if (suggested > 0)
                  Wrap(spacing: 8, children: [
                    ActionChip(
                      label: Text('Trả hết ${formatVnd(suggested)}'),
                      onPressed: () => _amount.text = '$suggested',
                    ),
                    ActionChip(
                      label: Text('Một nửa ${formatVnd(suggested ~/ 2)}'),
                      onPressed: () => _amount.text = '${suggested ~/ 2}',
                    ),
                  ])
                else if (max != null)
                  ActionChip(
                    label: Text('Trả tối đa ${formatVnd(max)}'),
                    onPressed: () => _amount.text = '$max',
                  ),
              ]),
            ),
          ),
          const SectionHeader('Chi tiết'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              ListTile(
                leading: const Icon(AppIcons.calendar),
                title: const Text('Ngày trả'),
                trailing: Text(formatDate(_date),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(AppIcons.notebookPen),
                    hintText: 'Ghi chú, ví dụ: tiền mặt',
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving || over || max == 0 ? null : _save,
            icon: const Icon(AppIcons.check),
            label: const Text('Lưu thanh toán'),
          ),
        ),
      ),
    );
  }
}
