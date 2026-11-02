import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../logic/plans.dart';
import '../models/member.dart';
import '../screens/plans_screen.dart';
import 'common.dart';
import 'app_icons.dart';

/// "Lắc để chọn người bao": dùng gia tốc kế, lắc điện thoại thì random
/// một thành viên. Chỉ có ở gói Đòi Nợ Thuê.
Future<void> showShakePicker(
    BuildContext context, List<Member> members, Plan plan) async {
  if (members.length < 2) {
    showSnack(context, 'Cần ít nhất 2 thành viên để lắc chọn người bao.');
    return;
  }
  if (!plan.canShakeToPick) {
    final go = await confirm(context, 'Tính năng VIP 😈',
        'Lắc để chọn người bao chỉ có ở gói Đòi Nợ Thuê.',
        ok: 'Xem các gói');
    if (go && context.mounted) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => const PlansScreen()));
    }
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _ShakeDialog(members: members),
  );
}

class _ShakeDialog extends StatefulWidget {
  final List<Member> members;
  const _ShakeDialog({required this.members});

  @override
  State<_ShakeDialog> createState() => _ShakeDialogState();
}

class _ShakeDialogState extends State<_ShakeDialog> {
  /// Gia tốc (m/s², đã trừ trọng lực) vượt ngưỡng này thì coi là lắc.
  static const _threshold = 12.0;

  StreamSubscription<UserAccelerometerEvent>? _sub;
  final _random = Random();
  Timer? _spin;
  String? _current;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _sub = userAccelerometerEventStream().listen((e) {
      final g = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
      if (g > _threshold && _spin == null) _start();
    }, onError: (Object e) {
      // Máy không có cảm biến: dùng nút "Không lắc được?" thay thế.
      debugPrint('Không đọc được cảm biến: $e');
    });
  }

  /// Quay tên liên tục khoảng 2 giây rồi dừng ở một người.
  void _start() {
    HapticFeedback.heavyImpact();
    var ticks = 0;
    _spin = Timer.periodic(const Duration(milliseconds: 90), (timer) {
      ticks++;
      setState(() =>
          _current = widget.members[_random.nextInt(widget.members.length)].name);
      if (ticks >= 22) {
        timer.cancel();
        HapticFeedback.vibrate();
        setState(() => _finished = true);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _spin?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ai bao bữa này?'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_current == null) ...[
          const Icon(AppIcons.vibrate, size: 64),
          const SizedBox(height: 12),
          const Text('Lắc mạnh điện thoại đi!', textAlign: TextAlign.center),
        ] else ...[
          MemberAvatar(_current!, radius: 36),
          const SizedBox(height: 12),
          Text(_current!,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (_finished)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Chúc mừng, bạn được vinh dự bao cả nhóm 🎉',
                  textAlign: TextAlign.center),
            ),
        ],
      ]),
      actions: [
        if (_spin == null)
          // Emulator không lắc được nên có nút bấm thay.
          TextButton(onPressed: _start, child: const Text('Không lắc được?')),
        if (_finished)
          TextButton(
            onPressed: () => setState(() {
              _spin = null;
              _current = null;
              _finished = false;
            }),
            child: const Text('Lắc lại'),
          ),
        FilledButton(
            onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
      ],
    );
  }
}
