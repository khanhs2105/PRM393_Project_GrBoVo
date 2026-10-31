import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../logic/emv_qr_parser.dart';
import '../widgets/common.dart';

/// Quét QR ngân hàng bằng camera. Quét được thì trả về [BankAccountQr].
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _lastInvalid;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      final qr = parseBankQr(raw);
      if (qr != null) {
        _done = true;
        Navigator.pop(context, qr);
        return;
      }
      // Báo một lần cho mỗi mã sai, tránh hiện snackbar liên tục.
      if (raw != _lastInvalid) {
        _lastInvalid = raw;
        showSnack(context, 'Đây không phải mã QR chuyển khoản ngân hàng');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final box = size.width * 0.7;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Quét QR ngân hàng'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Không mở được camera (${error.errorCode.name}).\n'
                'Hãy cấp quyền camera cho app trong Cài đặt.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: box,
            height: box,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        const Positioned(
          left: 24,
          right: 24,
          bottom: 48,
          child: Text(
            'Đưa mã QR nhận tiền vào khung',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ]),
    );
  }
}
