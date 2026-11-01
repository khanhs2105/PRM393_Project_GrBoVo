import 'package:flutter/material.dart';

import '../logic/money.dart';
import '../models/activity.dart';
import '../services/app_services.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../widgets/app_icons.dart';

/// Lịch sử hoạt động, giống tab "Activity" của Splitwise.
/// [groupId] null: mọi nhóm (mở từ màn chính).
class ActivityScreen extends StatelessWidget {
  final int? groupId;
  final String? groupName;
  const ActivityScreen({super.key, this.groupId, this.groupName});

  static (IconData, Color) _style(String kind) => switch (kind) {
        ActivityKind.expenseAdded => (AppIcons.plus, AppTheme.seed),
        ActivityKind.expenseEdited => (AppIcons.pencil, Colors.blue),
        ActivityKind.expenseDeleted ||
        ActivityKind.memberDeleted ||
        ActivityKind.groupDeleted =>
          (AppIcons.trash2, AppTheme.owe),
        ActivityKind.settled => (AppIcons.check, AppTheme.owed),
        ActivityKind.settleUndone => (AppIcons.undo2, Colors.orange),
        ActivityKind.memberAdded ||
        ActivityKind.memberEdited =>
          (AppIcons.user, Colors.indigo),
        _ => (AppIcons.users, Colors.blueGrey),
      };

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
          title: Text(groupName == null ? 'Hoạt động' : 'Hoạt động · $groupName')),
      body: FutureBuilder<List<Activity>>(
        future: App.activities.recent(groupId: groupId),
        builder: (context, snap) {
          final items = snap.data;
          if (items == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (items.isEmpty) {
            return const EmptyState(
              icon: AppIcons.history,
              title: 'Chưa có hoạt động',
              message:
                  'Mỗi lần thêm, sửa, xóa khoản chi hay trả tiền sẽ được ghi lại ở đây.',
            );
          }
          final byDay = <String, List<Activity>>{};
          for (final a in items) {
            byDay.putIfAbsent(dayLabel(a.createdAt), () => []).add(a);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              for (final entry in byDay.entries) ...[
                SectionHeader(entry.key),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final (i, a) in entry.value.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 68),
                      Builder(builder: (context) {
                        final (icon, color) = _style(a.kind);
                        final time =
                            '${a.createdAt.hour.toString().padLeft(2, '0')}:${a.createdAt.minute.toString().padLeft(2, '0')}';
                        return ListTile(
                          leading: IconTile(icon, color, size: 40),
                          title: Text(a.message),
                          subtitle: Text(
                              groupId == null ? '${a.groupName} · $time' : time,
                              style: TextStyle(color: muted, fontSize: 12)),
                          trailing: a.amount == null
                              ? null
                              : Text(formatVnd(a.amount!),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                        );
                      }),
                    ],
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
