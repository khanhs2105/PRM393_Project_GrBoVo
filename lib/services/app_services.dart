import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../data/activity_repository.dart';
import '../data/app_database.dart';
import '../data/expense_repository.dart';
import '../data/group_repository.dart';
import '../data/settings_repository.dart';
import '../data/settlement_repository.dart';
import '../logic/growth.dart';
import '../logic/plans.dart';
import '../models/bank.dart';
import 'auth_service.dart';
import 'ledger_service.dart';
import 'notification_service.dart';

/// Các đối tượng dùng chung toàn app, khởi tạo một lần trong main().
/// App nhỏ nên dùng biến toàn cục cho đơn giản, không cần Provider.
class App {
  /// Dữ liệu trên máy của tài khoản đang đăng nhập. Mỗi tài khoản một file
  /// SQLite riêng, mở lại bằng [openForUser] khi đổi tài khoản, để tài khoản
  /// mới không thấy nhóm của tài khoản cũ trên cùng điện thoại.
  static late Database db;
  static late GroupRepository groups;
  static late ExpenseRepository expenses;
  static late SettlementRepository settlements;
  static late SettingsRepository settings;
  static late ActivityRepository activities;
  static late final List<Bank> banks;

  /// uid của tài khoản đang mở dữ liệu, null nếu chưa mở.
  static String? openedUid;

  /// Đăng nhập Firebase. null nếu Firebase chưa cấu hình được
  /// (thiếu google-services.json...), khi đó [firebaseError] cho biết lý do.
  static AuthService? auth;

  /// Sổ chung nhiều tài khoản trên Firestore. null nếu Firebase lỗi.
  static LedgerService? shared;
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
    banks = parseBanks(await rootBundle.loadString('assets/banks.json'));
  }

  /// Mở dữ liệu của tài khoản [uid] (gọi sau khi đăng nhập). Gọi lại với
  /// cùng uid thì không làm gì.
  ///
  /// Bản cũ dùng chung một file cho mọi tài khoản. File cũ đó (nếu còn)
  /// được giao cho tài khoản đăng nhập đầu tiên sau khi cập nhật, các tài
  /// khoản khác bắt đầu với sổ trống. Không còn tạo nhóm mẫu.
  static Future<void> openForUser(String uid) {
    if (openedUid == uid) return Future.value();
    // Đăng ký xong thì cả màn đăng ký lẫn AuthGate cùng gọi: dùng chung
    // một lần mở.
    if (_openingUid == uid && _opening != null) return _opening!;
    _openingUid = uid;
    return _opening = _open(uid).whenComplete(() {
      _opening = null;
      _openingUid = null;
    });
  }

  static Future<void>? _opening;
  static String? _openingUid;

  static Future<void> _open(String uid) async {
    final dir = await getDatabasesPath();
    final path = join(dir, AppDatabase.fileNameFor(uid));
    final legacy = join(dir, AppDatabase.fileName);
    if (!await databaseExists(path) && await databaseExists(legacy)) {
      try {
        await File(legacy).rename(path);
        for (final ext in ['-wal', '-shm', '-journal']) {
          final f = File('$legacy$ext');
          if (await f.exists()) await f.rename('$path$ext');
        }
      } catch (e) {
        debugPrint('Không chuyển được dữ liệu cũ: $e');
      }
    }
    if (openedUid != null) await db.close();
    db = await AppDatabase.open(databaseFactory, path);
    openedUid = uid;
    groups = GroupRepository(db);
    expenses = ExpenseRepository(db);
    settlements = SettlementRepository(db);
    settings = SettingsRepository(db);
    activities = ActivityRepository(db);
    shared?.attach(db);
    purchasedPlan = await settings.currentPlan();
    final trial = await settings.get('pro_trial_until');
    trialUntil = trial == null ? null : DateTime.tryParse(trial);
    firstSession = await settings.get('first_open') == null;
    if (firstSession) {
      await settings.set('first_open', DateTime.now().toIso8601String());
    }
    _refreshPlan();
  }

  static Future<void> initFirebase() async {
    try {
      await Firebase.initializeApp();
      auth = AuthService();
      shared = LedgerService();
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
    await openForUser(auth!.currentUser!.uid);
    final saved = profile?.plan;
    if (saved != null) await setPlan(Plan.fromName(saved), sync: false);
  }

  static Future<void> register(
      String name, String email, String password) async {
    await auth!.register(
        name: name, email: email, password: password, plan: plan.value.name);
    // Tài khoản mới: bắt đầu gói Con Nợ trên sổ trống của chính mình.
    await openForUser(auth!.currentUser!.uid);
  }
}
