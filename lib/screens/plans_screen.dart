import 'package:flutter/material.dart';

import '../logic/growth.dart';
import '../logic/plans.dart';
import '../services/app_services.dart';
import '../widgets/app_icons.dart';
import '../widgets/common.dart';
import 'checkout_screen.dart';

/// Màn chọn gói. Không có thanh toán thật: nút mua mở màn thanh toán giả
/// ([CheckoutScreen]) luôn giảm 100%.
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nâng cấp')),
      // Nghe planChanges chứ không chỉ App.plan: đang dùng thử mà mua Chủ Nợ
      // thì gói thực tế không đổi nhưng các thẻ vẫn phải vẽ lại.
      body: ValueListenableBuilder<int>(
        valueListenable: App.planChanges,
        builder: (context, tick, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Chọn đẳng cấp đòi nợ của bạn',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Không tốn đồng nào thật. Đây là app chia tiền, '
                'không phải app lấy tiền 😌'),
            const SizedBox(height: 16),
            _TrialCard(tick: tick),
            // "Đang dùng" theo gói đã mua: đang dùng thử vẫn mua được Chủ Nợ,
            // và không hiện nút "Quay về làm Con Nợ" vô tác dụng.
            for (final plan in Plan.values)
              _PlanCard(plan: plan, isCurrent: plan == App.purchasedPlan),
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
                : _BuyButton(plan: plan),
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

/// Nút "Mua": mở màn thanh toán giả. Trước đây nút né tay người bấm 3 lần
/// nên nhiều người tưởng không mua được; giờ bấm là vào thanh toán luôn.
class _BuyButton extends StatelessWidget {
  final Plan plan;
  const _BuyButton({required this.plan});

  Future<void> _open(BuildContext context) async {
    final bought = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CheckoutScreen(plan: plan)),
    );
    if (bought == true && context.mounted) {
      showSnack(context, 'Đã kích hoạt gói ${plan.title} 😎');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () => _open(context),
      icon: const Icon(AppIcons.shoppingCart),
      label: Text('Mua ${plan.title}'),
    );
  }
}

/// Thẻ dùng thử Pro $proTrialDays ngày: mỗi máy một lần, không cần thanh toán,
/// hết hạn tự quay về Con Nợ.
class _TrialCard extends StatelessWidget {
  /// Giá trị của [App.planChanges]: đổi là thẻ vẽ lại (trước đây thẻ là
  /// `const` nên bấm dùng thử xong vẫn còn nút).
  final int tick;
  const _TrialCard({required this.tick});

  @override
  Widget build(BuildContext context) {
    if (App.purchasedPlan.isPro) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final String text;
    Widget? action;
    if (App.onTrial) {
      text = 'Đang dùng thử Pro đến ${formatDateTime(App.trialUntil!)}. '
          'Hết hạn app tự quay về Con Nợ, không trừ đồng nào.';
    } else if (App.trialUsed) {
      return const SizedBox.shrink();
    } else {
      text = 'Dùng thử gói Chủ Nợ $proTrialDays ngày, không cần thanh toán. '
          'Báo trước 1 ngày khi sắp hết hạn.';
      action = FilledButton.tonalIcon(
        onPressed: () async {
          await App.startTrial();
          if (context.mounted) {
            showSnack(context, 'Đã bật Pro dùng thử $proTrialDays ngày 🎉');
          }
        },
        icon: const Icon(AppIcons.sparkles),
        label: const Text('Dùng thử miễn phí'),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(AppIcons.sparkles),
            const SizedBox(width: 8),
            Text('Pro dùng thử',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          Text(text),
          if (action != null) ...[const SizedBox(height: 10), action],
        ]),
      ),
    );
  }
}
