import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/payos.dart';
import '../widgets/common.dart';

/// Mở trang thanh toán PayOS (mã VietQR) trong app. Khi PayOS chuyển về
/// [Payos.returnUrl] hoặc [Payos.cancelUrl], chặn lại và trả [PayosReturn]
/// qua [Navigator.pop]. Người dùng đóng màn này giữa chừng thì trả null.
class PayosWebViewScreen extends StatefulWidget {
  final Uri url;
  const PayosWebViewScreen({super.key, required this.url});

  @override
  State<PayosWebViewScreen> createState() => _PayosWebViewScreenState();
}

class _PayosWebViewScreenState extends State<PayosWebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onNavigationRequest: (req) {
            if (Payos.isResultUrl(req.url)) {
              _finish(Uri.parse(req.url));
              return NavigationDecision.prevent;
            }
            // Nút "mở app ngân hàng" trên trang PayOS dùng link riêng của
            // từng ngân hàng (không phải http): WebView không mở được, phải
            // nhờ Android mở app ngân hàng.
            final uri = Uri.tryParse(req.url);
            if (uri != null && uri.scheme != 'http' && uri.scheme != 'https') {
              _openExternal(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          // Một số máy chuyển trang bằng redirect không qua onNavigationRequest.
          onPageStarted: (url) {
            if (Payos.isResultUrl(url)) _finish(Uri.parse(url));
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted && !_done) {
              showSnack(
                context,
                'Không tải được trang PayOS: ${e.description}',
              );
            }
          },
        ),
      )
      ..loadRequest(widget.url);
  }

  Future<void> _openExternal(Uri uri) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      showSnack(
        context,
        'Không mở được app ngân hàng. Hãy chụp màn hình mã QR rồi quét '
        'bằng app ngân hàng của bạn.',
      );
    }
  }

  void _finish(Uri uri) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, Payos.parseReturn(uri));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PayOS (VietQR)'),
        actions: [
          // Chuyển khoản bằng app ngân hàng xong thì bấm để về app kiểm tra.
          TextButton(
            onPressed: () {
              if (_done) return;
              _done = true;
              Navigator.pop(context);
            },
            child: const Text('Đã chuyển khoản'),
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
