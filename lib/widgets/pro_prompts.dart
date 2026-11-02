import 'dart:math';

import 'package:flutter/material.dart';

import '../logic/growth.dart';
import '../screens/plans_screen.dart';
import '../services/app_services.dart';
import 'app_icons.dart';
import 'common.dart';

/// Hộp thoại khi chạm vào tính năng Pro: giải thích ngắn, kèm nút dùng thử
/// (nếu máy chưa dùng thử) hoặc nút xem các gói. Trả về true nếu sau đó
/// người dùng đã có Pro.
Future<bool> showProUpsell(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final canTry = !App.trialUsed;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(AppIcons.crown),
      title: Text(title),
      content: Text(canTry
          ? '$message\n\nDùng thử Pro $proTrialDays ngày, không cần thanh toán.'
          : message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Để sau')),
        if (canTry)
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'plans'),
              child: const Text('Xem các gói')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, canTry ? 'trial' : 'plans'),
          child: Text(canTry ? 'Dùng thử $proTrialDays ngày' : 'Xem các gói'),
        ),
      ],
    ),
  );
  if (!context.mounted) return App.plan.value.isPro;
  if (choice == 'trial') {
    await App.startTrial();
    if (context.mounted) {
      showSnack(context, 'Đã bật Pro dùng thử $proTrialDays ngày 🎉');
    }
  } else if (choice == 'plans') {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const PlansScreen()));
  }
  return App.plan.value.isPro;
}

/// Gọi sau mỗi thao tác đã có kết quả (thêm khoản chi, ghi nhận trả tiền,
/// tạo nhóm). Ưu tiên đề nghị dùng thử sau bill đầu tiên, nếu không thì
/// có thể hiện một quảng cáo vui ở bản Free.
Future<void> afterResult(
  BuildContext context, {
  int memberCount = 0,
  int expenseCount = 0,
}) async {
  if (shouldOfferTrial(
    plan: App.plan.value,
    trialUsed: App.trialUsed,
    memberCount: memberCount,
    expenseCount: expenseCount,
  )) {
    await showProUpsell(
      context,
      title: 'Cả nhóm vừa chốt bill đầu tiên 🎉',
      message: 'Thử Pro: chia theo số tiền hoặc theo %, nhắc nợ nhiều mốc, '
          'xuất báo cáo, không quảng cáo.',
    );
    return;
  }
  if (App.ads.onResult(plan: App.plan.value, firstSession: App.firstSession)) {
    await _showFakeAd(context);
  }
}

Future<void> _showFakeAd(BuildContext context) async {
  final ad = pickAd(Random().nextInt(1000));
  final removeAds = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(ctx).colorScheme.outline),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text('Quảng cáo', style: TextStyle(fontSize: 11)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(ad.brand)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(ad.emoji, style: const TextStyle(fontSize: 56)),
        const SizedBox(height: 8),
        Text(ad.text, textAlign: TextAlign.center),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tắt quảng cáo')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Đóng')),
      ],
    ),
  );
  if (removeAds == true && context.mounted) {
    await showProUpsell(
      context,
      title: 'Không còn quảng cáo với Pro',
      message: 'Gói Chủ Nợ trở lên không có quảng cáo.',
    );
  }
}
