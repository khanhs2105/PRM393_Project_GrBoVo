import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../logic/money.dart';
import '../logic/plans.dart';
import '../models/expense.dart';
import '../models/member.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
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
    if (source == ImageSource.camera &&
        !(await Permission.camera.request()).isGranted) {
      if (mounted) showSnack(context, 'Cần quyền camera để chụp hóa đơn');
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    if (_members.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                  labelText: 'Nội dung', hintText: 'Ví dụ: Lẩu Thái'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nhập nội dung' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: 'Số tiền',
                hintText: '150000, 150k, 1.5tr',
                helperText: _amountValue > 0 ? formatVnd(_amountValue) : null,
              ),
              validator: (v) {
                final x = parseVnd(v ?? '');
                return (x == null || x <= 0) ? 'Số tiền không hợp lệ' : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _paidBy,
              decoration: const InputDecoration(labelText: 'Ai trả tiền'),
              items: [
                for (final m in _members)
                  DropdownMenuItem(value: m.id, child: Text(m.name)),
              ],
              onChanged: (v) => setState(() => _paidBy = v),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Ngày: ${formatDate(_date)}'),
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
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'equal', label: Text('Chia đều')),
                ButtonSegment(value: 'exact', label: Text('Theo số tiền')),
              ],
              selected: {_splitType},
              onSelectionChanged: (v) => setState(() => _splitType = v.first),
            ),
            const SizedBox(height: 8),
            for (final m in _members)
              _splitType == 'equal'
                  ? CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(m.id),
                      onChanged: (v) => setState(() =>
                          v! ? _selected.add(m.id!) : _selected.remove(m.id)),
                      title: Text(m.name),
                      secondary: MemberAvatar(m.name),
                      subtitle: equalPreview?[m.id] == null
                          ? null
                          : Text(formatVnd(equalPreview![m.id]!)),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Checkbox(
                          value: _selected.contains(m.id),
                          onChanged: (v) => setState(() =>
                              v! ? _selected.add(m.id!) : _selected.remove(m.id)),
                        ),
                        Expanded(child: Text(m.name)),
                        SizedBox(
                          width: 140,
                          child: TextField(
                            controller: _exact[m.id],
                            enabled: _selected.contains(m.id),
                            decoration: const InputDecoration(
                                isDense: true, hintText: 'Số tiền'),
                          ),
                        ),
                      ]),
                    ),
            if (_splitType == 'exact')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Đã chia ${formatVnd(_exactTotal)} / ${formatVnd(_amountValue)}'
                  '${_exactTotal == _amountValue ? ' ✓' : ''}',
                  style: TextStyle(
                    color: _exactTotal == _amountValue
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text('Hóa đơn', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_receiptPath != null && File(_receiptPath!).existsSync())
              Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(_receiptPath!),
                      height: 200, width: double.infinity, fit: BoxFit.cover),
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
            ValueListenableBuilder<Plan>(
              valueListenable: App.plan,
              builder: (context, plan, _) => Row(children: [
                OutlinedButton.icon(
                  onPressed: () => _pickReceipt(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Chụp'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickReceipt(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Thư viện'),
                ),
                if (!plan.canAttachReceipt) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.lock_outline, size: 18),
                ],
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(onPressed: _save, child: const Text('Lưu')),
        ),
      ),
    );
  }
}
