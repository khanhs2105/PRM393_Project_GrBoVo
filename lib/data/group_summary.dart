import 'package:sqflite_common/sqlite_api.dart';

import '../logic/balances.dart';
import '../logic/debt_simplifier.dart';
import '../models/expense.dart';
import '../models/member.dart';
import '../models/settlement.dart';
import 'expense_repository.dart';
import 'group_repository.dart';
import 'settlement_repository.dart';

/// Mọi thứ màn Chi tiết nhóm cần, lấy trong một lần gọi.
class GroupSummary {
  final List<Member> members;
  final List<Expense> expenses;
  final List<Settlement> settlements;

  /// memberId -> số dư (dương: được nợ, âm: đang nợ)
  final Map<int, int> balances;

  /// Gợi ý thanh toán đã rút gọn.
  final List<Transfer> transfers;

  const GroupSummary({
    required this.members,
    required this.expenses,
    required this.settlements,
    required this.balances,
    required this.transfers,
  });

  int get totalSpent => expenses.fold(0, (sum, e) => sum + e.amount);

  Member memberById(int id) => members.firstWhere((m) => m.id == id);

  static Future<GroupSummary> load(Database db, int groupId) async {
    final members = await GroupRepository(db).members(groupId);
    final expenses = await ExpenseRepository(db).byGroup(groupId);
    final settlements = await SettlementRepository(db).byGroup(groupId);
    final balances = computeBalances(
      expenses,
      settlements,
      memberIds: members.map((m) => m.id!),
    );
    return GroupSummary(
      members: members,
      expenses: expenses,
      settlements: settlements,
      balances: balances,
      transfers: simplifyDebts(balances),
    );
  }
}
