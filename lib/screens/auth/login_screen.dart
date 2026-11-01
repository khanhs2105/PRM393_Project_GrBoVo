import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../logic/auth_validation.dart';
import '../../services/app_services.dart';
import '../../widgets/common.dart';
import 'auth_widgets.dart';
import 'register_screen.dart';

/// Màn đăng nhập. Đăng nhập xong, AuthGate trong main.dart tự chuyển sang
/// màn chính nhờ lắng nghe authStateChanges().
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await App.signIn(_email.text, _password.text);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    } catch (e) {
      if (mounted) setState(() => _error = 'Có lỗi xảy ra: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final err = validateEmail(_email.text);
    if (err != null) {
      setState(() => _error = 'Nhập email ở trên trước rồi bấm "Quên mật khẩu".');
      return;
    }
    try {
      await App.auth!.sendPasswordReset(_email.text);
      if (mounted) {
        showSnack(context, 'Đã gửi email đặt lại mật khẩu tới ${_email.text.trim()}');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = authErrorMessage(e.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Đăng nhập',
      subtitle: 'Chia tiền nhóm, nhắc nợ không ngại.',
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _hide ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
              validator: (v) =>
                  (v ?? '').isEmpty ? 'Nhập mật khẩu' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: _busy ? null : _forgot,
                  child: const Text('Quên mật khẩu?')),
            ),
            if (_error != null) AuthError(_error!),
            const SizedBox(height: 8),
            BusyButton(label: 'Đăng nhập', busy: _busy, onPressed: _submit),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Chưa có tài khoản?'),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen())),
                child: const Text('Đăng ký'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
