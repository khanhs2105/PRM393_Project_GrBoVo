import 'package:sqflite_common/sqlite_api.dart';

import 'app_database.dart';

/// Các bảng được sao lưu lên Firestore, theo thứ tự cha trước con
/// (khôi phục thì chèn theo thứ tự này, xóa theo thứ tự ngược lại).
/// Bảng app_settings không sao lưu (gói tài khoản đã nằm trong hồ sơ người
/// dùng), trừ các khóa "nhóm nào là sổ chung nào" ([ledgerKeyPrefix]): mất
/// chúng thì sau khi khôi phục, sổ chung cũ bị bỏ rơi.
const ledgerKeyPrefix = 'ledger_';

const backupTables = [
  'groups',
  'members',
  'expenses',
  'expense_shares',
  'settlements',
  'activities',
];

/// Chụp toàn bộ dữ liệu trên máy thành một Map để ghi vào Firestore.
/// Kết quả: {schemaVersion, tables: {tên bảng: [dòng...]}, counts: {tên bảng: số dòng}}.
Future<Map<String, Object?>> dumpDatabase(Database db) async {
  final tables = <String, List<Map<String, Object?>>>{};
  for (final t in backupTables) {
    final rows = await db.query(t);
    tables[t] = [for (final r in rows) Map<String, Object?>.from(r)];
  }
  final ledgerKeys = await db.query('app_settings',
      where: 'key LIKE ?', whereArgs: ['$ledgerKeyPrefix%']);
  return {
    'schemaVersion': AppDatabase.version,
    'tables': tables,
    'ledgerKeys': {
      for (final r in ledgerKeys) r['key'] as String: r['value'] as String?,
    },
    'counts': {for (final e in tables.entries) e.key: e.value.length},
  };
}

/// Ghi đè dữ liệu trên máy bằng bản sao lưu. Chạy trong một transaction nên
/// lỗi giữa chừng thì dữ liệu cũ vẫn còn nguyên.
Future<void> restoreDatabase(Database db, Map<String, dynamic> snapshot) async {
  final version = (snapshot['schemaVersion'] as num?)?.toInt() ?? 0;
  if (version > AppDatabase.version) {
    throw StateError(
        'Bản sao lưu được tạo từ phiên bản app mới hơn. Hãy cập nhật app.');
  }
  final tables = (snapshot['tables'] as Map?)?.cast<String, dynamic>();
  if (tables == null) throw const FormatException('Bản sao lưu bị hỏng');

  await db.transaction((txn) async {
    for (final t in backupTables.reversed) {
      await txn.delete(t);
    }
    for (final t in backupTables) {
      final rows = (tables[t] as List?) ?? const [];
      for (final r in rows) {
        await txn.insert(t, Map<String, Object?>.from(r as Map));
      }
    }
    // Khóa sổ chung cũ trỏ tới id nhóm cũ: bỏ hết rồi lấy theo bản sao lưu,
    // để không đẩy nhầm một nhóm khác (trùng id) lên sổ chung.
    await txn.delete('app_settings',
        where: 'key LIKE ?', whereArgs: ['$ledgerKeyPrefix%']);
    final keys = (snapshot['ledgerKeys'] as Map?) ?? const {};
    for (final e in keys.entries) {
      if (e.value == null) continue;
      await txn.insert('app_settings', {'key': '${e.key}', 'value': '${e.value}'});
    }
  });
}

/// "3 nhóm, 12 khoản chi" để hiển thị bản sao lưu.
String describeBackup(Map<String, dynamic> snapshot) {
  final counts = (snapshot['counts'] as Map?)?.cast<String, dynamic>() ?? {};
  int c(String t) => (counts[t] as num?)?.toInt() ?? 0;
  return '${c('groups')} nhóm, ${c('members')} thành viên, '
      '${c('expenses')} khoản chi, ${c('settlements')} lần trả nợ';
}
