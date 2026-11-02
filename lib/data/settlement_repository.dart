import 'package:sqflite_common/sqlite_api.dart';

import '../models/settlement.dart';

class SettlementRepository {
  final Database db;
  SettlementRepository(this.db);

  /// Lịch sử trả tiền của nhóm, mới nhất trước.
  Future<List<Settlement>> byGroup(int groupId) async {
    final rows = await db.query(
      'settlements',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'paid_at DESC, id DESC',
    );
    return rows.map(Settlement.fromMap).toList();
  }

  /// Ghi nhận một lượt chuyển tiền gợi ý là đã trả. Trả về id.
  Future<int> markPaid(int groupId, Transfer t, {DateTime? paidAt}) => record(
        groupId: groupId,
        fromId: t.fromId,
        toId: t.toId,
        amount: t.amount,
        paidAt: paidAt,
      );

  /// Số tiền tối đa [fromId] còn trả được cho [toId] lúc này: không quá số
  /// [fromId] đang nợ, và không quá số [toId] đang được nợ.
  Future<int> maxPayable(int groupId, int fromId, int toId) =>
      _maxPayable(db, groupId, fromId, toId);

  /// Ghi nhận một lần trả tiền, kể cả trả một phần.
  ///
  /// Kiểm tra số nợ còn lại trong cùng một transaction rồi mới ghi, nên bấm
  /// "Đã trả" nhiều lần liên tiếp cũng chỉ ghi được tối đa đúng số đang nợ.
  /// Trả quá số nợ thì ném [OverpaymentException].
  Future<int> record({
    required int groupId,
    required int fromId,
    required int toId,
    required int amount,
    DateTime? paidAt,
    String? note,
  }) {
    if (fromId == toId) throw ArgumentError('Người trả và người nhận trùng nhau');
    if (amount <= 0) throw ArgumentError('Số tiền phải lớn hơn 0');
    return db.transaction((txn) async {
      final max = await _maxPayable(txn, groupId, fromId, toId);
      if (amount > max) throw OverpaymentException(max);
      return txn.insert(
        'settlements',
        Settlement(
          groupId: groupId,
          fromId: fromId,
          toId: toId,
          amount: amount,
          paidAt: paidAt ?? DateTime.now(),
          note: note,
        ).toMap()
          ..remove('id'),
      );
    });
  }

  static Future<int> _maxPayable(
      DatabaseExecutor ex, int groupId, int fromId, int toId) async {
    final owes = -await _balance(ex, groupId, fromId);
    final owed = await _balance(ex, groupId, toId);
    final max = owes < owed ? owes : owed;
    return max > 0 ? max : 0;
  }

  /// Số dư của một thành viên (dương: được nợ, âm: đang nợ), cùng công thức
  /// với computeBalances nhưng tính thẳng bằng SQL.
  static Future<int> _balance(
      DatabaseExecutor ex, int groupId, int memberId) async {
    final rows = await ex.rawQuery(
      '''
      SELECT
        (SELECT COALESCE(SUM(amount), 0) FROM expenses
          WHERE group_id = ?1 AND paid_by = ?2)
        - (SELECT COALESCE(SUM(s.amount), 0) FROM expense_shares s
          JOIN expenses e ON e.id = s.expense_id
          WHERE e.group_id = ?1 AND s.member_id = ?2)
        + (SELECT COALESCE(SUM(amount), 0) FROM settlements
          WHERE group_id = ?1 AND from_id = ?2)
        - (SELECT COALESCE(SUM(amount), 0) FROM settlements
          WHERE group_id = ?1 AND to_id = ?2) AS balance''',
      [groupId, memberId],
    );
    return (rows.first['balance'] as num?)?.toInt() ?? 0;
  }

  /// Hoàn tác khi bấm nhầm "Đã trả".
  Future<void> delete(int id) =>
      db.delete('settlements', where: 'id = ?', whereArgs: [id]);
}

/// Ghi nhận số tiền lớn hơn số nợ còn lại (thường do bấm "Đã trả" nhiều lần).
class OverpaymentException implements Exception {
  /// Số tiền tối đa còn trả được, 0 nếu đã trả hết.
  final int maxPayable;
  const OverpaymentException(this.maxPayable);

  @override
  String toString() => maxPayable == 0
      ? 'Khoản này đã trả hết rồi'
      : 'Chỉ còn nợ $maxPayable₫, không ghi nhận quá số này';
}
