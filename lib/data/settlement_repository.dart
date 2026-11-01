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
  Future<int> markPaid(int groupId, Transfer t, {DateTime? paidAt}) {
    return db.insert(
      'settlements',
      Settlement(
        groupId: groupId,
        fromId: t.fromId,
        toId: t.toId,
        amount: t.amount,
        paidAt: paidAt ?? DateTime.now(),
      ).toMap()
        ..remove('id'),
    );
  }

  /// Ghi nhận một lần trả tiền bất kỳ, kể cả trả một phần hoặc trả trước.
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
    return db.insert(
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
  }

  /// Hoàn tác khi bấm nhầm "Đã trả".
  Future<void> delete(int id) =>
      db.delete('settlements', where: 'id = ?', whereArgs: [id]);
}
