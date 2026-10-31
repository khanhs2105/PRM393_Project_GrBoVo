import 'package:sqflite_common/sqlite_api.dart';

import '../logic/plans.dart';

/// Lưu cài đặt dạng key/value, hiện dùng cho gói tài khoản.
class SettingsRepository {
  final Database db;
  SettingsRepository(this.db);

  Future<String?> get(String key) async {
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> set(String key, String? value) => db.insert(
      'app_settings',
      {
        'key': key,
        'value': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Plan> currentPlan() async => Plan.fromName(await get('plan'));

  /// "Mua" gói: không thanh toán thật, chỉ lưu lại.
  Future<void> setPlan(Plan plan) => set('plan', plan.name);
}
