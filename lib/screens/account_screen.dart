import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/plans.dart';
import '../models/user_profile.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';
import '../widgets/app_icons.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import '../services/friendly_error.dart';

/// Tài khoản: ảnh đại diện, tên, email, gói, sửa hồ sơ, đổi mật khẩu, đăng xuất.
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
      if (mounted) showSnack(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Giữ MemoryImage theo chuỗi base64 để ảnh không nháy lại mỗi lần build.
  String? _avatarKey;
  MemoryImage? _avatarImage;

  MemoryImage? _avatarFor(UserProfile? p) {
    final key = p?.avatarBase64;
    if (key != _avatarKey) {
      _avatarKey = key;
      final bytes = p?.avatarBytes;
      _avatarImage = bytes == null ? null : MemoryImage(bytes);
    }
    return _avatarImage;
  }

  Future<void> _changeAvatar(bool hasAvatar) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(AppIcons.camera),
            title: const Text('Chụp ảnh'),
            onTap: () => Navigator.pop(ctx, 'camera'),
          ),
          ListTile(
            leading: const Icon(AppIcons.images),
            title: const Text('Chọn từ thư viện'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (hasAvatar)
            ListTile(
              leading: Icon(AppIcons.trash2,
                  color: Theme.of(ctx).colorScheme.error),
              title: const Text('Xóa ảnh đại diện'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'remove') {
      await _run(() => _auth.updateAvatar(null));
      return;
    }
    // Thu nhỏ còn 256px, nén JPEG để lưu thẳng vào Firestore (vài chục KB).
    final picked = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 70,
      preferredCameraDevice: CameraDevice.front,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _run(() async {
      await _auth.updateAvatar(bytes);
      if (mounted) showSnack(context, 'Đã cập nhật ảnh đại diện');
    });
  }

  Future<void> _editProfile(UserProfile? p) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => EditProfileScreen(profile: p)));

  Future<void> _changePassword() => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));

  Future<void> _signOut() async {
    final ok = await confirm(
      context,
      'Đăng xuất?',
      'Dữ liệu nhóm vẫn giữ trên máy.',
      ok: 'Đăng xuất',
    );
    if (!ok || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await App.signOut();
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
            final avatar = _avatarFor(p);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                GradientPanel(
                  child: Row(children: [
                    GestureDetector(
                      onTap: _busy ? null : () => _changeAvatar(avatar != null),
                      child: Stack(clipBehavior: Clip.none, children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: Colors.white,
                          backgroundImage: avatar,
                          child: avatar != null
                              ? null
                              : Text(
                                  name.isEmpty
                                      ? '?'
                                      : name.characters.first.toUpperCase(),
                                  style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFFF4D6D)),
                                ),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 4),
                              ],
                            ),
                            child: const Icon(AppIcons.camera,
                                size: 14, color: Color(0xFFFF4D6D)),
                          ),
                        ),
                      ]),
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
                  ]),
                ),
                if (_busy) const LinearProgressIndicator(),
                const SectionHeader('Tài khoản'),
                Card(
                  child: Column(children: [
                    ListTile(
                      leading: const IconTile(AppIcons.user, Color(0xFFFF8A3D)),
                      title: const Text('Chỉnh sửa hồ sơ'),
                      subtitle: Text((p?.phone ?? '').isEmpty
                          ? 'Tên hiển thị, số điện thoại'
                          : p!.phone!),
                      trailing: const Icon(AppIcons.chevronRight),
                      enabled: !_busy,
                      onTap: () => _editProfile(p),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading:
                          const IconTile(AppIcons.lock, Color(0xFF7E57C2)),
                      title: const Text('Đổi mật khẩu'),
                      trailing: const Icon(AppIcons.chevronRight),
                      enabled: !_busy,
                      onTap: _changePassword,
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
}
