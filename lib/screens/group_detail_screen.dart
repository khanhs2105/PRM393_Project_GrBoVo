import 'dart:io';

import 'package:flutter/material.dart';

import '../data/group_summary.dart';
import '../logic/money.dart';
import '../logic/plans.dart';
import '../models/bank.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/settlement.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
import '../widgets/shake_picker.dart';
import 'expense_form_screen.dart';
import 'group_form_screen.dart';
import 'member_form_screen.dart';
import 'payment_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final int groupId;
  const GroupDetailScreen({super.key, required this.groupId});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late Future<(Group, GroupSummary)> _future = _load();

  Future<(Group, GroupSummary)> _load() async => (
        (await App.groups.getById(widget.groupId))!,
        await GroupSummary.load(App.db, widget.groupId),
      );

  void _reload() => setState(() => _future = _load());

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _reload();
  }

  Future<void> _deleteGroup(Group g) async {
    final ok = await confirm(context, 'Xóa nhóm "${g.name}"?',
        'Toàn bộ khoản chi và lịch sử trả tiền của nhóm sẽ bị xóa.',
        ok: 'Xóa');
    if (!ok) return;
    await App.groups.delete(g.id!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Group, GroupSummary)>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: snap.hasError
                  ? Text('Lỗi: ${snap.error}')
                  : const CircularProgressIndicator(),
            ),
          );
        }
        final (group, s) = snap.data!;
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: Text(group.name),
              actions: [
                ValueListenableBuilder<Plan>(
                  valueListenable: App.plan,
                  builder: (context, plan, _) => IconButton(
                    tooltip: 'Lắc để chọn người bao',
                    icon: const Icon(Icons.casino_outlined),
                    onPressed: () => showShakePicker(context, s.members, plan),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _open(GroupFormScreen(group: group));
                    if (v == 'delete') _deleteGroup(group);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Sửa nhóm')),
                    PopupMenuItem(value: 'delete', child: Text('Xóa nhóm')),
                  ],
                ),
              ],
              bottom: const TabBar(tabs: [
                Tab(text: 'Khoản chi'),
                Tab(text: 'Số dư'),
                Tab(text: 'Thành viên'),
              ]),
            ),
            body: TabBarView(children: [
              _ExpensesTab(
                summary: s,
                onOpen: (e) =>
                    _open(ExpenseFormScreen(groupId: group.id!, expense: e)),
              ),
              _BalancesTab(
                group: group,
                summary: s,
                onPay: (t) => _open(PaymentScreen(group: group, transfer: t)),
                onUndo: (settlement) async {
                  final ok = await confirm(context, 'Hoàn tác?',
                      'Xóa lần trả ${formatVnd(settlement.amount)} này khỏi lịch sử.',
                      ok: 'Xóa');
                  if (!ok) return;
                  await App.settlements.delete(settlement.id!);
                  _reload();
                },
              ),
              _MembersTab(
                summary: s,
                onOpen: (m) => _open(MemberFormScreen(member: m)),
                onAdd: () => _open(
                    MemberFormScreen(member: Member(groupId: group.id!, name: ''))),
              ),
            ]),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => _open(ExpenseFormScreen(groupId: group.id!)),
              icon: const Icon(Icons.add),
              label: const Text('Thêm khoản chi'),
            ),
          ),
        );
      },
    );
  }
}

class _ExpensesTab extends StatelessWidget {
  final GroupSummary summary;
  final void Function(Expense) onOpen;
  const _ExpensesTab({required this.summary, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s.expenses.isEmpty) {
      return const Center(child: Text('Chưa có khoản chi nào'));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Tổng đã chi: ${formatVnd(s.totalSpent)}',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final e in s.expenses)
          ListTile(
            leading: e.receiptPath != null && File(e.receiptPath!).existsSync()
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(e.receiptPath!),
                        width: 44, height: 44, fit: BoxFit.cover),
                  )
                : const CircleAvatar(child: Icon(Icons.receipt_long)),
            title: Text(e.title),
            subtitle: Text('${s.memberById(e.paidBy).name} trả · '
                'chia ${e.shares.length} người · ${formatDate(e.date)}'),
            trailing: Text(formatVnd(e.amount),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            onTap: () => onOpen(e),
          ),
      ],
    );
  }
}

class _BalancesTab extends StatelessWidget {
  final Group group;
  final GroupSummary summary;
  final void Function(Transfer) onPay;
  final void Function(Settlement) onUndo;
  const _BalancesTab({
    required this.group,
    required this.summary,
    required this.onPay,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text('Cần thanh toán', style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Đã rút gọn: ${s.members.length} người chỉ cần '
          '${s.transfers.length} lượt chuyển.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 8),
        if (s.transfers.isEmpty)
          const Card(
            child: ListTile(
              leading: Text('🎉', style: TextStyle(fontSize: 28)),
              title: Text('Không ai nợ ai'),
            ),
          ),
        for (final t in s.transfers)
          Card(
            child: ListTile(
              leading: MemberAvatar(s.memberById(t.fromId).name),
              title: Text(
                  '${s.memberById(t.fromId).name} → ${s.memberById(t.toId).name}'),
              subtitle: Text(formatVnd(t.amount),
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600)),
              trailing: FilledButton.tonalIcon(
                onPressed: () => onPay(t),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Trả'),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text('Số dư từng người', style: text.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            for (final m in s.members)
              ListTile(
                leading: MemberAvatar(m.name),
                title: Text(m.name),
                subtitle: Text(_balanceLabel(s.balances[m.id] ?? 0)),
                trailing: Text(
                  formatVnd(s.balances[m.id] ?? 0),
                  style: TextStyle(
                    color: balanceColor(context, s.balances[m.id] ?? 0),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ]),
        ),
        if (s.settlements.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Lịch sử thanh toán', style: text.titleMedium),
          Text('Nhấn giữ để hoàn tác nếu bấm nhầm.', style: text.bodySmall),
          const SizedBox(height: 8),
          for (final st in s.settlements)
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(
                  '${s.memberById(st.fromId).name} đã trả ${s.memberById(st.toId).name}'),
              subtitle: Text(formatDateTime(st.paidAt)),
              trailing: Text(formatVnd(st.amount)),
              onLongPress: () => onUndo(st),
            ),
        ],
      ],
    );
  }

  String _balanceLabel(int v) =>
      v > 0 ? 'Được nợ' : (v < 0 ? 'Đang nợ' : 'Đã xong');
}

class _MembersTab extends StatelessWidget {
  final GroupSummary summary;
  final void Function(Member) onOpen;
  final VoidCallback onAdd;
  const _MembersTab(
      {required this.summary, required this.onOpen, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final m in summary.members)
          ListTile(
            leading: MemberAvatar(m.name),
            title: Text(m.name),
            subtitle: Text(m.hasBank
                ? '${findBankName(m.bankBin)} · ${m.accountNo}'
                : 'Chưa có tài khoản ngân hàng'),
            trailing: Icon(
              m.hasBank ? Icons.account_balance : Icons.warning_amber,
              color: m.hasBank ? null : Colors.orange,
            ),
            onTap: () => onOpen(m),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Thêm thành viên'),
          ),
        ),
      ],
    );
  }
}

String findBankName(String? bin) =>
    findBankByBin(App.banks, bin)?.shortName ?? bin ?? '';
