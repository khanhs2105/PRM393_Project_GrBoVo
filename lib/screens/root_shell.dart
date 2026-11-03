import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../widgets/app_icons.dart';
import '../widgets/pro_prompts.dart';
import 'account_screen.dart';
import 'activity_screen.dart';
import 'group_form_screen.dart';
import 'home_screen.dart';
import 'plans_screen.dart';

/// Khung chính có thanh điều hướng dưới đáy:
/// Nhóm, Hoạt động, [+ tạo nhóm nhanh], Gói, Hồ sơ.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  /// Vị trí của nút "+" trên thanh dưới; không phải một tab.
  static const _plusSlot = 2;

  int _index = 0;

  /// Tăng lên để màn Nhóm tải lại sau khi tạo nhóm từ nút "+".
  int _homeVersion = 0;

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

  Future<void> _quickCreateGroup() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const GroupFormScreen()),
    );
    if (created != true || !mounted) return;
    setState(() {
      _index = 0;
      _homeVersion++;
    });
    await afterResult(context);
  }

  void _onSelect(int i) {
    if (i == _plusSlot) {
      _quickCreateGroup();
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    // Mỗi lần đổi tab thì dựng lại màn đó để số liệu luôn mới.
    final page = switch (_index) {
      1 => const ActivityScreen(),
      3 => const PlansScreen(),
      4 => const AccountScreen(),
      _ => HomeScreen(key: ValueKey(_homeVersion)),
    };
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: page,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onSelect,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            const NavigationDestination(
              icon: Icon(AppIcons.house),
              label: 'Nhóm',
            ),
            const NavigationDestination(
              icon: Icon(AppIcons.history),
              label: 'Hoạt động',
            ),
            NavigationDestination(
              tooltip: 'Tạo nhóm nhanh',
              icon: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.plus, color: scheme.onPrimary, size: 26),
              ),
              label: '',
            ),
            const NavigationDestination(
              icon: Icon(AppIcons.crown),
              label: 'Gói',
            ),
            const NavigationDestination(
              icon: Icon(AppIcons.circleUser),
              label: 'Hồ sơ',
            ),
          ],
        ),
      ),
    );
  }
}
