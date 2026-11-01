import 'package:flutter/material.dart';

import '../../widgets/ui.dart';
import '../../widgets/app_icons.dart';

/// Khung chung cho màn đăng nhập/đăng ký: đầu trang gradient có logo.
class AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool showBack;
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showBack = false,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showBack)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: 'Quay lại',
                          icon: const Icon(AppIcons.arrowLeft),
                          onPressed: () => Navigator.maybePop(context),
                        ),
                      ),
                    GradientPanel(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Image.asset('assets/brand/chipin_logo.png',
                              width: 48, height: 48),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Alo, Trả Tiền!',
                                    style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w800)),
                                Text(subtitle,
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.9))),
                              ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 28),
                    Text(title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 16),
                    child,
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Khung báo lỗi màu đỏ nhạt.
class AuthError extends StatelessWidget {
  final String text;
  const AuthError(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(AppIcons.circleAlert, color: scheme.onErrorContainer),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text, style: TextStyle(color: scheme.onErrorContainer))),
      ]),
    );
  }
}

/// Nút chính hiện vòng xoay khi đang xử lý.
class BusyButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onPressed;
  const BusyButton(
      {super.key,
      required this.label,
      required this.busy,
      required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5))
          : Text(label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}
