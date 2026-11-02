import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/group_summary.dart';
import '../logic/categories.dart';
import '../logic/expense_filter.dart';
import '../logic/export.dart';
import '../logic/money.dart';
import '../logic/plans.dart';
import '../logic/vietqr.dart';
import '../models/activity.dart';
import '../models/bank.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/settlement.dart';
import '../services/app_services.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/pro_prompts.dart';
import '../widgets/shake_picker.dart';
import '../widgets/ui.dart';
import 'activity_screen.dart';
import 'expense_detail_screen.dart';
import 'expense_form_screen.dart';
import 'group_form_screen.dart';
import 'member_form_screen.dart';
import 'payment_screen.dart';
import 'record_payment_screen.dart';
import 'stats_screen.dart';
import '../widgets/app_icons.dart';

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

  /// Mở màn thêm khoản chi / trả tiền. Có kết quả thì có thể đề nghị dùng
  /// thử Pro (sau bill đầu tiên) hoặc hiện quảng cáo ở bản Free.
  Future<void> _openForResult(Widget screen) async {
    final done = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => screen));
    _reload();
    if (done != true) return;
    final (_, s) = await _future;
    if (!mounted) return;
    await afterResult(context,
        memberCount: s.members.length, expenseCount: s.expenses.length);
  }

  /// Nhân bản nhóm cho chuyến sau: giữ thành viên, bỏ khoản chi.
  Future<void> _duplicateGroup(Group g) async {
    final controller = TextEditingController(text: '${g.name} (lần sau)');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhân bản nhóm'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Nhóm mới có đủ thành viên và tài khoản ngân hàng, '
              'chưa có khoản chi nào. Khỏi phải mời lại từ đầu.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tên nhóm mới'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Tạo nhóm'),
          ),
        ],
      ),
    );
    if (name == null) return;
    final id = await App.groups.duplicate(g.id!, name);
    await App.activities.log(
      groupId: id,
      groupName: name,
      kind: ActivityKind.groupCreated,
      message: 'Tạo nhóm "$name" từ nhóm "${g.name}"',
    );
    if (!mounted) return;
    showSnack(context, 'Đã tạo nhóm "$name"');
    await Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: id)));
  }

  Future<void> _deleteGroup(Group g) async {
    final ok = await confirm(context, 'Xóa nhóm "${g.name}"?',
        'Toàn bộ khoản chi và lịch sử trả tiền của nhóm sẽ bị xóa.',
        ok: 'Xóa');
    if (!ok) return;
    await App.groups.delete(g.id!);
    await App.activities.log(
      groupId: null,
      groupName: g.name,
      kind: ActivityKind.groupDeleted,
      message: 'Xóa nhóm "${g.name}"',
    );
    if (mounted) Navigator.pop(context);
  }

  /// Gửi bản tóm tắt số dư vào Zalo/Messenger.
  Future<void> _shareSummary(Group g, GroupSummary s) async {
    await SharePlus.instance.share(ShareParams(
      text: groupSummaryText(
        groupName: g.name,
        members: s.members,
        expenses: s.expenses,
        balances: s.balances,
        transfers: s.transfers,
      ),
    ));
  }

  /// Xuất file CSV (mở được bằng Excel, Google Sheets) rồi chia sẻ.
  Future<void> _exportCsv(Group g, GroupSummary s) async {
    if (!App.plan.value.canExportReport) {
      final ok = await showProUpsell(context,
          title: 'Gửi bảng tổng kết cho cả nhóm',
          message: 'Xuất báo cáo CSV (mở bằng Excel) là tính năng Pro. '
              'Chia sẻ tóm tắt bằng chữ vẫn miễn phí.');
      if (!ok || !mounted) return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final safeName = removeDiacritics(g.name)
          .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
          .toLowerCase();
      final file = File(p.join(dir.path, 'chipin_$safeName.csv'));
      // BOM để Excel đọc đúng tiếng Việt.
      final csv = groupCsv(
        members: s.members,
        expenses: s.expenses,
        settlements: s.settlements,
      );
      await file.writeAsString('\uFEFF$csv');
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Alo, Trả Tiền! - ${g.name}',
      ));
    } catch (e) {
      if (mounted) showSnack(context, 'Không xuất được file: $e');
    }
  }

  Future<void> _undoSettlement(Group g, GroupSummary s, Settlement st) async {
    final ok = await confirm(context, 'Hoàn tác?',
        'Xóa lần trả ${formatVnd(st.amount)} này khỏi lịch sử.',
        ok: 'Xóa');
    if (!ok) return;
    await App.settlements.delete(st.id!);
    await App.activities.log(
      groupId: g.id,
      groupName: g.name,
      kind: ActivityKind.settleUndone,
      message:
          'Hoàn tác: ${s.memberById(st.fromId).name} trả ${s.memberById(st.toId).name}',
      amount: st.amount,
    );
    _reload();
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
                    icon: const Icon(AppIcons.dices),
                    onPressed: () => showShakePicker(context, s.members, plan),
                  ),
                ),
                IconButton(
                  tooltip: 'Thống kê',
                  icon: const Icon(AppIcons.chartPie),
                  onPressed: () =>
                      _open(StatsScreen(group: group, summary: s)),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'activity':
                        _open(ActivityScreen(
                            groupId: group.id, groupName: group.name));
                      case 'share':
                        _shareSummary(group, s);
                      case 'csv':
                        _exportCsv(group, s);
                      case 'duplicate':
                        _duplicateGroup(group);
                      case 'edit':
                        _open(GroupFormScreen(group: group));
                      case 'delete':
                        _deleteGroup(group);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'activity',
                        child: ListTile(
                            leading: Icon(AppIcons.history),
                            title: Text('Lịch sử hoạt động'))),
                    PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                            leading: Icon(AppIcons.share),
                            title: Text('Chia sẻ tóm tắt'))),
                    PopupMenuItem(
                        value: 'csv',
                        child: ListTile(
                            leading: Icon(AppIcons.sheet),
                            title: Text('Xuất file CSV'))),
                    PopupMenuItem(
                        value: 'duplicate',
                        child: ListTile(
                            leading: Icon(AppIcons.copy),
                            title: Text('Nhân bản nhóm'))),
                    PopupMenuDivider(),
                    PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                            leading: Icon(AppIcons.pencil),
                            title: Text('Sửa nhóm'))),
                    PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                            leading: Icon(AppIcons.trash2),
                            title: Text('Xóa nhóm'))),
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
                    onOpen: (e) => _open(
                        ExpenseDetailScreen(group: group, expenseId: e.id!)),
                    onAdd: () =>
                        _openForResult(ExpenseFormScreen(groupId: group.id!)),
                  ),
                  _BalancesTab(
                    summary: s,
                    onPay: (t) =>
                        _openForResult(PaymentScreen(group: group, transfer: t)),
                    onRecord: () => _openForResult(RecordPaymentScreen(
                        group: group,
                        members: s.members,
                        transfers: s.transfers)),
                    onUndo: (st) => _undoSettlement(group, s, st),
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
              onPressed: () =>
                  _openForResult(ExpenseFormScreen(groupId: group.id!)),
              icon: const Icon(AppIcons.plus),
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
    final muted = Colors.white.withValues(alpha: 0.85);
    return GradientPanel(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(groupTypeIcon(group.type), size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tổng chi', style: TextStyle(color: muted, fontSize: 13)),
            Text(formatVnd(s.totalSpent),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800)),
            Text('Trung bình ${formatVnd(perPerson)}/người',
                style: TextStyle(color: muted, fontSize: 13)),
          ]),
        ),
        AvatarStack(s.members.map((m) => m.name).toList(), max: 3),
      ]),
    );
  }
}

