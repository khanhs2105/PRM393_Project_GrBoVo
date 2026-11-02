import 'package:flutter/material.dart';

import '../data/cloud_backup.dart';
import '../logic/auth_validation.dart';
import '../logic/plans.dart';
import '../models/user_profile.dart';
import '../services/app_services.dart';
import '../services/auth_service.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import 'jwt_screen.dart';
import '../widgets/app_icons.dart';

/// Tài khoản: hồ sơ trên Firestore, xem JWT, sao lưu/khôi phục, đăng xuất.
/// Trả về true khi dữ liệu trên máy đã thay đổi (khôi phục) để màn chính tải lại.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _auth = App.auth!;
  late final Stream<UserProfile?> _profile = _auth.profileChanges();
  bool _busy = false;
  bool _changed = false;

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

  Future<void> _backup() => _run(() async {
        final snap = await _auth.backup(App.db);
        if (mounted) {
          showSnack(context,
              'Đã sao lưu lên Firebase: ${describeBackup(snap.cast<String, dynamic>())}');
        }
      });

  Future<void> _restore() => _run(() async {
        final b = await _auth.latestBackup();
        if (!mounted) return;
        if (b == null) {
          showSnack(context, 'Chưa có bản sao lưu nào trên Firebase.');
          return;
        }
        final at = AuthService.toDate(b['createdAt']);
        final ok = await confirm(
          context,
          'Khôi phục dữ liệu?',
          'Bản sao lưu${at == null ? '' : ' lúc ${formatDateTime(at)}'} có '
              '${describeBackup(b)}.\n\nDữ liệu hiện có trên máy sẽ bị thay thế.',
          ok: 'Khôi phục',
        );
        if (!ok) return;
        await _auth.restore(App.db, b);
        _changed = true;
        if (mounted) showSnack(context, 'Đã khôi phục dữ liệu từ Firebase.');
      });

  Future<void> _signOut() async {
    final ok = await confirm(
      context,
      'Đăng xuất?',
      'Dữ liệu nhóm vẫn giữ trên máy. Nên sao lưu trước nếu muốn dùng trên máy khác.',
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
        if (!didPop) Navigator.pop(context, _changed);
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
                const SectionHeader('Hồ sơ trên Firestore'),
                Card(
                  child: Column(children: [
                    _info('UID', user?.uid ?? '-'),
                    _info('Ngày tạo',
                        p?.createdAt == null ? '-' : formatDateTime(p!.createdAt!)),
                    _info(
                        'Đăng nhập gần nhất',
                        p?.lastLoginAt == null
                            ? '-'
                            : formatDateTime(p!.lastLoginAt!)),
                    _info('Số lần đăng nhập', '${p?.loginCount ?? '-'}'),
                    _info(
                        'Sao lưu gần nhất',
                        p?.lastBackupAt == null
                            ? 'Chưa sao lưu'
                            : formatDateTime(p!.lastBackupAt!)),
                    if (snap.hasError)
                      ListTile(
                        leading: const Icon(AppIcons.cloudOff),
                        title: const Text('Không đọc được hồ sơ'),
                        subtitle: Text('${snap.error}'),
                      ),
                  ]),
                ),
                const SectionHeader('Bảo mật'),
                Card(
                  child: ListTile(
                    leading: const IconTile(AppIcons.keyRound, Color(0xFF7E57C2)),
                    title: const Text('Xem JWT (ID token)'),
                    subtitle: const Text(
                        'Token Firebase cấp khi đăng nhập, kiểm chữ ký RS256'),
                    trailing: const Icon(AppIcons.chevronRight),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const JwtScreen())),
                  ),
                ),
                const SectionHeader('Dữ liệu'),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const IconTile(
                          AppIcons.cloudUpload, Color(0xFF29B6F6)),
                      title: const Text('Sao lưu lên Firebase'),
                      subtitle: const Text('Đẩy toàn bộ nhóm, khoản chi lên Firestore'),
                      enabled: !_busy,
                      onTap: _backup,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const IconTile(
                          AppIcons.cloudDownload, Color(0xFF16946A)),
                      title: const Text('Khôi phục từ Firebase'),
                      subtitle: const Text('Lấy bản sao lưu về máy này'),
                      enabled: !_busy,
                      onTap: _restore,
                    ),
                  ]),
                ),
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

  Widget _info(String label, String value) => ListTile(
        dense: true,
        title: Text(label),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: SelectableText(value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
}

