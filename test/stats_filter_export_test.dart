import 'package:chia_tien/logic/categories.dart';
import 'package:chia_tien/logic/expense_filter.dart';
import 'package:chia_tien/logic/export.dart';
import 'package:chia_tien/logic/stats.dart';
import 'package:chia_tien/models/expense.dart';
import 'package:chia_tien/models/member.dart';
import 'package:chia_tien/models/settlement.dart';
import 'package:flutter_test/flutter_test.dart';

const an = 1, binh = 2, chi = 3;

final members = [
  const Member(id: an, groupId: 1, name: 'An'),
  const Member(id: binh, groupId: 1, name: 'Bình'),
  const Member(id: chi, groupId: 1, name: 'Chi'),
];

final expenses = [
  Expense(
    id: 1,
    groupId: 1,
    title: 'Lẩu Thái',
    amount: 300000,
    paidBy: an,
    splitType: SplitType.equal,
    shares: {an: 100000, binh: 100000, chi: 100000},
    date: DateTime(2026, 10, 5),
  ),
  Expense(
    id: 2,
    groupId: 1,
    title: 'Tiền điện',
    amount: 400000,
    paidBy: binh,
    splitType: SplitType.shares,
    shares: {an: 200000, binh: 100000, chi: 100000},
    weights: {an: 2, binh: 1, chi: 1},
    date: DateTime(2026, 11, 1),
  ),
  Expense(
    id: 3,
    groupId: 1,
    title: 'Quà sinh nhật, "bí mật"',
    amount: 100000,
    paidBy: chi,
    splitType: SplitType.exact,
    shares: {an: 50000, binh: 50000},
    category: 'shopping',
    note: 'Mua ở Phúc Long',
    date: DateTime(2026, 11, 2),
  ),
];

void main() {
  test('danh mục: chọn tay thắng đoán tự động', () {
    expect(expenses[0].effectiveCategory, ExpenseCategory.food);
    expect(expenses[2].effectiveCategory, ExpenseCategory.shopping);
    expect(categoryFromName('rent'), ExpenseCategory.rent);
    expect(categoryFromName('lạ'), isNull);
    expect(categoryLabels.length, ExpenseCategory.values.length);
  });

  group('thống kê', () {
    test('theo danh mục, nhiều nhất trước', () {
      final r = totalsByCategory(expenses);
      expect(r.map((c) => c.category), [
        ExpenseCategory.utilities,
        ExpenseCategory.food,
        ExpenseCategory.shopping,
      ]);
      expect(r.first.amount, 400000);
      expect(r.first.count, 1);
    });

    test('theo người: đã trả và đã tiêu', () {
      final r = spendingByMember(expenses, memberIds: [an, binh, chi]);
      expect(r[an]!.paid, 300000);
      expect(r[an]!.consumed, 350000);
      expect(r[binh]!.paid, 400000);
      expect(r[binh]!.consumed, 250000);
      expect(r[chi]!.paid, 100000);
      expect(r[chi]!.consumed, 200000);
    });

    test('theo tháng, cũ trước', () {
      final r = totalsByMonth(expenses);
      expect(r.keys.toList(), [DateTime(2026, 10), DateTime(2026, 11)]);
      expect(r.values.toList(), [300000, 500000]);
    });
  });

  group('lọc khoản chi', () {
    test('tìm không dấu trong nội dung và ghi chú', () {
      expect(filterExpenses(expenses, query: 'lau').map((e) => e.id), [1]);
      expect(filterExpenses(expenses, query: 'ĐIỆN').map((e) => e.id), [2]);
      expect(filterExpenses(expenses, query: 'phuc long').map((e) => e.id), [3]);
      expect(filterExpenses(expenses).length, 3);
    });

    test('theo danh mục và theo người', () {
      expect(
          filterExpenses(expenses, category: ExpenseCategory.food)
              .map((e) => e.id),
          [1]);
      // Chi không có phần trong khoản 3 nhưng là người trả.
      expect(filterExpenses(expenses, memberId: chi).map((e) => e.id),
          [1, 2, 3]);
      expect(
          filterExpenses(expenses, memberId: an, query: 'qua').map((e) => e.id),
          [3]);
    });
  });

  group('xuất dữ liệu', () {
    test('csvCell bọc ô có dấu phẩy và ngoặc kép', () {
      expect(csvCell('abc'), 'abc');
      expect(csvCell('a,b'), '"a,b"');
      expect(csvCell('say "hi"'), '"say ""hi"""');
      expect(csvCell(null), '');
      expect(csvCell(1500), '1500');
    });

    test('CSV có cột từng người, dòng tổng và bảng thanh toán', () {
      final csv = groupCsv(
        members: members,
        expenses: expenses,
        settlements: [
          Settlement(
            groupId: 1,
            fromId: chi,
            toId: binh,
            amount: 50000,
            paidAt: DateTime(2026, 11, 3),
            note: 'tiền mặt',
          ),
        ],
      );
      final lines = csv.trim().split('\r\n');
      expect(lines.first,
          'Ngày,Nội dung,Danh mục,Số tiền,Người trả,Cách chia,An,Bình,Chi,Ghi chú');
      expect(lines[1],
          '05/10/2026,Lẩu Thái,Ăn uống,300000,An,Chia đều,100000,100000,100000,');
      expect(lines[3], startsWith('02/11/2026,"Quà sinh nhật, ""bí mật""",'));
      expect(lines[4], ',Tổng,,800000,,,350000,250000,200000,');
      expect(lines.last, '03/11/2026,Chi,Bình,50000,tiền mặt');
    });

    test('tóm tắt nhóm', () {
      final text = groupSummaryText(
        groupName: 'Phòng 302',
        members: members,
        expenses: expenses,
        balances: {an: -50000, binh: 150000, chi: -100000},
        transfers: const [Transfer(chi, binh, 100000), Transfer(an, binh, 50000)],
      );
      expect(text, contains('Tổng chi: 800.000 ₫ (3 khoản)'));
      expect(text, contains('• Bình: được nhận 150.000 ₫'));
      expect(text, contains('• An: cần trả 50.000 ₫'));
      expect(text, contains('• Chi → Bình: 100.000 ₫'));
    });
  });
}
