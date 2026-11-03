import 'dart:io';

import 'package:sqflite_common/sqlite_api.dart';

import '../models/group.dart';
import '../models/member.dart';

/// Số thành viên tối thiểu của một nhóm.
const minGroupMembers = 2;

class GroupRepository {
  final Database db;
  GroupRepository(this.db);

  /// Nhóm mới tạo nằm trên cùng.
  Future<List<Group>> getAll() async {
    final rows = await db.query('groups', orderBy: 'created_at DESC, id DESC');
    return rows.map(Group.fromMap).toList();
  }

  Future<Group?> getById(int id) async {
    final rows = await db.query('groups', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Group.fromMap(rows.first);
  }

  /// Tạo nhóm cùng danh sách thành viên ([Member.groupId] sẽ được gán lại).
  /// Trả về id của nhóm mới.
  Future<int> create(Group group, List<Member> members) {
    return db.transaction((txn) async {
      final groupId = await txn.insert('groups', group.toMap()..remove('id'));
      for (final m in members) {
        await txn.insert(
          'members',
          m.copyWith(groupId: groupId).toMap()..remove('id'),
        );
      }
      return groupId;
    });
  }

  /// Nhân bản nhóm cho lần đi chơi sau: chép loại nhóm và thành viên (kèm
  /// tài khoản ngân hàng), không chép khoản chi hay lần trả tiền.
  /// Trả về id của nhóm mới.
  Future<int> duplicate(int groupId, String newName) async {
    final source = await getById(groupId);
    if (source == null) throw StateError('Không tìm thấy nhóm #$groupId');
    final copied = await members(groupId);
    return create(
      Group(name: newName, type: source.type, createdAt: DateTime.now()),
      [for (final m in copied) m.copyWith(groupId: 0)],
    );
  }

  Future<void> update(Group group) => db.update(
        'groups',
        group.toMap(),
        where: 'id = ?',
        whereArgs: [group.id],
      );

  /// Xóa nhóm, kéo theo thành viên, khoản chi, lần trả tiền của nhóm.
  /// Xóa luôn lịch sử hoạt động của nhóm và file ảnh hóa đơn (không còn
  /// khoản chi nào trỏ tới nữa).
  Future<void> delete(int groupId) async {
    final receipts = await db.query('expenses',
        columns: ['receipt_path'],
        where: 'group_id = ? AND receipt_path IS NOT NULL',
        whereArgs: [groupId]);
    await db.transaction((txn) async {
      await txn.delete('activities', where: 'group_id = ?', whereArgs: [groupId]);
      await txn.delete('groups', where: 'id = ?', whereArgs: [groupId]);
    });
    for (final r in receipts) {
      await deleteFileQuietly(r['receipt_path'] as String?);
    }
  }

  Future<List<Member>> members(int groupId) async {
    final rows = await db.query(
      'members',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'id',
    );
    return rows.map(Member.fromMap).toList();
  }

  Future<int> addMember(Member m) =>
      db.insert('members', m.toMap()..remove('id'));

  Future<void> updateMember(Member m) =>
      db.update('members', m.toMap(), where: 'id = ?', whereArgs: [m.id]);

  /// Chỉ xóa được thành viên chưa dính tới khoản chi hay lần trả tiền nào.
  /// Trả về false nếu không xóa được (UI nên báo cho người dùng).
  Future<bool> deleteMember(int memberId) async {
    final used = await db.rawQuery(
      '''
      SELECT 1 FROM expenses WHERE paid_by = ?1
      UNION SELECT 1 FROM expense_shares WHERE member_id = ?1
      UNION SELECT 1 FROM settlements WHERE from_id = ?1 OR to_id = ?1
      LIMIT 1''',
      [memberId],
    );
    if (used.isNotEmpty) return false;
    // Nhóm phải còn ít nhất 2 người (xóa hết thì màn thêm khoản chi và
    // "lắc chọn người bao" bị lỗi).
    final left = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM members WHERE group_id = '
      '(SELECT group_id FROM members WHERE id = ?)',
      [memberId],
    );
    if (((left.first['n'] as int?) ?? 0) <= minGroupMembers) return false;
    await db.delete('members', where: 'id = ?', whereArgs: [memberId]);
    return true;
  }
}

/// Xóa file nếu còn, lỗi thì bỏ qua (dọn dẹp, không ảnh hưởng dữ liệu).
Future<void> deleteFileQuietly(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
