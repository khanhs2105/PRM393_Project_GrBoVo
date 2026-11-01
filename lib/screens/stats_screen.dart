import 'package:flutter/material.dart';

import '../data/group_summary.dart';
import '../logic/categories.dart';
import '../logic/money.dart';
import '../logic/stats.dart';
import '../models/group.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

/// Thống kê chi tiêu của nhóm: theo danh mục, theo người, theo tháng.
class StatsScreen extends StatelessWidget {
  final Group group;
  final GroupSummary summary;
  const StatsScreen({super.key, required this.group, required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final total = s.totalSpent;
    final byCategory = totalsByCategory(s.expenses);
    final byMember =
        spendingByMember(s.expenses, memberIds: s.members.map((m) => m.id!));
    final byMonth = totalsByMonth(s.expenses);
    final maxMember = byMember.values.fold<int>(
        0,
        (m, v) => [m, v.paid, v.consumed]
            .reduce((a, b) => a > b ? a : b));
    final maxMonth = byMonth.values.fold<int>(0, (m, v) => v > m ? v : m);

    return Scaffold(
      appBar: AppBar(title: Text('Thống kê · ${group.name}')),
      body: s.expenses.isEmpty
          ? const EmptyState(
              icon: Icons.insights_rounded,
              title: 'Chưa có số liệu',
              message: 'Thêm khoản chi để xem nhóm tiêu vào đâu nhiều nhất.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      _Number('Tổng chi', formatVnd(total)),
                      _Number('Số khoản', '${s.expenses.length}'),
                      _Number('TB/người',
                          formatVnd(s.members.isEmpty ? 0 : total ~/ s.members.length)),
                    ]),
                  ),
                ),
                const SectionHeader('Theo danh mục'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      for (final c in byCategory)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Row(children: [
                            IconTile.forCategory(c.category, size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                      child: Text(categoryLabels[c.category]!,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    Text(formatVnd(c.amount),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                  ]),
                                  const SizedBox(height: 6),
                                  _Bar(
                                      ratio: total == 0 ? 0 : c.amount / total,
                                      color: categoryStyle[c.category]!.$2),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${c.count} khoản · ${(c.amount * 100 / total).toStringAsFixed(1)}%',
                                      style: TextStyle(
                                          color: muted, fontSize: 12)),
                                ],
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
                SectionHeader('Theo người',
                    trailing: Text('Đã trả / Đã tiêu',
                        style: TextStyle(color: muted, fontSize: 11))),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      for (final m in s.members)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
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
                                  _LabeledBar(
                                    label: 'Trả',
                                    value: byMember[m.id]?.paid ?? 0,
                                    max: maxMember,
                                    color: AppTheme.owed,
                                  ),
                                  const SizedBox(height: 4),
                                  _LabeledBar(
                                    label: 'Tiêu',
                                    value: byMember[m.id]?.consumed ?? 0,
                                    max: maxMember,
                                    color: AppTheme.owe,
                                  ),
                                ],
                              ),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
                if (byMonth.length > 1) ...[
                  const SectionHeader('Theo tháng'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(children: [
                        for (final entry in byMonth.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            child: _LabeledBar(
                              label:
                                  '${entry.key.month.toString().padLeft(2, '0')}/${entry.key.year}',
                              value: entry.value,
                              max: maxMonth,
                              color: scheme.primary,
                              labelWidth: 64,
                            ),
                          ),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _Number extends StatelessWidget {
  final String label;
  final String value;
  const _Number(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12)),
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final double ratio;
  final Color color;
  const _Bar({required this.ratio, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: ratio.clamp(0.0, 1.0),
        minHeight: 8,
        color: color,
        backgroundColor: color.withValues(alpha: 0.12),
      ),
    );
  }
}

class _LabeledBar extends StatelessWidget {
  final String label;
  final int value;
  final int max;
  final Color color;
  final double labelWidth;
  const _LabeledBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    this.labelWidth = 34,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(children: [
      SizedBox(
          width: labelWidth,
          child: Text(label, style: TextStyle(color: muted, fontSize: 12))),
      Expanded(child: _Bar(ratio: max == 0 ? 0 : value / max, color: color)),
      const SizedBox(width: 8),
      SizedBox(
        width: 96,
        child: Text(formatVnd(value),
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    ]);
  }
}
