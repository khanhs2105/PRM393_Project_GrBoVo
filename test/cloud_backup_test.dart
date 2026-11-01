import 'dart:io';

import 'package:chia_tien/data/app_database.dart';
import 'package:chia_tien/data/cloud_backup.dart';
import 'package:chia_tien/data/group_repository.dart';
import 'package:chia_tien/data/seed.dart';
import 'package:chia_tien/models/group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  // Mỗi "máy" một file riêng (cùng đường dẫn thì sqflite trả về cùng một db).
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('chipin_backup'));
  tearDown(() => dir.deleteSync(recursive: true));
  Future<Database> open(String name) =>
      AppDatabase.open(databaseFactoryFfi, '${dir.path}/$name.db');

  test('sao lưu rồi khôi phục sang máy khác giữ nguyên dữ liệu', () async {
    final a = await open('a');
    await seedIfEmpty(a);
    final snap = await dumpDatabase(a);
    expect(snap['schemaVersion'], AppDatabase.version);
    final counts = snap['counts'] as Map;
    expect(counts['groups'], greaterThan(0));
    expect(counts['expenses'], greaterThan(0));

    // "Máy" thứ hai đang có dữ liệu khác, khôi phục sẽ ghi đè.
    final b = await open('b');
    await GroupRepository(b)
        .create(Group(name: 'Rác', createdAt: DateTime(2026)), const []);
    await restoreDatabase(b, snap);

    for (final t in backupTables) {
      expect(await b.query(t), await a.query(t), reason: t);
    }
    expect(describeBackup(snap), contains('nhóm'));

    // Id mới vẫn tăng tiếp sau dữ liệu đã khôi phục.
    final maxId = (await b.rawQuery('SELECT MAX(id) AS m FROM groups'))
        .first['m'] as int;
    final newId = await GroupRepository(b)
        .create(Group(name: 'Mới', createdAt: DateTime(2026)), const []);
    expect(newId, greaterThan(maxId));
    await a.close();
    await b.close();
  });

  test('bản sao lưu từ app mới hơn thì từ chối', () async {
    final db = await open('c');
    await expectLater(
      restoreDatabase(db, {
        'schemaVersion': AppDatabase.version + 1,
        'tables': <String, dynamic>{},
      }),
      throwsStateError,
    );
    await db.close();
  });
}
