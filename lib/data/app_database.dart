import 'package:sqflite_common/sqlite_api.dart';

/// Mở database SQLite của app và tạo bảng ở lần chạy đầu.
///
/// Trong app Flutter gọi:
///   import 'package:sqflite/sqflite.dart';
///   final db = await AppDatabase.open(
///       databaseFactory, join(await getDatabasesPath(), AppDatabase.fileName));
/// Trong unit test dùng databaseFactoryFfi và inMemoryDatabasePath.
class AppDatabase {
  static const fileName = 'chia_tien.db';
  /// 1: bản đầu. 2: danh mục, ghi chú, chia theo phần/%, lịch sử hoạt động.
  static const version = 2;

  static Future<Database> open(DatabaseFactory factory, String path) {
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        // Bật khóa ngoại để xóa nhóm thì xóa luôn thành viên, khoản chi...
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await _create(db);
          await _upgradeTo2(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) await _upgradeTo2(db);
        },
      ),
    );
  }

  static Future<void> _create(Database db) async {
    final batch = db.batch();
    batch.execute('''
      CREATE TABLE groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'meal',
        created_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE members (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        bank_bin TEXT,
        account_no TEXT,
        account_name TEXT
      )''');
    batch.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        amount INTEGER NOT NULL,
        paid_by INTEGER NOT NULL REFERENCES members(id),
        split_type TEXT NOT NULL,
        receipt_path TEXT,
        date INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE expense_shares (
        expense_id INTEGER NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
        member_id INTEGER NOT NULL REFERENCES members(id),
        amount INTEGER NOT NULL,
        PRIMARY KEY (expense_id, member_id)
      )''');
    batch.execute('''
      CREATE TABLE settlements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
        from_id INTEGER NOT NULL REFERENCES members(id),
        to_id INTEGER NOT NULL REFERENCES members(id),
        amount INTEGER NOT NULL,
        paid_at INTEGER NOT NULL
      )''');
    batch.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )''');
    batch.execute('CREATE INDEX idx_members_group ON members(group_id)');
    batch.execute('CREATE INDEX idx_expenses_group ON expenses(group_id)');
    batch.execute(
      'CREATE INDEX idx_settlements_group ON settlements(group_id)',
    );
    await batch.commit(noResult: true);
  }

  /// Thêm cột và bảng mới của bản 2. Chạy cho cả máy cài mới lẫn máy nâng cấp
  /// nên dữ liệu cũ được giữ nguyên.
  static Future<void> _upgradeTo2(Database db) async {
    final batch = db.batch();
    batch.execute('ALTER TABLE expenses ADD COLUMN category TEXT');
    batch.execute('ALTER TABLE expenses ADD COLUMN note TEXT');
    batch.execute('ALTER TABLE expense_shares ADD COLUMN weight INTEGER');
    batch.execute('ALTER TABLE settlements ADD COLUMN note TEXT');
    batch.execute('''
      CREATE TABLE activities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        group_id INTEGER,
        group_name TEXT NOT NULL,
        kind TEXT NOT NULL,
        message TEXT NOT NULL,
        amount INTEGER,
        created_at INTEGER NOT NULL
      )''');
    batch.execute(
      'CREATE INDEX idx_activities_group ON activities(group_id, created_at)',
    );
    await batch.commit(noResult: true);
  }
}
