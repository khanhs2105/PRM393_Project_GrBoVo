import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../data/expense_repository.dart';
import '../data/group_repository.dart';
import '../data/seed.dart';
import '../data/settings_repository.dart';
import '../data/settlement_repository.dart';
import '../logic/plans.dart';
import '../models/bank.dart';

/// Các đối tượng dùng chung toàn app, khởi tạo một lần trong main().
/// App nhỏ nên dùng biến toàn cục cho đơn giản, không cần Provider.
class App {
  static late final Database db;
  static late final GroupRepository groups;
  static late final ExpenseRepository expenses;
  static late final SettlementRepository settlements;
  static late final SettingsRepository settings;
  static late final List<Bank> banks;

  /// Gói đang dùng. Màn hình nào cần thì lắng nghe bằng ValueListenableBuilder.
  static final plan = ValueNotifier<Plan>(Plan.conNo);

  static Future<void> init() async {
    db = await AppDatabase.open(
        databaseFactory, join(await getDatabasesPath(), AppDatabase.fileName));
    groups = GroupRepository(db);
    expenses = ExpenseRepository(db);
    settlements = SettlementRepository(db);
    settings = SettingsRepository(db);
    banks = parseBanks(await rootBundle.loadString('assets/banks.json'));
    plan.value = await settings.currentPlan();
    await seedIfEmpty(db);
  }

  static Future<void> setPlan(Plan p) async {
    await settings.setPlan(p);
    plan.value = p;
  }
}
