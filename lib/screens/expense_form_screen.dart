import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logic/money.dart';
import '../logic/plans.dart';
import '../models/expense.dart';
import '../models/member.dart';
import '../services/app_services.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'plans_screen.dart';

/// Thêm hoặc sửa một khoản chi.
class ExpenseFormScreen extends StatefulWidget {
  final int groupId;
  final Expense? expense;
  const ExpenseFormScreen({super.key, required this.groupId, this.expense});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.expense?.title);
  late final _amount = TextEditingController(
      text: widget.expense == null ? '' : '${widget.expense!.amount}');

  List<Member> _members = [];
  int? _paidBy;
  final Set<int> _selected = {};
  late String _splitType = widget.expense?.splitType ?? 'equal';
  final Map<int, TextEditingController> _exact = {};
  String? _receiptPath;
  late DateTime _date = widget.expense?.date ?? DateTime.now();

  bool get _isEdit => widget.expense != null;
  int get _amountValue => parseVnd(_amount.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    App.groups.members(widget.groupId).then((members) {
      final e = widget.expense;
      setState(() {
        _members = members;
        _paidBy = e?.paidBy ?? members.first.id;
        _selected.addAll(e?.shares.keys ?? members.map((m) => m.id!));
        for (final m in members) {
          _exact[m.id!] = TextEditingController(
              text: e?.splitType == 'exact' && e!.shares.containsKey(m.id)
                  ? '${e.shares[m.id]}'
                  : '');
          _exact[m.id!]!.addListener(() => setState(() {}));
        }
        _receiptPath = e?.receiptPath;
      });
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    for (final c in _exact.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<int, int> _buildShares() {
    if (_splitType == 'equal') {
      return splitEqual(_amountValue, _selected.toList(), remainderTo: _paidBy);
    }
    return {
      for (final id in _selected) id: parseVnd(_exact[id]!.text) ?? 0,
    };
  }

  int get _exactTotal =>
      _selected.fold(0, (sum, id) => sum + (parseVnd(_exact[id]!.text) ?? 0));

  Future<void> _pickReceipt(ImageSource source) async {
    if (!App.plan.value.canAttachReceipt) {
      final go = await confirm(
          context,
          'Tính năng của Chủ Nợ 😎',
          'Gói Con Nợ không được đính kèm hóa đơn. Muốn có bằng chứng thì phải nâng cấp.',
          ok: 'Xem các gói');
      if (go && mounted) {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => const PlansScreen()));
      }
      return;
    }
    // image_picker tự xin quyền camera khi cần.
    final picked = await ImagePicker()
        .pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    if (picked == null) return;
    // Chép ảnh vào thư mục của app, vì ảnh tạm của image_picker có thể bị xóa.
    final dir = await getApplicationDocumentsDirectory();
    final dest = p.join(dir.path,
        'receipt_${DateTime.now().millisecondsSinceEpoch}${p.extension(picked.path)}');
    await File(picked.path).copy(dest);
    setState(() => _receiptPath = dest);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      showSnack(context, 'Chọn ít nhất 1 người tham gia');
      return;
    }
    final shares = _buildShares();
    if (!sharesMatchTotal(_amountValue, shares)) {
      showSnack(context,
          'Tổng các phần (${formatVnd(_exactTotal)}) phải bằng ${formatVnd(_amountValue)}');
      return;
    }
    await App.expenses.save(Expense(
      id: widget.expense?.id,
      groupId: widget.groupId,
      title: _title.text.trim(),
      amount: _amountValue,
      paidBy: _paidBy!,
      splitType: _splitType,
      shares: shares,
      receiptPath: _receiptPath,
      date: _date,
    ));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirm(context, 'Xóa khoản chi?',
        '"${widget.expense!.title}" sẽ bị xóa, số dư được tính lại.',
        ok: 'Xóa');
    if (!ok) return;
    await App.expenses.delete(widget.expense!.id!);
    if (mounted) Navigator.pop(context, true);
  }

  Widget _avatarChip(Member m, {required bool selected,
      required ValueChanged<bool> onSelected, bool filter = false}) {
    final avatar = MemberAvatar(m.name, radius: 12);
    return filter
        ? FilterChip(
            avatar: avatar,
            label: Text(m.name),
            selected: selected,
            showCheckmark: false,
            onSelected: onSelected,
          )
        : ChoiceChip(
            avatar: avatar,
            label: Text(m.name),
            selected: selected,
            showCheckmark: false,
            onSelected: onSelected,
          );
  }

  @override
  Widget build(BuildContext context) {
    if (_members.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final scheme = Theme.of(context).colorScheme;
    final equalPreview = _selected.isEmpty || _amountValue == 0
        ? null
        : splitEqual(_amountValue, _selected.toList(), remainderTo: _paidBy);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Sửa khoản chi' : 'Thêm khoản chi'),
        actions: [
          if (_isEdit)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            // Ô số tiền lớn ở trên cùng, giống các app chia tiền phổ biến.
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                child: Column(children: [
                  Row(children: [
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _title,
                      builder: (context, v, _) => IconTile.category(v.text),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _title,
                        decoration: const InputDecoration(
                            hintText: 'Nội dung, ví dụ: Lẩu Thái'),
                        textCapitalization: TextCapitalization.sentences,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nhập nội dung'
                            : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _amount,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.text,
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary),
                    decoration: InputDecoration(
                      hintText: '0',
                      filled: false,
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      suffixText: '₫',
                      helperText: _amountValue > 0
                          ? formatVnd(_amountValue)
                          : 'Gõ 150000, 150k hoặc 1.5tr',
                    ),
                    validator: (v) {
                      final x = parseVnd(v ?? '');
                      return (x == null || x <= 0) ? 'Số tiền không hợp lệ' : null;
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final quick in const [50000, 100000, 200000, 500000])
                        ActionChip(
                          label: Text(formatVnd(quick)),
                          onPressed: () => _amount.text = '$quick',
                        ),
                    ],
                  ),
                ]),
              ),
            ),
            const SectionHeader('Ai trả tiền?'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in _members)
                _avatarChip(m,
                    selected: _paidBy == m.id,
                    onSelected: (_) => setState(() => _paidBy = m.id)),
            ]),
            SectionHeader('Chia cho ai?',
                trailing: TextButton(
                  onPressed: () => setState(() =>
                      _selected.length == _members.length
                          ? _selected.clear()
                          : _selected.addAll(_members.map((m) => m.id!))),
                  child: Text(_selected.length == _members.length
                      ? 'Bỏ chọn hết'
                      : 'Chọn tất cả'),
                )),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'equal',
                    icon: Icon(Icons.drag_handle_rounded),
                    label: Text('Chia đều')),
                ButtonSegment(
                    value: 'exact',
                    icon: Icon(Icons.edit_note_rounded),
                    label: Text('Theo số tiền')),
              ],
              selected: {_splitType},
              onSelectionChanged: (v) => setState(() => _splitType = v.first),
            ),
            const SizedBox(height: 12),
            if (_splitType == 'equal') ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final m in _members)
                  _avatarChip(m,
                      filter: true,
                      selected: _selected.contains(m.id),
                      onSelected: (v) => setState(() =>
                          v ? _selected.add(m.id!) : _selected.remove(m.id))),
              ]),
              if (equalPreview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Mỗi người ${formatVnd(_amountValue ~/ _selected.length)}'
                    '${_amountValue % _selected.length == 0 ? '' : ' (phần lẻ ${_amountValue % _selected.length} ₫ tính cho người trả)'}',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
            ] else
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(children: [
                    for (final m in _members)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: Row(children: [
                          Checkbox(
                            value: _selected.contains(m.id),
                            onChanged: (v) => setState(() => v!
                                ? _selected.add(m.id!)
                                : _selected.remove(m.id)),
                          ),
                          MemberAvatar(m.name, radius: 14),
                          const SizedBox(width: 8),
                          Expanded(child: Text(m.name)),
                          SizedBox(
                            width: 130,
                            child: TextField(
                              controller: _exact[m.id],
                              enabled: _selected.contains(m.id),
                              textAlign: TextAlign.end,
                              decoration: const InputDecoration(
                                  isDense: true, hintText: '0', suffixText: '₫'),
                            ),
                          ),
                        ]),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(children: [
                        const Expanded(child: Text('Đã chia')),
                        Text(
                          '${formatVnd(_exactTotal)} / ${formatVnd(_amountValue)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _exactTotal == _amountValue
                                ? AppTheme.owed
                                : AppTheme.owe,
                          ),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            const SectionHeader('Chi tiết'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                ListTile(
                  leading: const Icon(Icons.event_rounded),
                  title: const Text('Ngày'),
                  trailing: Text(formatDate(_date),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _date = d);
                  },
                ),
                const Divider(height: 1),
                ValueListenableBuilder<Plan>(
                  valueListenable: App.plan,
                  builder: (context, plan, _) => ListTile(
                    leading: const Icon(Icons.receipt_long_rounded),
                    title: const Text('Ảnh hóa đơn'),
                    subtitle: plan.canAttachReceipt
                        ? null
                        : const Text('Cần gói Chủ Nợ trở lên'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (!plan.canAttachReceipt)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.lock_outline, size: 18),
                        ),
                      IconButton(
                        tooltip: 'Chụp ảnh',
                        onPressed: () => _pickReceipt(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                      ),
                      IconButton(
                        tooltip: 'Chọn từ thư viện',
                        onPressed: () => _pickReceipt(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                      ),
                    ]),
                  ),
                ),
                if (_receiptPath != null && File(_receiptPath!).existsSync())
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(File(_receiptPath!),
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton.filledTonal(
                          onPressed: () => setState(() => _receiptPath = null),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(_isEdit ? 'Lưu thay đổi' : 'Thêm khoản chi'),
          ),
        ),
      ),
    );
  }
}
