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
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/shake_picker.dart';
import '../widgets/ui.dart';
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
            ),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _GroupHeader(group: group, summary: s),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const TabBar(tabs: [
                    Tab(text: 'Khoản chi', height: 40),
                    Tab(text: 'Số dư', height: 40),
                    Tab(text: 'Thành viên', height: 40),
                  ]),
                ),
              ),
              Expanded(
                child: TabBarView(children: [
                  _ExpensesTab(
                    summary: s,
                    onOpen: (e) =>
                        _open(ExpenseFormScreen(groupId: group.id!, expense: e)),
                    onAdd: () => _open(ExpenseFormScreen(groupId: group.id!)),
                  ),
                  _BalancesTab(
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
                    onAdd: () => _open(MemberFormScreen(
                        member: Member(groupId: group.id!, name: ''))),
                  ),
                ]),
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

class _GroupHeader extends StatelessWidget {
  final Group group;
  final GroupSummary summary;
  const _GroupHeader({required this.group, required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final perPerson = s.members.isEmpty ? 0 : s.totalSpent ~/ s.members.length;
    final color = groupTypeColor(group.type);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          IconTile(groupTypeIcon(group.type), color, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Tổng chi', style: TextStyle(color: muted, fontSize: 13)),
              Text(formatVnd(s.totalSpent),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              Text('Trung bình ${formatVnd(perPerson)}/người',
                  style: TextStyle(color: muted, fontSize: 13)),
            ]),
          ),
          AvatarStack(s.members.map((m) => m.name).toList(), max: 3),
        ]),
      ),
    );
  }
}

class _ExpensesTab extends StatelessWidget {
  final GroupSummary summary;
  final void Function(Expense) onOpen;
  final VoidCallback onAdd;
  const _ExpensesTab(
      {required this.summary, required this.onOpen, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s.expenses.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long,
        title: 'Chưa có khoản chi',
        message: 'Thêm bữa ăn, tiền phòng hay tiền điện đầu tiên của nhóm.',
        actionLabel: 'Thêm khoản chi',
        onAction: onAdd,
      );
    }
    // Gom khoản chi theo ngày, danh sách đã sắp mới nhất trước.
    final byDay = <String, List<Expense>>{};
    for (final e in s.expenses) {
      byDay.putIfAbsent(dayLabel(e.date), () => []).add(e);
    }
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        for (final entry in byDay.entries) ...[
          SectionHeader(entry.key,
              trailing: Text(
                  formatVnd(entry.value.fold(0, (sum, e) => sum + e.amount)),
                  style: TextStyle(color: muted, fontSize: 12))),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, e) in entry.value.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 72),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: e.receiptPath != null &&
                          File(e.receiptPath!).existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.file(File(e.receiptPath!),
                              width: 44, height: 44, fit: BoxFit.cover),
                        )
                      : IconTile.category(e.title),
                  title: Text(e.title,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      '${s.memberById(e.paidBy).name} đã trả · chia ${e.shares.length} người'),
                  trailing: Text(formatVnd(e.amount),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  onTap: () => onOpen(e),
                ),
              ],
            ]),
          ),
        ],
      ],
    );
  }
}

class _BalancesTab extends StatelessWidget {
  final GroupSummary summary;
  final void Function(Transfer) onPay;
  final void Function(Settlement) onUndo;
  const _BalancesTab({
    required this.summary,
    required this.onPay,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final maxAbs = s.balances.values
        .fold<int>(0, (m, v) => v.abs() > m ? v.abs() : m);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        SectionHeader('Cần thanh toán',
            trailing: Text('${s.transfers.length} lượt',
                style: TextStyle(color: muted, fontSize: 12))),
        if (s.transfers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(children: [
                Text('🎉', style: TextStyle(fontSize: 32)),
                SizedBox(width: 16),
                Expanded(
                  child: Text('Không ai nợ ai. Nhóm đã sòng phẳng!',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        for (final t in s.transfers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TransferCard(
              from: s.memberById(t.fromId),
              to: s.memberById(t.toId),
              amount: t.amount,
              onPay: () => onPay(t),
            ),
          ),
        if (s.transfers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              'Đã rút gọn: ${s.members.length} người chỉ cần ${s.transfers.length} lượt chuyển.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        const SectionHeader('Số dư từng người'),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              for (final m in s.members)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    MemberAvatar(m.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(m.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            _BalanceBar(
                                value: s.balances[m.id] ?? 0, max: maxAbs),
                          ]),
                    ),
                    const SizedBox(width: 12),
                    SignedAmount(s.balances[m.id] ?? 0),
                  ]),
                ),
            ]),
          ),
        ),
        if (s.settlements.isNotEmpty) ...[
          SectionHeader('Lịch sử thanh toán',
              trailing: Text('Nhấn giữ để hoàn tác',
                  style: TextStyle(color: muted, fontSize: 11))),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final st in s.settlements)
                ListTile(
                  leading: const IconTile(
                      Icons.check_rounded, AppTheme.owed, size: 40),
                  title: Text(
                      '${s.memberById(st.fromId).name} → ${s.memberById(st.toId).name}'),
                  subtitle: Text(formatDateTime(st.paidAt)),
                  trailing: Text(formatVnd(st.amount),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  onLongPress: () => onUndo(st),
                ),
            ]),
          ),
        ],
      ],
    );
  }
}

class _TransferCard extends StatelessWidget {
  final Member from;
  final Member to;
  final int amount;
  final VoidCallback onPay;
  const _TransferCard({
    required this.from,
    required this.to,
    required this.amount,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          MemberAvatar(from.name, radius: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward_rounded,
                size: 18, color: scheme.onSurfaceVariant),
          ),
          MemberAvatar(to.name, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${from.name} trả ${to.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              Text(formatVnd(amount),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800)),
            ]),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            onPressed: onPay,
            icon: const Icon(Icons.qr_code_2, size: 18),
            label: const Text('Trả'),
          ),
        ]),
      ),
    );
  }
}

/// Thanh ngang thể hiện độ lớn số dư so với người lớn nhất.
class _BalanceBar extends StatelessWidget {
  final int value;
  final int max;
  const _BalanceBar({required this.value, required this.max});

  @override
  Widget build(BuildContext context) {
    final ratio = max == 0 ? 0.0 : value.abs() / max;
    final color = value >= 0 ? AppTheme.owed : AppTheme.owe;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: 6,
        color: color,
        backgroundColor: color.withValues(alpha: 0.12),
      ),
    );
  }
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        const SectionHeader('Thành viên'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, m) in summary.members.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 72),
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: MemberAvatar(m.name, radius: 22),
                title: Text(m.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(m.hasBank
                    ? '${findBankName(m.bankBin)} · ${m.accountNo}'
                    : 'Chưa có tài khoản nhận tiền'),
                trailing: m.hasBank
                    ? const Icon(Icons.verified_rounded, color: AppTheme.owed)
                    : const StatusPill('Thêm TK', Colors.orange),
                onTap: () => onOpen(m),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Thêm thành viên'),
        ),
      ],
    );
  }
}

String findBankName(String? bin) =>
    findBankByBin(App.banks, bin)?.shortName ?? bin ?? '';
