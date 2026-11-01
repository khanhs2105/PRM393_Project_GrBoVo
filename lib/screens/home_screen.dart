import 'package:flutter/material.dart';

import '../data/group_summary.dart';
import '../logic/money.dart';
import '../logic/plans.dart';
import '../models/group.dart';
import '../services/app_services.dart';
import '../theme.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'account_screen.dart';
import 'group_detail_screen.dart';
import 'group_form_screen.dart';
import 'plans_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<(Group, GroupSummary)>> _future = _load();

  /// 0: tất cả, 1: còn nợ, 2: đã xong.
  int _filter = 0;

  Future<List<(Group, GroupSummary)>> _load() async {
    final groups = await App.groups.getAll();
    return [
      for (final g in groups) (g, await GroupSummary.load(App.db, g.id!)),
    ];
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _createGroup(int currentCount) async {
    if (!App.plan.value.canCreateGroup(currentCount)) {
      final go = await confirm(context, 'Hết chỗ rồi 😅', groupLimitMessage,
          ok: 'Xem các gói');
      if (go && mounted) {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => const PlansScreen()));
      }
      return;
    }
    final created = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const GroupFormScreen()));
    if (created == true) _reload();
  }

  Future<void> _openGroup(Group g) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: g.id!)));
    _reload();
  }

  /// "Chào buổi sáng, Huy 👋" khi đã có tên hiển thị.
  String _greet() {
    final name = App.auth?.currentUser?.displayName?.trim() ?? '';
    final g = greeting();
    return name.isEmpty ? g : g.replaceFirst(' 👋', ', $name 👋');
  }

  Future<void> _openAccount() async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const AccountScreen()));
    if (changed == true && mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<(Group, GroupSummary)>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data;
        final shown = items == null
            ? const <(Group, GroupSummary)>[]
            : [
                for (final e in items)
                  if (_filter == 0 ||
                      (_filter == 1 && e.$2.transfers.isNotEmpty) ||
                      (_filter == 2 && e.$2.transfers.isEmpty))
                    e,
              ];
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 68,
            titleSpacing: 16,
            title: Row(children: [
              Image.asset('assets/brand/chipin_logo.png',
                  width: 38, height: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_greet(),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurfaceVariant)),
                      const Text('Alo, Trả Tiền!',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4)),
                    ]),
              ),
            ]),
            actions: [
              IconButton(
                tooltip: 'Tài khoản',
                icon: const Icon(AppIcons.circleUser),
                onPressed: _openAccount,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: snap.hasError
              ? Center(child: Text('Lỗi: ${snap.error}'))
              : items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? EmptyState(
                          icon: AppIcons.users,
                          title: 'Chưa có nhóm nào',
                          message:
                              'Tạo nhóm cho phòng trọ, buổi đi ăn hay chuyến du lịch để bắt đầu chia tiền.',
                          actionLabel: 'Tạo nhóm đầu tiên',
                          onAction: () => _createGroup(0),
                        )
                      : RefreshIndicator(
                          onRefresh: () async => _reload(),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                            children: [
                              _SummaryCard(items: items),
                              const SizedBox(height: 16),
                              _Segmented(
                                labels: const ['Tất cả', 'Còn nợ', 'Đã xong'],
                                value: _filter,
                                onChanged: (v) => setState(() => _filter = v),
                              ),
                              const SizedBox(height: 12),
                              if (shown.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Text(
                                      _filter == 1
                                          ? 'Không nhóm nào còn nợ 🎉'
                                          : 'Chưa có nhóm nào trả xong.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: scheme.onSurfaceVariant)),
                                ),
                              for (final (g, s) in shown)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _GroupCard(
                                      group: g,
                                      summary: s,
                                      onTap: () => _openGroup(g)),
                                ),
                            ],
                          ),
                        ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _createGroup(items?.length ?? 0),
            icon: const Icon(AppIcons.plus),
            label: const Text('Tạo nhóm'),
          ),
        );
      },
    );
  }
}

/// Thẻ tóm tắt: tổng chi, số tiền còn phải trả, số nhóm đã xong.
class _SummaryCard extends StatelessWidget {
  final List<(Group, GroupSummary)> items;
  const _SummaryCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = items.fold<int>(0, (sum, e) => sum + e.$2.totalSpent);
    final remaining = items.fold<int>(
        0, (sum, e) => sum + e.$2.transfers.fold<int>(0, (a, t) => a + t.amount));
    final open = items.where((e) => e.$2.transfers.isNotEmpty).length;
    final done = items.length - open;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Tổng chi tiêu ${items.length} nhóm',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant)),
            ),
            Icon(AppIcons.wallet, size: 18, color: scheme.onSurfaceVariant),
          ]),
          const SizedBox(height: 4),
          Text(formatVnd(total),
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 14),
          Row(children: [
            _Tile(
              color: AppTheme.owe,
              label: 'Còn phải trả',
              value: formatVnd(remaining),
              sub: '$open nhóm',
            ),
            const SizedBox(width: 8),
            _Tile(
              color: AppTheme.owed,
              label: 'Đã trả xong',
              value: '$done nhóm',
              sub: done == items.length ? 'Sạch nợ 🎉' : 'trên ${items.length}',
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final String sub;
  const _Tile(
      {required this.color,
      required this.label,
      required this.value,
      required this.sub});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: dark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          Text(sub,
              style: TextStyle(
                  color: color.withValues(alpha: 0.8), fontSize: 11)),
        ]),
      ),
    );
  }
}

/// Bộ chọn dạng thanh chia đoạn, kiểu shadcn "Tabs".
class _Segmented extends StatelessWidget {
  final List<String> labels;
  final int value;
  final ValueChanged<int> onChanged;
  const _Segmented(
      {required this.labels, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: i == value ? scheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: i == value ? AppTheme.softShadow : null,
                ),
                child: Text(labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            i == value ? FontWeight.w600 : FontWeight.w500,
                        color: i == value
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Group group;
  final GroupSummary summary;
  final VoidCallback onTap;
  const _GroupCard(
      {required this.group, required this.summary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pending = summary.transfers.length;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            IconTile(groupTypeIcon(group.type), groupTypeColor(group.type),
                size: 46),
            const SizedBox(width: 12),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                    '${summary.members.length} người · ${summary.expenses.length} khoản chi',
                    style: TextStyle(color: muted, fontSize: 12.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatVnd(summary.totalSpent),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              pending == 0
                  ? const StatusPill('Đã xong', AppTheme.owed)
                  : StatusPill('Còn $pending lượt', AppTheme.owe),
            ]),
            const SizedBox(width: 4),
            Icon(AppIcons.chevronRight, size: 18, color: muted),
          ]),
        ),
      ),
    );
  }
}