class _ExpensesTab extends StatefulWidget {
  final GroupSummary summary;
  final void Function(Expense) onOpen;
  final VoidCallback onAdd;
  const _ExpensesTab(
      {required this.summary, required this.onOpen, required this.onAdd});

  @override
  State<_ExpensesTab> createState() => _ExpensesTabState();
}

class _ExpensesTabState extends State<_ExpensesTab> {
  final _search = TextEditingController();
  ExpenseCategory? _category;
  int? _memberId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _filtering =>
      _search.text.trim().isNotEmpty || _category != null || _memberId != null;

  void _clear() => setState(() {
        _search.clear();
        _category = null;
        _memberId = null;
      });

  /// Hàng chip lọc: theo người và theo danh mục đang có trong nhóm.
  Widget _filters(GroupSummary s) {
    final used = {for (final e in s.expenses) e.effectiveCategory};
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final m in s.members)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: MemberAvatar(m.name, radius: 10),
                label: Text(m.name),
                selected: _memberId == m.id,
                showCheckmark: false,
                onSelected: (v) => setState(() => _memberId = v ? m.id : null),
              ),
            ),
          for (final c in ExpenseCategory.values)
            if (used.contains(c))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: Icon(categoryStyle[c]!.$1,
                      size: 16, color: categoryStyle[c]!.$2),
                  label: Text(categoryLabels[c]!),
                  selected: _category == c,
                  showCheckmark: false,
                  onSelected: (v) => setState(() => _category = v ? c : null),
                ),
              ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    if (s.expenses.isEmpty) {
      return EmptyState(
        icon: AppIcons.receipt,
        title: 'Chưa có khoản chi',
        message: 'Thêm bữa ăn, tiền phòng hay tiền điện đầu tiên của nhóm.',
        actionLabel: 'Thêm khoản chi',
        onAction: widget.onAdd,
      );
    }
    final shown = filterExpenses(
      s.expenses,
      query: _search.text,
      category: _category,
      memberId: _memberId,
    );
    // Gom khoản chi theo ngày, danh sách đã sắp mới nhất trước.
    final byDay = <String, List<Expense>>{};
    for (final e in shown) {
      byDay.putIfAbsent(dayLabel(e.date), () => []).add(e);
    }
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(AppIcons.search),
              hintText: 'Tìm khoản chi, ghi chú...',
              suffixIcon: _filtering
                  ? IconButton(
                      tooltip: 'Bỏ lọc',
                      onPressed: _clear,
                      icon: const Icon(AppIcons.x))
                  : null,
            ),
          ),
        ),
        _filters(s),
        if (_filtering)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Tìm thấy ${shown.length} khoản · '
              '${formatVnd(shown.fold(0, (sum, e) => sum + e.amount))}',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Không có khoản chi nào khớp.',
                textAlign: TextAlign.center, style: TextStyle(color: muted)),
          ),
        for (final entry in byDay.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: e.receiptPath != null &&
                              File(e.receiptPath!).existsSync()
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: Image.file(File(e.receiptPath!),
                                  width: 44, height: 44, fit: BoxFit.cover),
                            )
                          : IconTile.forCategory(e.effectiveCategory),
                      title: Text(e.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${s.memberById(e.paidBy).name} đã trả · '
                          '${e.splitType == SplitType.equal ? 'chia đều' : SplitType.label(e.splitType).toLowerCase()} '
                          '${e.shares.length} người'),
                      trailing: Text(formatVnd(e.amount),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      onTap: () => widget.onOpen(e),
                    ),
                  ],
                ]),
              ),
            ]),
          ),
      ],
    );
  }
}

