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
      title: 'Chipin',
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
        // key theo uid: đổi tài khoản thì màn chính tạo lại từ đầu.
        return RootShell(key: ValueKey(user.uid));
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
