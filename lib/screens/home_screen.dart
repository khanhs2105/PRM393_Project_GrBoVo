import 'package:flutter/material.dart';

import '../data/group_summary.dart';
import '../logic/money.dart';
import '../logic/plans.dart';
import '../models/group.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GrBoVo Split'),
        actions: [
          ValueListenableBuilder<Plan>(
            valueListenable: App.plan,
            builder: (context, plan, _) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.workspace_premium_outlined, size: 18),
                label: Text(plan.title),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PlansScreen())),
              ),
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<(Group, GroupSummary)>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Lỗi: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Chưa có nhóm nào.\nBấm "Tạo nhóm" để bắt đầu chia tiền.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final (group, summary) = items[i];
                final pending = summary.transfers.length;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    leading: CircleAvatar(child: Icon(groupTypeIcon(group.type))),
                    title: Text(group.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${summary.members.length} người · '
                      'đã chi ${formatVnd(summary.totalSpent)}\n'
                      '${pending == 0 ? 'Không ai nợ ai 🎉' : '$pending khoản cần thanh toán'}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                GroupDetailScreen(groupId: group.id!)),
                      );
                      _reload();
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FutureBuilder<List<(Group, GroupSummary)>>(
        future: _future,
        builder: (context, snap) => FloatingActionButton.extended(
          onPressed: () => _createGroup(snap.data?.length ?? 0),
          icon: const Icon(Icons.group_add),
          label: const Text('Tạo nhóm'),
        ),
      ),
    );
  }
}
