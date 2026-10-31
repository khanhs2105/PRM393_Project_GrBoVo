import 'package:flutter/material.dart';

import '../data/group_summary.dart';
import '../logic/money.dart';
import '../logic/plans.dart';
import '../models/group.dart';
import '../services/app_services.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'activity_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<(Group, GroupSummary)>>(
      future: _future,
      builder: (context, snap) {
        final items = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/brand/chipin_logo.png',
                    width: 30, height: 30),
                const SizedBox(width: 10),
                const Text('Chipin',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Hoạt động',
                icon: const Icon(Icons.history_rounded),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ActivityScreen())),
              ),
              ValueListenableBuilder<Plan>(
                valueListenable: App.plan,
                builder: (context, plan, _) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ActionChip(
                    avatar: const Icon(Icons.workspace_premium, size: 18),
                    label: Text(plan.title),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const PlansScreen())),
                  ),
                ),
              ),
            ],
          ),
          body: snap.hasError
              ? Center(child: Text('Lỗi: ${snap.error}'))
              : items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? EmptyState(
                          icon: Icons.groups_rounded,
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
                              const SectionHeader('Nhóm của bạn'),
                              for (final (g, s) in items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
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
            icon: const Icon(Icons.add),
            label: const Text('Tạo nhóm'),
          ),
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<(Group, GroupSummary)> items;
  const _SummaryCard({required this.items});

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (sum, e) => sum + e.$2.totalSpent);
    final pending = items.fold<int>(0, (sum, e) => sum + e.$2.transfers.length);
    final open = items.where((e) => e.$2.transfers.isNotEmpty).length;
    const white = Colors.white;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1CC29F), Color(0xFF0E8F74)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.seed.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Tổng chi tiêu các nhóm',
            style: TextStyle(color: white.withValues(alpha: 0.85))),
        const SizedBox(height: 6),
        Text(formatVnd(total),
            style: const TextStyle(
                color: white, fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        Row(children: [
          _Stat(label: 'Nhóm', value: '${items.length}'),
          _Stat(label: 'Nhóm còn nợ', value: '$open'),
          _Stat(label: 'Lượt cần trả', value: '$pending'),
        ]),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
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
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            IconTile(groupTypeIcon(group.type), groupTypeColor(group.type),
                size: 52),
            const SizedBox(width: 14),
            Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                    '${groupTypeLabel(group.type)} · ${summary.expenses.length} khoản chi',
                    style: TextStyle(color: muted, fontSize: 13)),
                const SizedBox(height: 8),
                AvatarStack(summary.members.map((m) => m.name).toList()),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatVnd(summary.totalSpent),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              pending == 0
                  ? const StatusPill('Đã xong', AppTheme.owed)
                  : StatusPill('Còn $pending lượt', AppTheme.owe),
            ]),
          ]),
        ),
      ),
    );
  }
}
