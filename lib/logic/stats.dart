/// Số liệu cho màn Thống kê: chi theo danh mục, theo người, theo tháng.
library;

import '../models/expense.dart';
import 'categories.dart';

class CategoryTotal {
  final ExpenseCategory category;
  final int amount;
  final int count;
  const CategoryTotal(this.category, this.amount, this.count);
}

/// Tổng tiền mỗi danh mục, nhiều nhất trước. Danh mục không có khoản nào bị bỏ.
List<CategoryTotal> totalsByCategory(List<Expense> expenses) {
  final amount = <ExpenseCategory, int>{};
  final count = <ExpenseCategory, int>{};
  for (final e in expenses) {
    final c = e.effectiveCategory;
    amount[c] = (amount[c] ?? 0) + e.amount;
    count[c] = (count[c] ?? 0) + 1;
  }
  final list = [
    for (final c in amount.keys) CategoryTotal(c, amount[c]!, count[c]!),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return list;
}

class MemberSpending {
  /// Tổng tiền người này đã bỏ ra trả cho nhóm.
  final int paid;

  /// Tổng phần người này thực sự tiêu (phải chịu).
  final int consumed;
  const MemberSpending(this.paid, this.consumed);
}

/// Mỗi người đã trả bao nhiêu và tiêu bao nhiêu (chưa tính các lần trả nợ).
Map<int, MemberSpending> spendingByMember(
  List<Expense> expenses, {
  Iterable<int> memberIds = const [],
}) {
  final paid = {for (final id in memberIds) id: 0};
  final consumed = {for (final id in memberIds) id: 0};
  for (final e in expenses) {
    paid[e.paidBy] = (paid[e.paidBy] ?? 0) + e.amount;
    consumed.putIfAbsent(e.paidBy, () => 0);
    e.shares.forEach((id, v) {
      consumed[id] = (consumed[id] ?? 0) + v;
      paid.putIfAbsent(id, () => 0);
    });
  }
  return {
    for (final id in paid.keys) id: MemberSpending(paid[id]!, consumed[id]!),
  };
}

/// Tổng chi theo tháng, tháng cũ trước. Khóa là ngày 1 của tháng.
Map<DateTime, int> totalsByMonth(List<Expense> expenses) {
  final result = <DateTime, int>{};
  for (final e in expenses) {
    final m = DateTime(e.date.year, e.date.month);
    result[m] = (result[m] ?? 0) + e.amount;
  }
  final keys = result.keys.toList()..sort();
  return {for (final k in keys) k: result[k]!};
}
