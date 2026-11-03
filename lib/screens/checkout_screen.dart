import 'dart:async';

import 'package:flutter/material.dart';

import '../logic/money.dart';
import '../logic/plans.dart';
import '../services/app_services.dart';
import '../services/payos.dart';
import '../services/vnpay_sandbox.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'payos_webview_screen.dart';
import 'vnpay_webview_screen.dart';

/// Màn thanh toán gói. Có ba kiểu:
/// - Qua PayOS: tạo link thanh toán, mở trang có mã VietQR, quét bằng app
///   ngân hàng. Tiền thật, vào thẳng tài khoản đã gắn với PayOS. Về lại app
///   thì hỏi PayOS trạng thái đơn, PAID mới kích hoạt gói.
/// - Qua cổng VNPay môi trường thử nghiệm (sandbox): mở trang VNPay trong
///   app, trả bằng thẻ test, VNPay báo thành công thì kích hoạt gói. Sandbox
///   không trừ tiền thật.
/// - Miễn phí (giả lập): luôn giảm 100%, không gọi cổng nào.
///
/// Trả về `true` qua [Navigator.pop] khi đã kích hoạt gói.
class CheckoutScreen extends StatefulWidget {
  final Plan plan;
  const CheckoutScreen({super.key, required this.plan});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum _Method {
  payos(
    'PayOS (VietQR)',
    'Quét mã QR bằng app ngân hàng, trừ tiền thật',
    AppIcons.qrCode,
  ),
  vnpay(
    'VNPay (sandbox)',
    'Cổng VNPay thử nghiệm, trả bằng thẻ test bên dưới',
    AppIcons.landmark,
  ),
  free(
    'Miễn phí (giả lập)',
    'Mã CONNOTHUONG giảm 100%, không gọi cổng nào',
    AppIcons.sparkles,
  );

  const _Method(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  _Method _method = PayosConfig.isConfigured
      ? _Method.payos
      : VnpayConfig.isConfigured
      ? _Method.vnpay
      : _Method.free;

  /// Đang bận (kích hoạt gói...). Chữ hiện ở thanh dưới.
  String? _busy;

  /// Đơn PayOS đang chờ ngân hàng xác nhận.
  PayosLink? _payosLink;
  String? _payosNote;
  Timer? _payosPoll;
  int _payosTries = 0;
  bool _payosChecking = false;

  @override
  void dispose() {
    _payosPoll?.cancel();
    super.dispose();
  }

  Plan get plan => widget.plan;
  bool get _isVnpay => _method == _Method.vnpay;
  bool get _isFree => _method == _Method.free;
  int get _total => _isFree ? 0 : plan.monthlyPrice;

  Future<void> _pay() async {
    switch (_method) {
      case _Method.payos:
        await _payPayos();
      case _Method.vnpay:
        await _payVnpay();
      case _Method.free:
        await _payFree();
    }
  }

  Future<void> _payPayos() async {
    if (!PayosConfig.isConfigured) {
      showSnack(context, 'Chưa điền khóa PayOS (lib/services/payos.dart).');
      return;
    }
    setState(() => _busy = 'Đang tạo mã thanh toán PayOS...');
    final PayosLink link;
    try {
      link = await Payos.createLink(
        amount: plan.monthlyPrice,
        // Không dấu, tối đa 9 ký tự để chạy được với mọi ngân hàng.
        description: 'CHIPIN',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      showSnack(context, 'Không tạo được link PayOS: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _payosLink = link;
      _payosNote = null;
    });
    await _openPayos();
  }

  /// Mở (lại) trang PayOS. Đóng trang hoặc PayOS chuyển về thì bắt đầu chờ
  /// ngân hàng xác nhận: chuyển khoản thường mất vài giây tới một phút mới
  /// được PayOS ghi nhận, hỏi ngay một lần dễ báo nhầm "chưa thanh toán".
  Future<void> _openPayos() async {
    final link = _payosLink;
    if (link == null) return;
    final ret = await Navigator.push<PayosReturn>(
      context,
      MaterialPageRoute(
        builder: (_) => PayosWebViewScreen(url: link.checkoutUrl),
      ),
    );
    if (!mounted || _payosLink != link) return;
    if (ret != null && ret.cancelled) {
      setState(() => _payosLink = null);
      showSnack(context, 'Bạn đã hủy thanh toán');
      return;
    }
    _startPayosPolling();
  }

  void _startPayosPolling() {
    _payosPoll?.cancel();
    _payosTries = 0;
    _checkPayos();
    _payosPoll = Timer.periodic(const Duration(seconds: 3), (_) {
      _payosTries++;
      if (_payosTries > 40) {
        // Khoảng 2 phút: thôi tự hỏi, để người dùng bấm "Kiểm tra lại".
        _payosPoll?.cancel();
        if (mounted) {
          setState(() => _payosNote =
              'Chưa thấy tiền về. Nếu bạn đã chuyển khoản, đợi chút rồi bấm '
              '"Kiểm tra lại".');
        }
        return;
      }
      _checkPayos();
    });
  }

  Future<void> _checkPayos({bool manual = false}) async {
    final link = _payosLink;
    if (link == null || _payosChecking) return;
    _payosChecking = true;
    String status;
    try {
      status = await Payos.getStatus(link.orderCode);
    } catch (e) {
      status = '';
      if (manual && mounted) showSnack(context, '$e');
    } finally {
      _payosChecking = false;
    }
    if (!mounted || _payosLink != link) return;
    switch (status) {
      case 'PAID':
        _payosPoll?.cancel();
        setState(() => _payosLink = null);
        await _activate(
          'Đã thanh toán ${formatVnd(plan.monthlyPrice)} qua PayOS.\n'
          'Mã đơn: ${link.orderCode}',
        );
      case 'CANCELLED' || 'EXPIRED' || 'FAILED':
        _payosPoll?.cancel();
        setState(() => _payosLink = null);
        showSnack(context,
            'Đơn ${link.orderCode} đã ${_statusText(status)}, tạo đơn mới nhé');
      default:
        if (manual) {
          setState(() => _payosNote =
              'Chưa thấy tiền về (${_statusText(status)}). Chuyển khoản xong '
              'thường mất vài giây tới một phút.');
        }
    }
  }

  static String _statusText(String s) => switch (s) {
        'PENDING' => 'đang chờ thanh toán',
        'PROCESSING' => 'đang xử lý',
        'CANCELLED' => 'bị hủy',
        'EXPIRED' => 'hết hạn',
        'FAILED' => 'thất bại',
        '' => 'không hỏi được PayOS',
        _ => s,
      };

  void _cancelPayos() {
    _payosPoll?.cancel();
    setState(() => _payosLink = null);
  }

  Future<void> _payFree() async {
    const steps = [
      'Đang kết nối ngân hàng...',
      'Đang hỏi ý kiến ví tiền của bạn...',
      'Đang áp mã giảm 100%...',
    ];
    for (final s in steps) {
      if (!mounted) return;
      setState(() => _busy = s);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    await _activate('Đã trừ: 0 ₫. Đùa thôi, miễn phí mà 😜');
  }

  Future<void> _payVnpay() async {
    if (!VnpayConfig.isConfigured) {
      showSnack(
        context,
        'Chưa điền khóa VNPay sandbox (lib/services/vnpay_sandbox.dart).',
      );
      return;
    }
    final txnRef = 'ALO${DateTime.now().millisecondsSinceEpoch}';
    final url = VnpaySandbox.buildPaymentUrl(
      amount: plan.monthlyPrice,
      // Không dấu, không ký tự đặc biệt theo khuyến nghị của VNPay.
      orderInfo: 'Nang cap goi ${plan.name} ma $txnRef',
      txnRef: txnRef,
    );
    final result = await Navigator.push<VnpayResult>(
      context,
      MaterialPageRoute(builder: (_) => VnpayWebViewScreen(url: url)),
    );
    if (!mounted || result == null) return;
    if (result.success) {
      await _activate(
        'Đã thanh toán ${formatVnd(plan.monthlyPrice)} qua '
        'VNPay sandbox (tiền thử nghiệm, không phải tiền thật).\n'
        'Ngân hàng: ${result.bankCode}\n'
        'Mã giao dịch: ${result.transactionNo}',
      );
    } else {
      showSnack(context, 'Thanh toán chưa thành công: ${result.message}');
    }
  }

  Future<void> _activate(String detail) async {
    setState(() => _busy = 'Đang kích hoạt gói...');
    try {
      await App.setPlan(plan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      showSnack(context, 'Không kích hoạt được gói, thử lại nhé ($e)');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(AppIcons.partyPopper, size: 36),
        title: const Text('Thanh toán thành công! 🎉'),
        content: Text('Bạn đã trở thành ${plan.title}.\n\n$detail'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Ngon'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final price = plan.monthlyPrice;
    final locked = _busy != null || _payosLink != null;
    return PopScope(
      canPop: _busy == null,
      child: Scaffold(
        appBar: AppBar(title: const Text('Thanh toán')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Đơn hàng', style: text.titleMedium),
                    const SizedBox(height: 12),
                    _line('Gói ${plan.title} (1 tháng)', formatVnd(price)),
                    if (_isFree)
                      _line(
                        'Mã CONNOTHUONG (giảm 100%)',
                        formatVnd(-price),
                        color: scheme.primary,
                      ),
                    const Divider(height: 24),
                    _line('Tổng thanh toán', formatVnd(_total), bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Phương thức thanh toán', style: text.titleMedium),
            const SizedBox(height: 8),
            for (final m in _Method.values)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: m == _method
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: m == _method ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  enabled: !locked,
                  leading: Icon(m.icon),
                  title: Text(m.title),
                  subtitle: Text(m.subtitle),
                  trailing: m == _method
                      ? Icon(AppIcons.circleCheck, color: scheme.primary)
                      : null,
                  onTap: () => setState(() => _method = m),
                ),
              ),
            if (_isVnpay) _testCardInfo(context),
            const SizedBox(height: 8),
            Text(switch (_method) {
              _Method.payos =>
                'PayOS trừ tiền thật: tiền chuyển vào tài '
                    'khoản ngân hàng đã gắn với PayOS.',
              _Method.vnpay =>
                'Đây là cổng VNPay môi trường thử nghiệm: '
                    'thanh toán bằng thẻ test, không trừ tiền thật.',
              _Method.free =>
                'Thanh toán giả lập cho vui: không kết nối '
                    'ngân hàng hay ví nào và không trừ tiền thật.',
            }, style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _payosLink != null && _busy == null
                ? _payosWaiting(context)
                : _busy != null
                ? Row(
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_busy!)),
                    ],
                  )
                : FilledButton.icon(
                    onPressed: _pay,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(AppIcons.lock),
                    label: Text('Thanh toán ${formatVnd(_total)}'),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _payosWaiting(BuildContext context) {
    final link = _payosLink!;
    final polling = _payosPoll?.isActive ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (polling)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(AppIcons.timer, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _payosNote ??
                    'Đang chờ ngân hàng xác nhận đơn ${link.orderCode}. '
                        'Chuyển khoản xong gói sẽ tự kích hoạt.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(onPressed: _cancelPayos, child: const Text('Hủy')),
            const Spacer(),
            OutlinedButton(
              onPressed: _openPayos,
              child: const Text('Mở lại mã QR'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => _checkPayos(manual: true),
              child: const Text('Kiểm tra lại'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _testCardInfo(BuildContext context) {
    Widget row(String k, String v) => Row(
      children: [
        SizedBox(width: 110, child: Text(k)),
        Expanded(
          child: SelectableText(
            v,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trên trang VNPay chọn "Thẻ nội địa", ngân hàng NCB, '
            'rồi nhập thẻ test:',
          ),
          const SizedBox(height: 6),
          row('Số thẻ', '9704198526191432198'),
          row('Tên chủ thẻ', 'NGUYEN VAN A'),
          row('Ngày phát hành', '07/15'),
          row('OTP', '123456'),
        ],
      ),
    );
  }

  Widget _line(String label, String value, {Color? color, bool bold = false}) {
    final style = TextStyle(
      color: color,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
