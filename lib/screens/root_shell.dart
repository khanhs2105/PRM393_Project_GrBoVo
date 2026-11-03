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
          color: Theme.of(context).navigationBarTheme.backgroundColor ??
              scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(children: [
              _tab(0, AppIcons.house, 'Nhóm'),
              _tab(1, AppIcons.history, 'Hoạt động'),
              Expanded(
                child: Center(
                  child: Tooltip(
                    message: 'Tạo nhóm nhanh',
                    child: Material(
                      color: scheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => _onSelect(_plusSlot),
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(AppIcons.plus,
                              color: scheme.onPrimary, size: 24),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _tab(3, AppIcons.crown, 'Gói'),
              _tab(4, AppIcons.circleUser, 'Hồ sơ'),
            ]),
          ),
        ),
      ),
    );
  }

  /// Một ô tab: icon trên, chữ một dòng bên dưới, tất cả căn giữa.
  Widget _tab(int i, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _index == i;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: () => _onSelect(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 30,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.surfaceContainerHighest
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 4),
            // Máy hẹp thì thu nhỏ chữ chứ không xuống dòng.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
