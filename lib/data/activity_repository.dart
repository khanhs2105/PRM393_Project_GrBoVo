import 'package:sqflite_common/sqlite_api.dart';

import '../models/activity.dart';

/// Lịch sử hoạt động, giống tab "Activity" của Splitwise.
class ActivityRepository {
  final Database db;
  ActivityRepository(this.db);

  Future<int> log({
    required int? groupId,
    required String groupName,
    required String kind,
    required String message,
    int? amount,
    DateTime? at,
  }) =>
      db.insert(
        'activities',
        Activity(
          groupId: groupId,
          groupName: groupName,
          kind: kind,
          message: message,
          amount: amount,
          createdAt: at ?? DateTime.now(),
        ).toMap()
          ..remove('id'),
      );

  /// Mới nhất trước. [groupId] null: mọi nhóm.
  Future<List<Activity>> recent({int? groupId, int limit = 200}) async {
    final rows = await db.query(
      'activities',
      where: groupId == null ? null : 'group_id = ?',
      whereArgs: groupId == null ? null : [groupId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(Activity.fromMap).toList();
  }
}
