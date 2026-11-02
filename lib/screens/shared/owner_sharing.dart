import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../logic/money.dart';
import '../../models/member.dart';
import '../../services/app_services.dart';
import '../../services/ledger_service.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';

/// Chủ sổ bật sổ chung cho nhóm: chọn mình là thành viên nào rồi tạo sổ
/// trên Firestore. Trả về true nếu bật thành công.
Future<bool> startSharing(
    BuildContext context, int groupId, List<Member> members) async {
  final service = App.shared;
  if (service == null) {
    showSnack(context, 'Chưa kết nối được Firebase');
    return false;
  }
  if (members.isEmpty) {
    showSnack(context, 'Thêm thành viên trước đã');
    return false;
  }
  final myName =
      (App.auth?.currentUser?.displayName ?? '').trim().toLowerCase();
  final guess = members
      .where((m) => myName.isNotEmpty && m.name.trim().toLowerCase() == myName)
      .firstOrNull;
  final ownerId = await showDialog<int>(
    context: context,
    builder: (ctx) {
      int? picked = guess?.id;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Bật sổ chung'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                  'Mỗi người dùng tài khoản riêng: bạn gửi mã mời cho từng '
                  'thành viên, họ nhập mã là xem được sổ và số nợ của mình. '
                  'Chỉ bạn (chủ sổ) ghi khoản chi và gửi nhắc nợ.\n\n'
                  'Bạn là ai trong nhóm này?'),
              const SizedBox(height: 8),
              RadioGroup<int>(
                groupValue: picked,
                onChanged: (v) => setState(() => picked = v),
                child: Column(children: [
                  for (final m in members)
                    RadioListTile<int>(
                      value: m.id!,
                      title: Text(m.name),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ]),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            FilledButton(
              onPressed: picked == null ? null : () => Navigator.pop(ctx, picked),
              child: const Text('Bật sổ chung'),
            ),
          ],
        ),
      );
    },
  );
  if (ownerId == null) return false;
  try {
    await service.share(groupId, ownerMemberId: ownerId);
    if (context.mounted) {
      showSnack(context, 'Đã bật sổ chung. Bấm "Mời" cạnh từng thành viên.');
    }
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Không bật được sổ chung: $e');
    return false;
  }
}

/// Tạo mã mời cho [member] và cho chủ sổ gửi qua Zalo/Messenger.
Future<void> showInviteDialog(
    BuildContext context, SharedLedger ledger, Member member) async {
  final service = App.shared!;
  String code;
  try {
    code = await service.createInvite(ledger, member);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Không tạo được mã mời: $e');
    return;
  }
  if (!context.mounted) return;
  final text = 'Alo ${member.name}! Mình mời bạn vào sổ "${ledger.name}" '
      'trên app Alo, Trả Tiền!\n'
      'Đăng nhập tài khoản của bạn > bấm "Nhập mã mời" > nhập mã: $code';
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Mời ${member.name}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Gửi mã này cho đúng người. Ai nhập mã sẽ đứng tên '
            'thành viên này và nhận nhắc nợ của bạn. Mã chỉ dùng được '
            'một lần và hết hạn sau 7 ngày.'),
        const SizedBox(height: 16),
        SelectableText(code,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 8)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        FilledButton.icon(
          onPressed: () async {
            await SharePlus.instance.share(ShareParams(text: text));
          },
          icon: const Icon(AppIcons.share, size: 18),
          label: const Text('Gửi mã'),
        ),
      ],
    ),
  );
}

/// Chủ sổ soạn và gửi nhắc nợ tới tài khoản [toUid] của [debtor].
Future<void> sendReminder(
  BuildContext context, {
  required SharedLedger ledger,
  required Member debtor,
  required String toUid,
  required int amount,
}) async {
  final service = App.shared!;
  final controller = TextEditingController(
      text: service.defaultReminder(ledger, debtor.name, amount));
  final message = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Nhắc ${debtor.name} trả ${formatVnd(amount)}'),
      content: TextField(
        controller: controller,
        maxLines: 4,
        decoration: const InputDecoration(labelText: 'Lời nhắc'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        FilledButton.icon(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.pop(ctx, v);
          },
          icon: const Icon(AppIcons.bell, size: 18),
          label: const Text('Gửi'),
        ),
      ],
    ),
  );
  if (message == null) return;
  try {
    await service.remind(
        ledger: ledger, toUid: toUid, amount: amount, message: message);
    if (context.mounted) {
      showSnack(context, 'Đã gửi nhắc nợ tới ${debtor.name}');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Không gửi được: $e');
  }
}

/// Thẻ giới thiệu sổ chung ở tab Thành viên khi nhóm chưa bật.
class ShareBanner extends StatelessWidget {
  final VoidCallback onStart;
  const ShareBanner({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(AppIcons.users, size: 20),
            SizedBox(width: 8),
            Text('Mời cả nhóm vào sổ',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 6),
          const Text('Mỗi người có tài khoản riêng, tự xem mình nợ ai bao '
              'nhiêu. Bạn là chủ sổ nên chỉ bạn ghi chép và gửi nhắc nợ '
              'cho người đang nợ mình.'),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(AppIcons.userPlus, size: 18),
            label: const Text('Bật sổ chung'),
          ),
        ]),
      ),
    );
  }
}
