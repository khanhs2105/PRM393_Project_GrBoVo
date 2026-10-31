import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_services.dart';
import 'services/notification_service.dart';

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
    const seed = Color(0xFF0F9D58);
    return MaterialApp(
      title: 'GrBoVo Split',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
