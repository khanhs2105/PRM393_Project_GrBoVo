import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../widgets/app_icons.dart';
import 'activity_screen.dart';
import 'home_screen.dart';
import 'plans_screen.dart';

/// Khung chính có thanh điều hướng dưới đáy: Nhóm, Hoạt động, Gói.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Nghe nhắc nợ từ chủ các sổ chung mình đang tham gia.
    App.shared?.startInbox();
  }

  @override
  void dispose() {
    App.shared?.stopInbox();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mỗi lần đổi tab thì dựng lại màn đó để số liệu luôn mới.
    final page = switch (_index) {
      1 => const ActivityScreen(),
      2 => const PlansScreen(),
      _ => const HomeScreen(),
    };
    final border = Theme.of(context).colorScheme.outlineVariant;
    return Scaffold(
      body: page,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(icon: Icon(AppIcons.house), label: 'Nhóm'),
            NavigationDestination(
                icon: Icon(AppIcons.history), label: 'Hoạt động'),
            NavigationDestination(icon: Icon(AppIcons.crown), label: 'Gói'),
          ],
        ),
      ),
    );
  }
}
