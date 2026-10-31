import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../logic/money.dart';
import '../logic/plans.dart';
import '../logic/vietqr.dart';
import '../models/bank.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/settlement.dart';
import '../services/app_services.dart';
import '../services/notification_service.dart';
import '../widgets/common.dart';
import 'member_form_screen.dart';

/// Màn thanh toán một lượt chuyển: hiện QR VietQR, nhắc nợ, đánh dấu đã trả.
class PaymentScreen extends StatefulWidget {
  final Group group;
  final Transfer transfer;
  const PaymentScreen({super.key, required this.group, required this.transfer});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Member? _from;
  Member? _to;
  final _random = Random();

  Transfer get t => widget.transfer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final members = await App.groups.members(widget.group.id!);
    if (!mounted) return;
    setState(() {
      _from = members.firstWhere((m) => m.id == t.fromId);
      _to = members.firstWhere((m) => m.id == t.toId);
    });
  }

  String get _note => suggestedNote(_from!.name, _to!.name, widget.group.name);

  String get _qrUrl => vietQrImageUrl(
        bin: _to!.bankBin!,
        accountNo: _to!.accountNo!,
        amount: t.amount,
        note: _note,
        accountName: _to!.accountName,
      );

  String _reminderText() => reminderMessage(
        plan: App.plan.value,
        debtor: _from!.name,
        creditor: _to!.name,
        amount: t.amount,
        group: widget.group.name,
        variant: _random.nextInt(100),
      );

  Future<void> _share() async {
    final text = StringBuffer(_reminderText());
    if (_to!.hasBank) {
      text
        ..writeln()
        ..writeln()
        ..writeln('Quét QR để trả: $_qrUrl');
    }
    await SharePlus.instance.share(ShareParams(text: text.toString()));
  }

  Future<void> _saveQr() async {
    try {
      final client = HttpClient();
      final res = await (await client.getUrl(Uri.parse(_qrUrl))).close();
      final bytes = await consolidateHttpClientResponseBytes(res);
      client.close();
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      await Gal.putImageBytes(bytes, name: 'vietqr_${DateTime.now().millisecondsSinceEpoch}');
      if (mounted) showSnack(context, 'Đã lưu QR vào thư viện ảnh');
    } catch (e) {
      if (mounted) showSnack(context, 'Không lưu được QR: $e');
    }
  }

  Future<void> _scheduleReminder() async {
    final now = DateTime.now();
    var tonight = DateTime(now.year, now.month, now.day, 20);
    if (tonight.isBefore(now)) tonight = tonight.add(const Duration(days: 1));
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);

    final at = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Nhắc nợ lúc nào?')),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('1 phút nữa (để thử)'),
            onTap: () =>
                Navigator.pop(ctx, DateTime.now().add(const Duration(minutes: 1))),
          ),
          ListTile(
            leading: const Icon(Icons.nightlight_outlined),
            title: Text('20:00 ${tonight.day == now.day ? 'tối nay' : 'tối mai'}'),
            onTap: () => Navigator.pop(ctx, tonight),
          ),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('9:00 sáng mai'),
            onTap: () => Navigator.pop(ctx, tomorrow),
          ),
          ListTile(
            leading: const Icon(Icons.date_range_outlined),
            title: const Text('3 ngày nữa'),
            onTap: () => Navigator.pop(ctx, now.add(const Duration(days: 3))),
          ),
        ]),
      ),
    );
    if (at == null) return;
    if (!await NotificationService.requestPermission()) {
      if (mounted) showSnack(context, 'Cần cho phép thông báo để nhắc nợ');
      return;
    }
    await NotificationService.schedule(
      at: at,
      title: 'Nhắc nợ: ${_from!.name} → ${_to!.name}',
      body: _reminderText(),
    );
    if (mounted) {
      showSnack(context, 'Sẽ nhắc lúc ${formatDateTime(at)} (có thể lệch vài phút)');
    }
  }

  Future<void> _markPaid() async {
    final ok = await confirm(
      context,
      'Xác nhận đã trả?',
      '${_from!.name} đã chuyển ${formatVnd(t.amount)} cho ${_to!.name}.',
      ok: 'Đã trả',
    );
    if (!ok) return;
    await App.settlements.markPaid(widget.group.id!, t);
    HapticFeedback.mediumImpact();
    if (mounted) {
      showSnack(context, 'Đã ghi nhận thanh toán ✓');
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_from == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final to = _to!;
    final bank = findBankByBin(App.banks, to.bankBin);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Thanh toán')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Column(children: [MemberAvatar(_from!.name, radius: 26), Text(_from!.name)]),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.arrow_forward, size: 32),
            ),
            Column(children: [MemberAvatar(to.name, radius: 26), Text(to.name)]),
          ]),
          const SizedBox(height: 12),
          Center(
            child: Text(formatVnd(t.amount),
                style: text.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          if (!to.hasBank)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text('${to.name} chưa có tài khoản ngân hàng nên chưa tạo được QR.'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => MemberFormScreen(member: to)));
                      _load();
                    },
                    icon: const Icon(Icons.account_balance),
                    label: const Text('Thêm tài khoản'),
                  ),
                ]),
              ),
            )
          else ...[
            Card(
              clipBehavior: Clip.antiAlias,
              color: Colors.white,
              child: AspectRatio(
                aspectRatio: 1,
                child: Image.network(
                  _qrUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (context, error, stack) => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Không tải được QR. Kiểm tra kết nối mạng.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: const Icon(Icons.account_balance),
              title: Text(bank?.shortName ?? to.bankBin!),
              subtitle: Text('${to.accountNo}'
                  '${to.accountName == null ? '' : ' · ${to.accountName}'}'),
              trailing: IconButton(
                tooltip: 'Copy số tài khoản',
                icon: const Icon(Icons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: to.accountNo!));
                  showSnack(context, 'Đã copy số tài khoản');
                },
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.notes),
              title: const Text('Nội dung chuyển khoản'),
              subtitle: Text(_note),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saveQr,
              icon: const Icon(Icons.download),
              label: const Text('Lưu QR vào thư viện ảnh'),
            ),
          ],
          const SizedBox(height: 8),
          ValueListenableBuilder<Plan>(
            valueListenable: App.plan,
            builder: (context, plan, _) => Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.campaign_outlined),
                  label: Text(plan == Plan.doiNoThue ? 'Đòi nợ 😈' : 'Nhắc nợ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scheduleReminder,
                  icon: const Icon(Icons.alarm_add_outlined),
                  label: const Text('Hẹn nhắc'),
                ),
              ),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _markPaid,
            icon: const Icon(Icons.check),
            label: const Text('Đã trả'),
          ),
        ),
      ),
    );
  }
}
