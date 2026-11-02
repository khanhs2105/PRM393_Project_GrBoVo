import 'package:flutter/material.dart';

import '../logic/auth_validation.dart';
import '../logic/plans.dart';
import '../models/user_profile.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import '../widgets/app_icons.dart';

/// Tài khoản: tên, email, gói, đổi tên, đăng xuất.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _auth = App.auth!;
  late final Stream<UserProfile?> _profile = _auth.profileChanges();
  bool _busy = false;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) showSnack(context, 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(String current) async {
    final c = TextEditingController(text: current);
    final key = GlobalKey<FormState>();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên hiển thị'),
        content: Form(
          key: key,
          child: TextFormField(
              controller: c, autofocus: true, validator: validateDisplayName),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
              onPressed: () {
                if (key.currentState!.validate()) Navigator.pop(ctx, c.text);
              },
              child: const Text('Lưu')),
        ],
      ),
    );
    if (name == null) return;
    await _run(() => _auth.updateDisplayName(name));
  }

  Future<void> _signOut() async {
    final ok = await confirm(
      context,
      'Đăng xuất?',
      'Dữ liệu nhóm vẫn giữ trên máy.',
      ok: 'Đăng xuất',
    );
    if (!ok || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await _auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, false);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Tài khoản')),
        body: StreamBuilder<UserProfile?>(
          stream: _profile,
          builder: (context, snap) {
            final p = snap.data;
            final name = (p?.displayName.isNotEmpty ?? false)
                ? p!.displayName
                : (user?.displayName ?? 'Bạn');
            final email = p?.email ?? user?.email ?? '';
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                GradientPanel(
                  child: Row(children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.white,
                      child: Text(
                        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFF4D6D)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w800)),
                            Text(email,
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.9))),
                            const SizedBox(height: 6),
                            ValueListenableBuilder<Plan>(
                              valueListenable: App.plan,
                              builder: (ctx, plan, _) => Text(
                                  'Gói: ${plan.title}${App.onTrial ? ' (dùng thử)' : ''}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                          ]),
                    ),
                    IconButton(
                      tooltip: 'Đổi tên',
                      icon: const Icon(AppIcons.pencil),
                      onPressed: _busy ? null : () => _rename(name),
                    ),
                  ]),
                ),
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: _busy ? null : _signOut,
                  icon: const Icon(AppIcons.logOut),
                  label: const Text('Đăng xuất'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
