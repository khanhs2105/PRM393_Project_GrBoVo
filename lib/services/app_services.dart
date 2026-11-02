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
import '../logic/growth.dart';
import '../logic/plans.dart';
import '../models/bank.dart';
import 'auth_service.dart';
import 'notification_service.dart';

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

  /// Gói đang áp dụng (đã tính dùng thử). Màn hình nào cần thì lắng nghe
  /// bằng ValueListenableBuilder.
  static final plan = ValueNotifier<Plan>(Plan.conNo);

  /// Gói đã "mua" (không tính dùng thử).
  static Plan purchasedPlan = Plan.conNo;

  /// Hạn dùng thử Pro, null nếu chưa dùng thử lần nào.
  static DateTime? trialUntil;
  static bool get trialUsed => trialUntil != null;
  static bool get onTrial =>
      !purchasedPlan.isPro &&
      trialUntil != null &&
      DateTime.now().isBefore(trialUntil!);

  /// Lần mở app đầu tiên trên máy: không hiện quảng cáo.
  static bool firstSession = false;

  static final ads = AdPolicy();

  static Future<void> init() async {
    db = await AppDatabase.open(
        databaseFactory, join(await getDatabasesPath(), AppDatabase.fileName));
    groups = GroupRepository(db);
    expenses = ExpenseRepository(db);
    settlements = SettlementRepository(db);
    settings = SettingsRepository(db);
    activities = ActivityRepository(db);
    banks = parseBanks(await rootBundle.loadString('assets/banks.json'));
    purchasedPlan = await settings.currentPlan();
    final trial = await settings.get('pro_trial_until');
    trialUntil = trial == null ? null : DateTime.tryParse(trial);
    firstSession = await settings.get('first_open') == null;
    if (firstSession) {
      await settings.set('first_open', DateTime.now().toIso8601String());
    }
    _refreshPlan();
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
    purchasedPlan = p;
    _refreshPlan();
    if (sync) await auth?.savePlan(p.name);
  }

  static void _refreshPlan() =>
      plan.value = effectivePlan(purchasedPlan, trialUntil, DateTime.now());

  /// Bắt đầu dùng thử Pro $proTrialDays ngày (mỗi máy một lần) và hẹn thông
  /// báo trước khi hết hạn một ngày, để không ai bị bất ngờ.
  static Future<void> startTrial() async {
    if (trialUsed) return;
    final until = DateTime.now().add(const Duration(days: proTrialDays));
    await settings.set('pro_trial_until', until.toIso8601String());
    trialUntil = until;
    _refreshPlan();
    try {
      if (await NotificationService.requestPermission()) {
        await NotificationService.schedule(
          at: until.subtract(const Duration(days: 1)),
          title: 'Pro dùng thử còn 1 ngày',
          body: 'Mai hết dùng thử. App tự quay về gói Con Nợ, '
              'không trừ đồng nào. Thích thì nâng cấp nhé 😎',
        );
      }
    } catch (e) {
      debugPrint('Không hẹn được thông báo hết dùng thử: $e');
    }
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
