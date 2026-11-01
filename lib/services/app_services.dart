import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../data/activity_repository.dart';
import '../data/app_database.dart';
import '../data/expense_repository.dart';
import '../data/group_repository.dart';
import '../data/seed.dart';
import '../data/settings_repository.dart';
import '../data/settlement_repository.dart';
import '../logic/plans.dart';
import '../models/bank.dart';
import 'auth_service.dart';

/// Các đối tượng dùng chung toàn app, khởi tạo một lần trong main().
/// App nhỏ nên dùng biến toàn cục cho đơn giản, không cần Provider.
class App {
  static late final Database db;
  static late final GroupRepository groups;
  static late final ExpenseRepository expenses;
  static late final SettlementRepository settlements;
  static late final SettingsRepository settings;
  static late final ActivityRepository activities;
  static late final List<Bank> banks;

  /// Đăng nhập Firebase. null nếu Firebase chưa cấu hình được
  /// (thiếu google-services.json...), khi đó [firebaseError] cho biết lý do.
  static AuthService? auth;
  static Object? firebaseError;

  /// Gói đang dùng. Màn hình nào cần thì lắng nghe bằng ValueListenableBuilder.
  static final plan = ValueNotifier<Plan>(Plan.conNo);

  static Future<void> init() async {
    db = await AppDatabase.open(
        databaseFactory, join(await getDatabasesPath(), AppDatabase.fileName));
    groups = GroupRepository(db);
    expenses = ExpenseRepository(db);
    settlements = SettlementRepository(db);
    settings = SettingsRepository(db);
    activities = ActivityRepository(db);
    banks = parseBanks(await rootBundle.loadString('assets/banks.json'));
    plan.value = await settings.currentPlan();
    await seedIfEmpty(db);
  }

  static Future<void> initFirebase() async {
    try {
      await Firebase.initializeApp();
      auth = AuthService();
    } catch (e) {
      firebaseError = e;
      debugPrint('Firebase chưa sẵn sàng: $e');
    }
  }

  /// Đổi gói trên máy và đồng bộ lên hồ sơ Firestore nếu đang đăng nhập.
  static Future<void> setPlan(Plan p, {bool sync = true}) async {
    await settings.setPlan(p);
    plan.value = p;
    if (sync) await auth?.savePlan(p.name);
  }

  /// Đăng nhập rồi lấy lại gói đã lưu trên Firestore (nếu có).
  static Future<void> signIn(String email, String password) async {
    final profile = await auth!.signIn(email: email, password: password);
    final saved = profile?.plan;
    if (saved != null) await setPlan(Plan.fromName(saved), sync: false);
  }

  static Future<void> register(
          String name, String email, String password) =>
      auth!.register(
          name: name, email: email, password: password, plan: plan.value.name);
}
