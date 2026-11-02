import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../logic/auth_validation.dart';
import '../services/app_services.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'auth/auth_widgets.dart';

/// Đổi mật khẩu: nhập mật khẩu hiện tại (Firebase bắt xác thực lại) rồi
/// mật khẩu mới hai lần.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await App.auth!.changePassword(
          currentPassword: _current.text, newPassword: _new.text);
      if (!mounted) return;
      showSnack(context, 'Đã đổi mật khẩu');
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      final wrongOld = e.code == 'wrong-password' ||
          e.code == 'invalid-credential' ||
          e.code == 'INVALID_LOGIN_CREDENTIALS';
      if (mounted) {
        setState(() => _error = wrongOld
            ? 'Mật khẩu hiện tại không đúng.'
            : authErrorMessage(e.code));
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _deco(String label, IconData icon, {String? helper}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          tooltip: _hide ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
          icon: Icon(_hide ? AppIcons.eye : AppIcons.eyeOff),
          onPressed: () => setState(() => _hide = !_hide),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đổi mật khẩu')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _current,
              obscureText: _hide,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.password],
              decoration: _deco('Mật khẩu hiện tại', AppIcons.lock),
              validator: (v) =>
                  (v ?? '').isEmpty ? 'Nhập mật khẩu hiện tại' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _new,
              obscureText: _hide,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              decoration: _deco('Mật khẩu mới', AppIcons.keyRound,
                  helper: 'Ít nhất 6 ký tự, có cả chữ và số'),
              validator: (v) => validateNewPassword(v, _current.text),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirm,
              obscureText: _hide,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              decoration: _deco('Nhập lại mật khẩu mới', AppIcons.keyRound),
              validator: (v) => validateConfirmPassword(v, _new.text),
            ),
            const SizedBox(height: 20),
            if (_error != null) AuthError(_error!),
            BusyButton(label: 'Đổi mật khẩu', busy: _busy, onPressed: _save),
          ],
        ),
      ),
    );
  }
}
