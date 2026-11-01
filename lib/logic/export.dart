/// Xuất dữ liệu nhóm: file CSV mở bằng Excel/Google Sheets, và bản tóm tắt
/// dạng chữ để gửi vào nhóm chat.
library;

import '../models/expense.dart';
import '../models/member.dart';
import '../models/settlement.dart';
import 'categories.dart';
import 'money.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Bọc ô CSV trong ngoặc kép khi cần (có dấu phẩy, ngoặc kép, xuống dòng).
String csvCell(Object? value) {
  final s = value?.toString() ?? '';
  if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

String _row(List<Object?> cells) => cells.map(csvCell).join(',');

/// CSV gồm bảng khoản chi (mỗi người một cột phần phải chịu) và bảng các lần
/// trả tiền. Số tiền ghi dạng số nguyên để Excel cộng được.
String groupCsv({
  required List<Member> members,
  required List<Expense> expenses,
  required List<Settlement> settlements,
}) {
  String name(int id) => members
      .firstWhere((m) => m.id == id,
          orElse: () => Member(groupId: 0, name: '#$id'))
      .name;

  final lines = <String>[
    _row([
      'Ngày',
      'Nội dung',
      'Danh mục',
      'Số tiền',
      'Người trả',
      'Cách chia',
      for (final m in members) m.name,
      'Ghi chú',
    ]),
  ];
  // Cũ trước, giống sổ chi tiêu.
  final sorted = [...expenses]..sort((a, b) => a.date.compareTo(b.date));
  for (final e in sorted) {
    lines.add(_row([
      _date(e.date),
      e.title,
      categoryLabels[e.effectiveCategory],
      e.amount,
      name(e.paidBy),
      SplitType.label(e.splitType),
      for (final m in members) e.shares[m.id] ?? 0,
      e.note,
    ]));
  }
  lines.add(_row([
    '',
    'Tổng',
    '',
    expenses.fold<int>(0, (s, e) => s + e.amount),
    '',
    '',
    for (final m in members)
      expenses.fold<int>(0, (s, e) => s + (e.shares[m.id] ?? 0)),
    '',
  ]));

  if (settlements.isNotEmpty) {
    lines
      ..add('')
      ..add(_row(['Ngày', 'Người trả', 'Người nhận', 'Số tiền', 'Ghi chú']));
    final paid = [...settlements]..sort((a, b) => a.paidAt.compareTo(b.paidAt));
    for (final s in paid) {
      lines.add(_row(
          [_date(s.paidAt), name(s.fromId), name(s.toId), s.amount, s.note]));
    }
  }
  return '${lines.join('\r\n')}\r\n';
}

/// Tin nhắn tóm tắt nhóm: tổng chi, số dư từng người, ai cần trả ai.
String groupSummaryText({
  required String groupName,
  required List<Member> members,
  required List<Expense> expenses,
  required Map<int, int> balances,
  required List<Transfer> transfers,
}) {
  String name(int id) => members.firstWhere((m) => m.id == id).name;
  final total = expenses.fold<int>(0, (s, e) => s + e.amount);
  final b = StringBuffer()
    ..writeln('📒 $groupName')
    ..writeln('Tổng chi: ${formatVnd(total)} (${expenses.length} khoản)')
    ..writeln()
    ..writeln('Số dư:');
  for (final m in members) {
    final v = balances[m.id] ?? 0;
    final state = v > 0
        ? 'được nhận ${formatVnd(v)}'
        : v < 0
            ? 'cần trả ${formatVnd(-v)}'
            : 'đã sòng phẳng';
    b.writeln('• ${m.name}: $state');
  }
  b.writeln();
  if (transfers.isEmpty) {
    b.writeln('Không ai nợ ai 🎉');
  } else {
    b.writeln('Cần chuyển:');
    for (final t in transfers) {
      b.writeln('• ${name(t.fromId)} → ${name(t.toId)}: ${formatVnd(t.amount)}');
    }
  }
  b.write('\nGửi từ Chipin');
  return b.toString();
}
