import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
import 'avatar_cache.dart';
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

  /// Có DB đang mở (kể cả sau khi đăng xuất, khi openedUid đã là null).
  static bool _dbOpen = false;

  /// Đăng nhập Firebase. null nếu Firebase chưa cấu hình được
  /// (thiếu google-services.json...), khi đó [firebaseError] cho biết lý do.
  static AuthService? auth;

  /// Sổ chung nhiều tài khoản trên Firestore. null nếu Firebase lỗi.
  static LedgerService? shared;
  static Object? firebaseError;

  /// Gói đang áp dụng (đã tính dùng thử). Màn hình nào cần thì lắng nghe
  /// bằng ValueListenableBuilder.
  static final plan = ValueNotifier<Plan>(Plan.conNo);

  /// Tăng mỗi khi gói đã mua / dùng thử thay đổi, kể cả khi [plan] (gói
  /// thực tế) không đổi, ví dụ mua Chủ Nợ trong lúc đang dùng thử.
  static final planChanges = ValueNotifier<int>(0);

  /// Gói đã "mua" (không tính dùng thử).
  static Plan purchasedPlan = Plan.conNo;

  /// Hạn dùng thử Pro, null nếu chưa dùng thử lần nào.
  static DateTime? trialUntil;
  /// Máy này đã từng bật dùng thử (với bất kỳ tài khoản nào). Lưu ngoài DB
  /// riêng từng tài khoản để tạo tài khoản mới không được dùng thử lại.
  static bool _deviceTrialUsed = false;
  static bool get trialUsed => trialUntil != null || _deviceTrialUsed;
  static bool get onTrial =>
      !purchasedPlan.isPro &&
      trialUntil != null &&
      DateTime.now().isBefore(trialUntil!);

  /// Lần mở app đầu tiên trên máy: không hiện quảng cáo.
  static bool firstSession = false;

  static final ads = AdPolicy();

  static AppLifecycleListener? _lifecycle;

  static Future<void> init() async {
    // Mở lại app (từ nền) thì tính lại gói: dùng thử hết hạn trong lúc app
    // nằm nền thì quay về Con Nợ ngay, không đợi khởi động lại.
    _lifecycle ??= AppLifecycleListener(onResume: _refreshPlan);
    banks = parseBanks(await rootBundle.loadString('assets/banks.json'));
  }

  /// Mở dữ liệu của tài khoản [uid] (gọi sau khi đăng nhập). Gọi lại với
  /// cùng uid thì không làm gì.
  ///
  /// Bản cũ dùng chung một file cho mọi tài khoản. File cũ đó (nếu còn)
  /// được giao cho tài khoản đăng nhập đầu tiên sau khi cập nhật, các tài
  /// khoản khác bắt đầu với sổ trống. Không còn tạo nhóm mẫu.
  ///
  /// [claimLegacy] hỏi người dùng có nhận file dữ liệu cũ đó không (file có
  /// thể là của người khác từng dùng máy). Không hỏi được thì không nhận.
  static Future<void> openForUser(String uid,
      {Future<bool> Function()? claimLegacy}) {
    if (openedUid == uid && _opening == null) return Future.value();
    // Đăng ký xong thì cả màn đăng ký lẫn AuthGate cùng gọi: dùng chung
    // một lần mở.
    if (_openingUid == uid && _opening != null) return _opening!;
    _openingUid = uid;
    // Đổi tài khoản nhanh: đợi lần mở trước xong hẳn rồi mới mở DB mới,
    // để không đóng nhầm DB hay để App.db lệch với openedUid.
    final f = _lock
        .then((_) => openedUid == uid ? null : _open(uid, claimLegacy));
    _lock = f.then((_) {}, onError: (_) {});
    late final Future<void> done;
    done = f.whenComplete(() {
      if (identical(_opening, done)) {
        _opening = null;
        _openingUid = null;
      }
    });
    return _opening = done;
  }

  static Future<void> _lock = Future.value();
  static Future<void>? _opening;
  static String? _openingUid;

  static Future<void> _open(
      String uid, Future<bool> Function()? claimLegacy) async {
    final dir = await getDatabasesPath();
    _deviceTrialFile = File(join(dir, 'device_trial_used'));
    _deviceTrialUsed = await _deviceTrialFile!.exists();
    final path = join(dir, AppDatabase.fileNameFor(uid));
    final legacy = join(dir, AppDatabase.fileName);
    if (!await databaseExists(path) &&
        await databaseExists(legacy) &&
        claimLegacy != null &&
        await claimLegacy()) {
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
    if (_dbOpen) await db.close();
    db = await AppDatabase.open(databaseFactory, path);
    _dbOpen = true;
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

  static File? _deviceTrialFile;

  /// Đăng xuất: hủy thông báo đã hẹn (nhắc nợ, hết dùng thử) của tài khoản
  /// này, quên gói và ảnh đại diện đã tải, để người dùng sau trên cùng máy
  /// không thấy.
  static Future<void> signOut() async {
    try {
      await NotificationService.cancelAll();
    } catch (e) {
      debugPrint('Không hủy được thông báo: $e');
    }
    await auth?.signOut();
    purchasedPlan = Plan.conNo;
    trialUntil = null;
    // Lần đăng nhập sau (kể cả cùng tài khoản) mở lại DB và đọc lại gói,
    // dùng thử từ DB. DB cũ được đóng lúc đó, không đóng ngay để các màn
    // đang bị gỡ không truy vấn vào DB đã đóng.
    openedUid = null;
    _refreshPlan();
    AvatarCache.clear();
  }

  static void _refreshPlan() {
    plan.value = effectivePlan(purchasedPlan, trialUntil, DateTime.now());
    planChanges.value++;
  }

  /// Bắt đầu dùng thử Pro $proTrialDays ngày (mỗi máy một lần) và hẹn thông
  /// báo trước khi hết hạn một ngày, để không ai bị bất ngờ.
  static Future<void> startTrial() async {
    if (trialUsed) return;
    final until = DateTime.now().add(const Duration(days: proTrialDays));
    await settings.set('pro_trial_until', until.toIso8601String());
    try {
      await _deviceTrialFile?.writeAsString(until.toIso8601String());
      _deviceTrialUsed = true;
    } catch (e) {
      debugPrint('Không ghi được cờ dùng thử: $e');
    }
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
        // Tài khoản mới luôn bắt đầu ở gói Con Nợ, không thừa hưởng gói
        // (hay dùng thử) của tài khoản vừa đăng xuất trên cùng máy.
        name: name, email: email, password: password, plan: Plan.conNo.name);
    // Tài khoản mới: bắt đầu gói Con Nợ trên sổ trống của chính mình.
    await openForUser(auth!.currentUser!.uid);
  }
}
