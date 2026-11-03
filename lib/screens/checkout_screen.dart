import 'package:flutter/material.dart';

import '../logic/money.dart';
import '../logic/plans.dart';
import '../services/app_services.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';

/// Màn thanh toán GIẢ cho các gói troll: chọn phương thức, bấm thanh toán,
/// chờ "xử lý" một chút rồi báo thành công và kích hoạt gói. Không gọi cổng
/// thanh toán nào, không trừ đồng nào: luôn được giảm 100%.
///
/// Trả về `true` qua [Navigator.pop] khi đã kích hoạt gói.
class CheckoutScreen extends StatefulWidget {
  final Plan plan;
  const CheckoutScreen({super.key, required this.plan});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _PayMethod {
  final String title;
  final String subtitle;
  final IconData icon;
  const _PayMethod(this.title, this.subtitle, this.icon);
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const _methods = [
    _PayMethod('Ví điện tử', 'Liên kết ví, trừ 0 ₫', AppIcons.wallet),
    _PayMethod('Thẻ ATM / Visa', 'Thẻ của bạn, không phải thẻ của bạn bè',
        AppIcons.landmark),
    _PayMethod('Quét mã QR', 'Quét xong cũng không mất gì', AppIcons.qrCode),
    _PayMethod('Ghi nợ, trả sau', 'Đúng chất app chia tiền 😏',
        AppIcons.notebookPen),
  ];

  static const _steps = [
    'Đang kết nối ngân hàng...',
    'Đang hỏi ý kiến ví tiền của bạn...',
    'Đang áp mã giảm 100%...',
  ];

  int _method = 0;
  bool _paying = false;
  int _step = 0;

  Plan get plan => widget.plan;

  Future<void> _pay() async {
    setState(() {
      _paying = true;
      _step = 0;
    });
    // Giả lập vài bước xử lý cho giống thanh toán thật.
    for (var i = 0; i < _steps.length; i++) {
      if (!mounted) return;
      setState(() => _step = i);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    try {
      await App.setPlan(plan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _paying = false);
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
        content: Text('Bạn đã trở thành ${plan.title}.\n\n'
            'Phương thức: ${_methods[_method].title}\n'
            'Đã trừ: 0 ₫. Đùa thôi, miễn phí mà 😜'),
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
    return PopScope(
      // Đang "trừ tiền" thì không cho thoát giữa chừng.
      canPop: !_paying,
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
                    _line('Mã CONNOTHUONG (giảm 100%)', formatVnd(-price),
                        color: scheme.primary),
                    const Divider(height: 24),
                    _line('Tổng thanh toán', formatVnd(0), bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Phương thức thanh toán', style: text.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < _methods.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: i == _method ? scheme.primary : scheme.outlineVariant,
                    width: i == _method ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  enabled: !_paying,
                  leading: Icon(_methods[i].icon),
                  title: Text(_methods[i].title),
                  subtitle: Text(_methods[i].subtitle),
                  trailing: i == _method
                      ? Icon(AppIcons.circleCheck, color: scheme.primary)
                      : null,
                  onTap: () => setState(() => _method = i),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Đây là thanh toán giả lập cho vui: app không kết nối ngân hàng '
              'hay ví nào và không bao giờ trừ tiền thật.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _paying
                ? Row(children: [
                    const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_steps[_step])),
                  ])
                : FilledButton.icon(
                    onPressed: _pay,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                    icon: const Icon(AppIcons.lock),
                    label: Text('Thanh toán ${formatVnd(0)}'),
                  ),
          ),
        ),
      ),
    );
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
