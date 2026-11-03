import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/vnpay_sandbox.dart';
import '../widgets/common.dart';

/// Mở trang thanh toán VNPay sandbox trong app. Khi VNPay chuyển về
/// [VnpaySandbox.returnUrl], chặn lại, kiểm chữ ký và trả [VnpayResult]
/// qua [Navigator.pop]. Người dùng đóng màn này giữa chừng thì trả null.
class VnpayWebViewScreen extends StatefulWidget {
  final Uri url;
  const VnpayWebViewScreen({super.key, required this.url});

  @override
  State<VnpayWebViewScreen> createState() => _VnpayWebViewScreenState();
}

class _VnpayWebViewScreenState extends State<VnpayWebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onNavigationRequest: (req) {
          if (VnpaySandbox.isReturnUrl(req.url)) {
            _finish(Uri.parse(req.url));
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        // Một số máy chuyển trang bằng redirect không qua onNavigationRequest.
        onPageStarted: (url) {
          if (VnpaySandbox.isReturnUrl(url)) _finish(Uri.parse(url));
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted && !_done) {
            showSnack(context, 'Không tải được trang VNPay: ${e.description}');
          }
        },
      ))
      ..loadRequest(widget.url);
  }

  void _finish(Uri uri) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, VnpaySandbox.parseReturn(uri));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VNPay (sandbox)'),
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
