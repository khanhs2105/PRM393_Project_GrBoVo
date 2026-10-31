import 'package:chia_tien/logic/balances.dart';
import 'package:chia_tien/logic/debt_simplifier.dart';
import 'package:chia_tien/logic/money.dart';
import 'package:chia_tien/models/expense.dart';
import 'package:chia_tien/models/settlement.dart';
import 'package:flutter_test/flutter_test.dart';

const an = 1, binh = 2, chi = 3, dung = 4;

Expense exp(int paidBy, int amount, List<int> members) => Expense(
      groupId: 1,
      title: 'test',
      amount: amount,
      paidBy: paidBy,
      splitType: 'equal',
      shares: splitEqual(amount, members, remainderTo: paidBy),
      date: DateTime(2026, 11, 1),
    );

/// Áp dụng các lượt chuyển vào số dư, kết quả phải về 0 hết.
Map<int, int> apply(Map<int, int> balances, List<Transfer> transfers) {
  final b = Map.of(balances);
  for (final t in transfers) {
    b[t.fromId] = b[t.fromId]! + t.amount;
    b[t.toId] = b[t.toId]! - t.amount;
  }
  return b;
}

void main() {
  test('ví dụ trong kế hoạch: An trả 300k, Bình trả 90k, chia 3', () {
    final balances = computeBalances([
      exp(an, 300000, [an, binh, chi]),
      exp(binh, 90000, [an, binh, chi]),
    ], []);
    expect(balances, {an: 170000, binh: -40000, chi: -130000});

    final transfers = simplifyDebts(balances);
    expect(transfers, [
      const Transfer(chi, an, 130000),
      const Transfer(binh, an, 40000),
    ]);
  });

  test('tổng số dư luôn bằng 0, kể cả khi chia có phần lẻ', () {
    final balances = computeBalances([
      exp(an, 100000, [an, binh, chi]),
      exp(chi, 77777, [an, binh, chi, dung]),
      exp(dung, 50001, [binh, dung]),
    ], []);
    expect(balances.values.reduce((a, b) => a + b), 0);
  });

  test('vòng tròn nợ triệt tiêu nhau thì không cần chuyển', () {
    // An trả cho Bình, Bình trả cho Chi, Chi trả cho An, cùng số tiền.
    final balances = computeBalances([
      exp(an, 100000, [binh]),
      exp(binh, 100000, [chi]),
      exp(chi, 100000, [an]),
    ], []);
    expect(simplifyDebts(balances), isEmpty);
  });

  test('n người thì tối đa n - 1 lượt chuyển và trả xong hết', () {
    final balances = computeBalances([
      exp(an, 480000, [an, binh, chi, dung]),
      exp(binh, 120000, [an, binh, chi, dung]),
      exp(chi, 35000, [an, chi]),
      exp(dung, 999999, [an, binh, chi, dung]),
    ], []);
    final transfers = simplifyDebts(balances);
    expect(transfers.length, lessThanOrEqualTo(3));
    expect(transfers.every((t) => t.amount > 0), isTrue);
    expect(apply(balances, transfers).values.every((v) => v == 0), isTrue);
  });

  test('sau khi trả tiền thì số dư giảm tương ứng', () {
    final expenses = [
      exp(an, 300000, [an, binh, chi]),
    ];
    final paid = [
      Settlement(
        groupId: 1,
        fromId: binh,
        toId: an,
        amount: 100000,
        paidAt: DateTime(2026, 11, 2),
      ),
    ];
    final balances = computeBalances(expenses, paid);
    expect(balances, {an: 100000, binh: 0, chi: -100000});
    expect(simplifyDebts(balances), [const Transfer(chi, an, 100000)]);
  });

  test('thành viên chưa có khoản nào vẫn có số dư 0', () {
    final balances = computeBalances([], [], memberIds: [an, binh]);
    expect(balances, {an: 0, binh: 0});
    expect(simplifyDebts(balances), isEmpty);
  });

  test('tổng khác 0 thì báo lỗi', () {
    expect(() => simplifyDebts({an: 10, binh: -5}), throwsArgumentError);
  });
}
