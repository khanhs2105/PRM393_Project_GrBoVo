import '../models/expense.dart';
import '../models/settlement.dart';

/// Tính số dư ròng của từng thành viên.
///
/// Dương: người đó đang được nợ (người khác phải trả cho họ).
/// Âm: người đó đang nợ.
/// Tổng tất cả số dư luôn bằng 0.
///
/// Với mỗi khoản chi: người trả +amount, mỗi người tham gia -phần của mình.
/// Với mỗi lần trả tiền: người trả +amount (bớt nợ), người nhận -amount.
Map<int, int> computeBalances(
  List<Expense> expenses,
  List<Settlement> settlements, {
  Iterable<int> memberIds = const [],
}) {
  final balances = {for (final id in memberIds) id: 0};

  void add(int id, int delta) => balances[id] = (balances[id] ?? 0) + delta;

  for (final e in expenses) {
    add(e.paidBy, e.amount);
    e.shares.forEach((memberId, share) => add(memberId, -share));
  }
  for (final s in settlements) {
    add(s.fromId, s.amount);
    add(s.toId, -s.amount);
  }
  return balances;
}
