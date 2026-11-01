import 'dart:io';

import 'package:flutter/material.dart';

import '../logic/categories.dart';
import '../logic/money.dart';
import '../models/activity.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../services/app_services.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'expense_form_screen.dart';

/// Xem chi tiết một khoản chi: ai trả, mỗi người chịu bao nhiêu, ảnh hóa đơn.
/// Giống màn chi tiết khoản chi của Splitwise, có nút sửa và xóa.
class ExpenseDetailScreen extends StatefulWidget {
  final Group group;
  final int expenseId;
  const ExpenseDetailScreen(
      {super.key, required this.group, required this.expenseId});

  @override
  State<ExpenseDetailScreen> createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  Expense? _expense;
  List<Member> _members = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e = await App.expenses.getById(widget.expenseId);
    final members = await App.groups.members(widget.group.id!);
    if (!mounted) return;
    setState(() {
      _expense = e;
      _members = members;
      _loaded = true;
    });
  }

  Member? _member(int id) {
    for (final m in _members) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _edit() async {
    final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => ExpenseFormScreen(
                groupId: widget.group.id!, expense: _expense)));
    if (changed != true) return;
    // Form có thể đã xóa khoản chi.
    final e = await App.expenses.getById(widget.expenseId);
    if (!mounted) return;
    if (e == null) {
      Navigator.pop(context, true);
    } else {
      _load();
    }
  }

  Future<void> _delete() async {
    final e = _expense!;
    final ok = await confirm(context, 'Xóa khoản chi?',
        '"${e.title}" sẽ bị xóa, số dư được tính lại.',
        ok: 'Xóa');
    if (!ok) return;
    await App.expenses.delete(e.id!);
    await App.activities.log(
      groupId: widget.group.id,
      groupName: widget.group.name,
      kind: ActivityKind.expenseDeleted,
      message: 'Xóa khoản chi "${e.title}"',
      amount: e.amount,
    );
    if (mounted) Navigator.pop(context, true);
  }

  String _splitDetail(Expense e, int memberId) {
    final w = e.weights[memberId];
    return switch (e.splitType) {
      SplitType.shares when w != null => '$w phần',
      SplitType.percent when w != null => formatPercent(w),
      _ => '',
    };
  }

  void _openReceipt(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Ảnh hóa đơn',
                style: TextStyle(color: Colors.white)),
          ),
          body: Center(
            child: InteractiveViewer(child: Image.file(File(path))),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final e = _expense;
    if (e == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Khoản chi đã bị xóa')),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final category = e.effectiveCategory;
    final payer = _member(e.paidBy);
    final hasReceipt =
        e.receiptPath != null && File(e.receiptPath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết khoản chi'),
        actions: [
          IconButton(
              tooltip: 'Sửa', onPressed: _edit, icon: const Icon(Icons.edit)),
          IconButton(
              tooltip: 'Xóa',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                IconTile.forCategory(category, size: 64),
                const SizedBox(height: 12),
                Text(e.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(formatVnd(e.amount),
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    StatusPill(categoryLabels[category]!,
                        categoryStyle[category]!.$2),
                    StatusPill(SplitType.label(e.splitType), scheme.primary),
                    StatusPill(formatDate(e.date), muted),
                  ],
                ),
              ]),
            ),
          ),
          const SectionHeader('Người trả'),
          Card(
            child: ListTile(
              leading: MemberAvatar(payer?.name ?? '?', radius: 20),
              title: Text('${payer?.name ?? '?'} đã trả',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: Text(formatVnd(e.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppTheme.owed)),
            ),
          ),
          SectionHeader('Chia cho ${e.shares.length} người'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, entry) in e.shares.entries.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 72),
                Builder(builder: (context) {
                  final m = _member(entry.key);
                  final isPayer = entry.key == e.paidBy;
                  final detail = _splitDetail(e, entry.key);
                  return ListTile(
                    leading: MemberAvatar(m?.name ?? '?'),
                    title: Text(m?.name ?? '?'),
                    subtitle: Text(
                      isPayer
                          ? 'Phần của mình${detail.isEmpty ? '' : ' · $detail'}'
                          : 'Nợ ${payer?.name ?? '?'}${detail.isEmpty ? '' : ' · $detail'}',
                      style: TextStyle(color: muted),
                    ),
                    trailing: Text(formatVnd(entry.value),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isPayer ? muted : AppTheme.owe)),
                  );
                }),
              ],
            ]),
          ),
          if (e.note != null && e.note!.isNotEmpty) ...[
            const SectionHeader('Ghi chú'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Icon(Icons.notes_rounded, color: muted),
                  const SizedBox(width: 12),
                  Expanded(child: Text(e.note!)),
                ]),
              ),
            ),
          ],
          if (hasReceipt) ...[
            const SectionHeader('Ảnh hóa đơn'),
            GestureDetector(
              onTap: () => _openReceipt(e.receiptPath!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(File(e.receiptPath!),
                    height: 220, width: double.infinity, fit: BoxFit.cover),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
