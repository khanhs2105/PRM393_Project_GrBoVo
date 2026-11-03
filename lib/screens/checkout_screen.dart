import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/money.dart';
import '../logic/plans.dart';
import '../services/app_services.dart';
import '../services/momo_sandbox.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';

/// Màn thanh toán gói. Có hai kiểu:
/// - Qua cổng MoMo môi trường thử nghiệm (sandbox): tạo đơn thật trên
///   test-payment.momo.vn, mở trang thanh toán, app tự hỏi trạng thái đơn và
///   kích hoạt gói khi MoMo báo thành công. Sandbox không trừ tiền thật.
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
  momo('MoMo (sandbox)',
      'Cổng MoMo thử nghiệm: thẻ ATM test, QR ví, thẻ quốc tế', AppIcons.wallet),
  free('Miễn phí (giả lập)', 'Mã CONNOTHUONG giảm 100%, không gọi cổng nào',
      AppIcons.sparkles);

  const _Method(this.title, this.subtitle, this.icon);
  final String title;
  final String subtitle;
  final IconData icon;

  bool get isMomo => this != _Method.free;
}

class _CheckoutScreenState extends State<CheckoutScreen>
    with WidgetsBindingObserver {
  _Method _method = _Method.momo;

  /// Đang bận (tạo đơn, kích hoạt gói...). Chữ hiện ở thanh dưới.
  String? _busy;

  /// Đơn MoMo đang chờ người dùng thanh toán trên trang MoMo.
  MomoOrder? _order;
  Timer? _poll;
  bool _checking = false;

  Plan get plan => widget.plan;
  int get _total => _method.isMomo ? plan.monthlyPrice : 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Thanh toán xong trên trình duyệt quay lại app: hỏi MoMo ngay.
    if (state == AppLifecycleState.resumed && _order != null) _check();
  }

  Future<void> _pay() async {
    if (_method.isMomo) {
      await _payMomo();
    } else {
      await _payFree();
    }
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

  Future<void> _payMomo() async {
    setState(() => _busy = 'Đang tạo đơn trên MoMo...');
    final MomoOrder order;
    try {
      order = await MomoSandbox.create(
        amount: plan.monthlyPrice,
        orderInfo: 'Nang cap goi ${plan.name} - Alo Tra Tien',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      await _offerFree('$e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = null;
      _order = order;
    });
    await _openPayPage();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  Future<void> _openPayPage() async {
    final order = _order;
    if (order == null) return;
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(order.payUrl),
          mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: order.payUrl));
      if (mounted) {
        showSnack(context,
            'Không mở được trình duyệt. Đã chép link thanh toán, dán vào Chrome nhé.');
      }
    }
  }

  /// Hỏi MoMo trạng thái đơn đang chờ.
  Future<void> _check({bool manual = false}) async {
    final order = _order;
    if (order == null || _checking) return;
    _checking = true;
    try {
      final code = await MomoSandbox.query(order);
      if (!mounted || _order != order) return;
      if (code == 0) {
        _poll?.cancel();
        setState(() => _order = null);
        await _activate('Đã thanh toán ${formatVnd(plan.monthlyPrice)} qua '
            'MoMo sandbox (tiền thử nghiệm, không phải tiền thật).\n'
            'Mã đơn: ${order.orderId}');
      } else if (MomoSandbox.isPending(code)) {
        if (manual) showSnack(context, 'MoMo chưa nhận được tiền, chờ chút nhé');
      } else {
        _poll?.cancel();
        setState(() => _order = null);
        showSnack(context,
            'Thanh toán MoMo không thành công hoặc đã hủy (mã $code). Thử lại nhé.');
      }
    } catch (e) {
      if (manual && mounted) showSnack(context, 'Không hỏi được MoMo: $e');
    } finally {
      _checking = false;
    }
  }

  /// MoMo sandbox từ chối tạo đơn (thường là mã 99 do MoMo tắt khóa mẫu):
  /// báo rõ và cho chuyển sang thanh toán giả lập để vẫn mua được gói.
  Future<void> _offerFree(String error) async {
    final useFree = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MoMo sandbox đang từ chối'),
        content: Text('Cổng thử nghiệm của MoMo không nhận đơn lúc này:\n'
            '$error\n\nBạn có thể thử lại sau, hoặc dùng thanh toán giả '
            'lập (miễn phí) để kích hoạt gói ngay.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Thử lại sau')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Dùng miễn phí')),
        ],
      ),
    );
    if (useFree == true && mounted) {
      setState(() => _method = _Method.free);
      await _payFree();
    }
  }

  void _cancelOrder() {
    _poll?.cancel();
    setState(() => _order = null);
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Ngon')),
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
    final locked = _busy != null || _order != null;
    return PopScope(
      // Đang tạo đơn / kích hoạt thì không cho thoát giữa chừng.
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
                    if (!_method.isMomo)
                      _line('Mã CONNOTHUONG (giảm 100%)', formatVnd(-price),
                          color: scheme.primary),
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
                    color: m == _method ? scheme.primary : scheme.outlineVariant,
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
            if (_method == _Method.momo) _testCardInfo(context),
            const SizedBox(height: 8),
            Text(
              _method.isMomo
                  ? 'Đây là cổng MoMo môi trường thử nghiệm: thanh toán bằng '
                      'thẻ/ví test, không trừ tiền thật.'
                  : 'Thanh toán giả lập cho vui: không kết nối ngân hàng hay '
                      'ví nào và không trừ tiền thật.',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _bottom(context),
          ),
        ),
      ),
    );
  }

  Widget _bottom(BuildContext context) {
    if (_busy != null) {
      return Row(children: [
        const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: 12),
        Expanded(child: Text(_busy!)),
      ]);
    }
    if (_order != null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Row(children: [
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Expanded(
              child: Text('Đang chờ MoMo xác nhận. Thanh toán xong quay lại '
                  'app, gói sẽ tự kích hoạt.')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          TextButton(onPressed: _cancelOrder, child: const Text('Hủy')),
          const Spacer(),
          OutlinedButton(
              onPressed: _openPayPage, child: const Text('Mở lại trang MoMo')),
          const SizedBox(width: 8),
          FilledButton(
              onPressed: () => _check(manual: true),
              child: const Text('Kiểm tra')),
        ]),
      ]);
    }
    return FilledButton.icon(
      onPressed: _pay,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      icon: const Icon(AppIcons.lock),
      label: Text('Thanh toán ${formatVnd(_total)}'),
    );
  }

  Widget _testCardInfo(BuildContext context) {
    Widget row(String k, String v) => Row(children: [
          SizedBox(width: 110, child: Text(k)),
          Expanded(
              child: SelectableText(v,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]);
    return _Note.child(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Trên trang MoMo chọn "Thẻ ATM" và nhập thẻ test '
            '(chọn ngân hàng NCB nếu được hỏi). Quét QR thì cần app MoMo '
            'bản thử nghiệm.'),
        const SizedBox(height: 6),
        row('Số thẻ', '9704 0000 0000 0018'),
        row('Tên chủ thẻ', 'NGUYEN VAN A'),
        row('Ngày phát hành', '03/07'),
        row('OTP', 'OTP'),
      ],
    ));
  }

  Widget _line(String label, String value, {Color? color, bool bold = false}) {
    final style = TextStyle(
        color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  final Widget content;
  const _Note._(this.content);
  factory _Note(String text) => _Note._(Text(text));
  factory _Note.child(Widget child) => _Note._(child);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: content,
    );
  }
}
