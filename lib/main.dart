import 'package:flutter/material.dart';

import 'screens/root_shell.dart';
import 'services/app_services.dart';
import 'services/notification_service.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const RootShell(),
    );
  }
}
