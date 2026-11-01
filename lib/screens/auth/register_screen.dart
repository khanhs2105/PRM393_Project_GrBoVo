import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../logic/auth_validation.dart';
import '../../services/app_services.dart';
import 'auth_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await App.register(_name.text, _email.text, _password.text);
      // Đăng ký xong Firebase tự đăng nhập luôn; đóng màn này để lộ màn chính.
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    } catch (e) {
      if (mounted) setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Tạo tài khoản',
      subtitle: 'Hồ sơ của bạn được lưu trên Firebase.',
      showBack: true,
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  labelText: 'Tên hiển thị',
                  prefixIcon: Icon(Icons.person_outline)),
              validator: validateDisplayName,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                  labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
              validator: validateEmail,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password,
              obscureText: _hide,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                helperText: 'Ít nhất 6 ký tự, có cả chữ và số',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _hide ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
              validator: validatePassword,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirm,
              obscureText: _hide,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                  labelText: 'Nhập lại mật khẩu',
                  prefixIcon: Icon(Icons.lock_reset)),
              validator: (v) => validateConfirmPassword(v, _password.text),
            ),
            const SizedBox(height: 16),
            if (_error != null) AuthError(_error!),
            const SizedBox(height: 8),
            BusyButton(label: 'Đăng ký', busy: _busy, onPressed: _submit),
          ]),
        ),
      ),
    );
  }
}
