import 'package:flutter/material.dart';

import '../logic/emv_qr_parser.dart';
import '../logic/vietqr.dart';
import '../models/activity.dart';
import '../models/bank.dart';
import '../models/member.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
import 'qr_scan_screen.dart';

/// Thêm/sửa thành viên và tài khoản ngân hàng nhận tiền.
/// [member] có id null nghĩa là thêm mới.
class MemberFormScreen extends StatefulWidget {
  final Member member;
  const MemberFormScreen({super.key, required this.member});

  @override
  State<MemberFormScreen> createState() => _MemberFormScreenState();
}

class _MemberFormScreenState extends State<MemberFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.member.name);
  late final _accountNo = TextEditingController(text: widget.member.accountNo);
  late final _accountName =
      TextEditingController(text: widget.member.accountName);
  late String? _bin = widget.member.bankBin;
  // Đổi key để DropdownMenu vẽ lại khi ngân hàng được điền từ QR.
  int _bankFieldVersion = 0;

  bool get _isNew => widget.member.id == null;

  @override
  void dispose() {
    _name.dispose();
    _accountNo.dispose();
    _accountName.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final qr = await Navigator.push<BankAccountQr>(
        context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (qr == null || !mounted) return;
    final bank = findBankByBin(App.banks, qr.bin);
    setState(() {
      _bin = qr.bin;
      _bankFieldVersion++;
      _accountNo.text = qr.accountNo;
      if (qr.accountName != null) _accountName.text = qr.accountName!;
    });
    showSnack(
        context,
        bank == null
            ? 'Đã đọc số tài khoản. Mã ngân hàng ${qr.bin} chưa có trong danh sách.'
            : 'Đã điền ${bank.shortName} · ${qr.accountNo}');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final hasAccount = _accountNo.text.trim().isNotEmpty;
    if (hasAccount && _bin == null) {
      showSnack(context, 'Chọn ngân hàng');
      return;
    }
    final m = Member(
      id: widget.member.id,
      groupId: widget.member.groupId,
      name: _name.text.trim(),
      bankBin: hasAccount ? _bin : null,
      accountNo: hasAccount ? _accountNo.text.trim() : null,
      accountName: _accountName.text.trim().isEmpty
          ? null
          : removeDiacritics(_accountName.text.trim()).toUpperCase(),
    );
    if (_isNew) {
      await App.groups.addMember(m);
    } else {
      await App.groups.updateMember(m);
    }
    await _log(
      _isNew ? ActivityKind.memberAdded : ActivityKind.memberEdited,
      _isNew ? 'Thêm thành viên ${m.name}' : 'Sửa thông tin ${m.name}',
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _log(String kind, String message) async {
    final group = await App.groups.getById(widget.member.groupId);
    await App.activities.log(
      groupId: widget.member.groupId,
      groupName: group?.name ?? '',
      kind: kind,
      message: message,
    );
  }

  Future<void> _delete() async {
    final ok = await confirm(
        context, 'Xóa ${widget.member.name}?', 'Thành viên sẽ bị xóa khỏi nhóm.',
        ok: 'Xóa');
    if (!ok) return;
    final deleted = await App.groups.deleteMember(widget.member.id!);
    if (!mounted) return;
    if (deleted) {
      await _log(ActivityKind.memberDeleted,
          'Xóa thành viên ${widget.member.name}');
      if (mounted) Navigator.pop(context, true);
    } else {
      showSnack(context,
          'Không xóa được: người này đã có trong khoản chi hoặc lần trả tiền.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Thêm thành viên' : 'Sửa thành viên'),
        actions: [
          if (!_isNew)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Tên'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Nhập tên' : null,
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: Text('Tài khoản nhận tiền',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              FilledButton.tonalIcon(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Quét QR'),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Mở app ngân hàng, vào mục "QR nhận tiền" rồi quét để tự điền.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => DropdownMenu<String>(
                key: ValueKey(_bankFieldVersion),
                width: constraints.maxWidth,
                initialSelection: _bin,
                label: const Text('Ngân hàng'),
                enableFilter: true,
                requestFocusOnTap: true,
                menuHeight: 320,
                dropdownMenuEntries: [
                  for (final b in App.banks)
                    DropdownMenuEntry(
                        value: b.bin, label: '${b.shortName} (${b.code})'),
                ],
                onSelected: (v) => setState(() => _bin = v),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _accountNo,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Số tài khoản'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _accountName,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                  labelText: 'Tên chủ tài khoản (không bắt buộc)'),
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
