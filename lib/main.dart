import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
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
      title: 'GrBoVo Split',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const HomeScreen(),
    );
  }
}
