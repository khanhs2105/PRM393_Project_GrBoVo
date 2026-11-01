import 'dart:math';

import 'package:flutter/material.dart';

import '../logic/plans.dart';
import '../services/app_services.dart';
import '../widgets/app_icons.dart';

/// Màn chọn gói. Không có thanh toán thật, nút mua sẽ chạy trốn vài lần
/// rồi mới chịu cho bấm.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nâng cấp')),
      body: ValueListenableBuilder<Plan>(
        valueListenable: App.plan,
        builder: (context, current, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Chọn đẳng cấp đòi nợ của bạn',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Không tốn đồng nào thật. Đây là app chia tiền, '
                'không phải app lấy tiền 😌'),
            const SizedBox(height: 16),
            for (final plan in Plan.values)
              _PlanCard(plan: plan, isCurrent: plan == current),
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool isCurrent;
  const _PlanCard({required this.plan, required this.isCurrent});

  static const _emoji = {
    Plan.conNo: '🥲',
    Plan.chuNo: '😎',
    Plan.doiNoThue: '😈',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isCurrent ? scheme.primary : scheme.outlineVariant,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_emoji[plan]!, style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(plan.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(plan.price, style: TextStyle(color: scheme.primary)),
              ]),
            ),
            if (isCurrent) const Chip(label: Text('Đang dùng')),
          ]),
          const SizedBox(height: 8),
          Text(plan.slogan, style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 8),
          for (final perk in plan.perks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(AppIcons.check, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(perk)),
              ]),
            ),
          if (!isCurrent) ...[
            const SizedBox(height: 12),
            plan == Plan.conNo
                ? OutlinedButton(
                    onPressed: () => _downgrade(context),
                    child: const Text('Quay về làm Con Nợ'),
                  )
                : _RunawayBuyButton(plan: plan),
          ],
        ]),
      ),
    );
  }

  Future<void> _downgrade(BuildContext context) async {
    await App.setPlan(Plan.conNo);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Chào mừng trở lại làm Con Nợ. Nghèo nhưng vui 🥲')));
    }
  }
}

/// Nút "Mua" né tay người bấm 3 lần đầu, sau đó mới cho mua (miễn phí).
class _RunawayBuyButton extends StatefulWidget {
  final Plan plan;
  const _RunawayBuyButton({required this.plan});

  @override
  State<_RunawayBuyButton> createState() => _RunawayBuyButtonState();
}

class _RunawayBuyButtonState extends State<_RunawayBuyButton> {
  static const _taunts = [
    'Ơ kìa, chắc chưa? 🤨',
    'Nghĩ lại đi, tiền đó trả nợ được đấy 😏',
    'Thôi được rồi, bấm lần nữa đi 🙄',
  ];
  final _random = Random();
  int _dodges = 0;
  Alignment _align = Alignment.centerLeft;

  Future<void> _onPressed() async {
    if (_dodges < _taunts.length) {
      setState(() {
        _align = Alignment(_random.nextDouble() * 2 - 1, 0);
        _dodges++;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(_taunts[_dodges - 1]),
            duration: const Duration(milliseconds: 1200)));
      return;
    }
    await App.setPlan(widget.plan);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thanh toán thành công! 🎉'),
        content: Text('Bạn đã trở thành ${widget.plan.title}.\n\n'
            'Đã trừ 0 ₫ từ tài khoản. Đùa thôi, miễn phí mà 😜'),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Ngon')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedAlign(
      alignment: _align,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: FilledButton.icon(
        onPressed: _onPressed,
        icon: const Icon(AppIcons.shoppingCart),
        label: Text('Mua ${widget.plan.title}'),
      ),
    );
  }
}
