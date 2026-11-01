import 'package:sqflite_common/sqlite_api.dart';

import '../logic/money.dart';
import '../models/expense.dart';

class ExpenseRepository {
  final Database db;
  ExpenseRepository(this.db);

  /// Khoản chi của nhóm, mới nhất trước, đã kèm [Expense.shares].
  Future<List<Expense>> byGroup(int groupId) async {
    final rows = await db.query(
      'expenses',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'date DESC, id DESC',
    );
    if (rows.isEmpty) return [];

    final shareRows = await db.rawQuery(
      '''
      SELECT s.expense_id, s.member_id, s.amount, s.weight
      FROM expense_shares s
      JOIN expenses e ON e.id = s.expense_id
      WHERE e.group_id = ?''',
      [groupId],
    );
    final sharesByExpense = <int, Map<int, int>>{};
    final weightsByExpense = <int, Map<int, int>>{};
    for (final r in shareRows) {
      final expenseId = r['expense_id'] as int;
      final memberId = r['member_id'] as int;
      (sharesByExpense[expenseId] ??= {})[memberId] = r['amount'] as int;
      final w = r['weight'] as int?;
      if (w != null) (weightsByExpense[expenseId] ??= {})[memberId] = w;
    }
    return [
      for (final r in rows)
        Expense.fromMap(
          r,
          sharesByExpense[r['id'] as int] ?? {},
          weightsByExpense[r['id'] as int] ?? {},
        ),
    ];
  }

  Future<Expense?> getById(int id) async {
    final rows = await db.query('expenses', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final shareRows = await db.query(
      'expense_shares',
      where: 'expense_id = ?',
      whereArgs: [id],
    );
    return Expense.fromMap(rows.first, {
      for (final r in shareRows) r['member_id'] as int: r['amount'] as int,
    }, {
      for (final r in shareRows)
        if (r['weight'] != null) r['member_id'] as int: r['weight'] as int,
    });
  }

  /// Thêm mới nếu [Expense.id] là null, ngược lại cập nhật. Trả về id.
  /// Báo lỗi nếu tổng các phần không bằng số tiền.
  Future<int> save(Expense e) {
    if (e.shares.isEmpty) {
      throw ArgumentError('Khoản chi phải có ít nhất 1 người tham gia');
    }
    if (!sharesMatchTotal(e.amount, e.shares)) {
      throw ArgumentError('Tổng các phần không bằng số tiền ${e.amount}');
    }
    return db.transaction((txn) async {
      final int id;
      if (e.id == null) {
        id = await txn.insert('expenses', e.toMap()..remove('id'));
      } else {
        id = e.id!;
        await txn.update(
          'expenses',
          e.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'expense_shares',
          where: 'expense_id = ?',
          whereArgs: [id],
        );
      }
      for (final s in e.shares.entries) {
        await txn.insert('expense_shares', {
          'expense_id': id,
          'member_id': s.key,
          'amount': s.value,
          'weight': e.weights[s.key],
        });
      }
      return id;
    });
  }

  Future<void> delete(int id) =>
      db.delete('expenses', where: 'id = ?', whereArgs: [id]);

  /// Thêm lại khoản chi vừa xóa (nút "Hoàn tác"), giữ nguyên id cũ.
  Future<void> restore(Expense e) async {
    await db.transaction((txn) async {
      await txn.insert('expenses', e.toMap());
      for (final s in e.shares.entries) {
        await txn.insert('expense_shares', {
          'expense_id': e.id,
          'member_id': s.key,
          'amount': s.value,
          'weight': e.weights[s.key],
        });
      }
    });
  }
}
