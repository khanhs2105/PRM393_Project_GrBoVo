import 'package:flutter/material.dart';

import '../logic/auth_validation.dart';
import '../models/user_profile.dart';
import '../services/app_services.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'auth/auth_widgets.dart';
import '../services/friendly_error.dart';

/// Sửa tên hiển thị và số điện thoại. Email không sửa ở đây.
class EditProfileScreen extends StatefulWidget {
  final UserProfile? profile;
  const EditProfileScreen({super.key, this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
      text: widget.profile?.displayName.isNotEmpty == true
          ? widget.profile!.displayName
          : (App.auth?.currentUser?.displayName ?? ''));
  late final _phone = TextEditingController(text: widget.profile?.phone ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await App.auth!.updateProfile(
        name: _name.text,
        phone: _phone.text.replaceAll(RegExp(r'[\s.-]'), ''),
      );
      // Đổi tên ở các sổ chung đã tham gia để chủ sổ thấy tên mới.
      await App.shared?.renameMe(_name.text.trim());
      if (!mounted) return;
      showSnack(context, 'Đã lưu hồ sơ');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không lưu được: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.profile?.email ?? App.auth?.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Chỉnh sửa hồ sơ')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  labelText: 'Tên hiển thị', prefixIcon: Icon(AppIcons.user)),
              validator: validateDisplayName,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                  labelText: 'Số điện thoại (không bắt buộc)',
                  prefixIcon: Icon(AppIcons.smartphone)),
              validator: validatePhone,
            ),
            const SizedBox(height: 14),
            TextFormField(
              initialValue: email,
              enabled: false,
              decoration: const InputDecoration(
                  labelText: 'Email (không đổi được)',
                  prefixIcon: Icon(AppIcons.mail)),
            ),
            const SizedBox(height: 20),
            if (_error != null) AuthError(_error!),
            BusyButton(label: 'Lưu', busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
