import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'screens/auth/login_screen.dart';
import 'screens/root_shell.dart';
import 'services/app_services.dart';
import 'services/notification_service.dart';
import 'theme.dart';
import 'widgets/app_icons.dart';
import 'widgets/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await App.initFirebase();
  await App.init();
  await NotificationService.init();
  runApp(const ChiaTienApp());
}

class ChiaTienApp extends StatelessWidget {
  const ChiaTienApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Chạm vào chỗ trống bất kỳ ngoài ô nhập thì ẩn bàn phím.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      title: 'Alo, Trả Tiền!',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const AuthGate(),
    );
  }
}

/// Chưa đăng nhập thì hiện màn đăng nhập, đăng nhập rồi thì vào màn chính.
/// Firebase Auth tự lưu phiên nên mở lại app không phải đăng nhập lại.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = App.auth;
    if (auth == null) return const _FirebaseMissing();
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      initialData: auth.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return const LoginScreen();
        // key theo uid: đổi tài khoản thì mở dữ liệu của tài khoản đó và
        // tạo lại màn chính từ đầu.
        return _UserData(key: ValueKey(user.uid), uid: user.uid);
      },
    );
  }
}

/// Mở dữ liệu trên máy của tài khoản [uid] rồi mới vào màn chính.
class _UserData extends StatefulWidget {
  final String uid;
  const _UserData({super.key, required this.uid});

  @override
  State<_UserData> createState() => _UserDataState();
}

class _UserDataState extends State<_UserData> {
  late Future<void> _ready = _open();

  Future<void> _open() =>
      App.openForUser(widget.uid, claimLegacy: _askClaimLegacy);

  /// Bản cũ để dữ liệu mọi tài khoản chung một file. Hỏi trước khi giao
  /// file đó cho tài khoản này, vì có thể là dữ liệu của người khác.
  Future<bool> _askClaimLegacy() async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Có dữ liệu cũ trên máy'),
        content: const Text(
            'Máy này còn dữ liệu nhóm từ bản trước (khi chưa tách dữ liệu '
            'theo tài khoản). Đây có phải dữ liệu của bạn không?\n\n'
            'Chọn "Không" nếu máy dùng chung: bạn bắt đầu với sổ trống, dữ '
            'liệu cũ vẫn để nguyên cho người kia.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Không')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Của tôi, nhận vào')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                EmptyState(
                  icon: AppIcons.circleAlert,
                  title: 'Không mở được dữ liệu',
                  message: '${snap.error}',
                  actionLabel: 'Thử lại',
                  onAction: () => setState(() => _ready = _open()),
                ),
                TextButton(
                  onPressed: App.signOut,
                  child: const Text('Đăng xuất'),
                ),
              ],
            ),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        return const RootShell();
      },
    );
  }
}

class _FirebaseMissing extends StatelessWidget {
  const _FirebaseMissing();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EmptyState(
        icon: AppIcons.cloudOff,
        title: 'Chưa kết nối được Firebase',
        message: 'Kiểm tra file android/app/google-services.json '
            '(xem docs/firebase-setup.md).\n\n${App.firebaseError}',
      ),
    );
  }
}