class _BalancesTab extends StatelessWidget {
  final GroupSummary summary;
  final void Function(Transfer) onPay;
  final VoidCallback onRecord;
  final void Function(Settlement) onUndo;
  const _BalancesTab({
    required this.summary,
    required this.onPay,
    required this.onRecord,
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onRecord,
          icon: const Icon(AppIcons.banknote),
          label: const Text('Ghi nhận thanh toán khác'),
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
                      AppIcons.check, AppTheme.owed, size: 40),
                  title: Text(
                      '${s.memberById(st.fromId).name} → ${s.memberById(st.toId).name}'),
                  subtitle: Text(st.note == null
                      ? formatDateTime(st.paidAt)
                      : '${formatDateTime(st.paidAt)} · ${st.note}'),
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
            child: Icon(AppIcons.arrowRight,
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
            icon: const Icon(AppIcons.qrCode, size: 18),
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
                    ? const Icon(AppIcons.badgeCheck, color: AppTheme.owed)
                    : const StatusPill('Thêm TK', Colors.orange),
                onTap: () => onOpen(m),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(AppIcons.userPlus),
          label: const Text('Thêm thành viên'),
        ),
      ],
    );
  }
}

String findBankName(String? bin) =>
    findBankByBin(App.banks, bin)?.shortName ?? bin ?? '';
