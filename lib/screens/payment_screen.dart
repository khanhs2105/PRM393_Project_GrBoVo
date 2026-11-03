import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../logic/growth.dart';
import '../logic/money.dart';
import '../logic/plans.dart';
import '../logic/vietqr.dart';
import '../models/activity.dart';
import '../models/bank.dart';
import '../models/group.dart';
import '../models/member.dart';
import '../models/settlement.dart';
import '../data/settlement_repository.dart';
import '../services/app_services.dart';
import '../widgets/common.dart';
import '../widgets/pro_prompts.dart';
import '../widgets/ui.dart';
import 'member_form_screen.dart';
import '../widgets/app_icons.dart';
import '../services/friendly_error.dart';

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

  /// Đếm số lần nhắc khoản này hôm nay. Hết lượt thì báo và trả về false.
  Future<bool> _takeReminderSlot() async {
    final key = reminderCountKey(
        widget.group.id!, t.fromId, t.toId, DateTime.now());
    final count = int.tryParse(await App.settings.get(key) ?? '') ?? 0;
    if (!canRemindAgain(count)) {
      if (mounted) showSnack(context, reminderLimitMessage);
      return false;
    }
    await App.settings.set(key, '${count + 1}');
    return true;
  }

  Future<void> _share() async {
    if (!await _takeReminderSlot()) return;
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

  /// Hẹn nhắc nợ: lời nhắc gửi qua sổ chung tới tài khoản của người nợ,
  /// thông báo hiện trên máy NGƯỜI NỢ (không phải máy người bấm).
  Future<void> _scheduleReminder() async {
    final service = App.shared;
    if (service == null) {
      showSnack(context, 'Chưa kết nối được Firebase');
      return;
    }
    final (ledger, debtorUid) = await (() async {
      try {
        return await service.debtorAccount(
            widget.group.id!, t.fromId, t.toId);
      } on StateError catch (e) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Chưa gửi được tới máy người nợ'),
              content: Text(e.message),
              actions: [
                FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK')),
              ],
            ),
          );
        }
        return (null, null);
      } catch (e) {
        if (mounted) showSnack(context, 'Không đọc được sổ chung: ${friendlyError(e)}');
        return (null, null);
      }
    })();
    if (ledger == null || debtorUid == null || !mounted) return;
    final now = DateTime.now();
    final tonight = nextEvening(now);
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final pro = App.plan.value.canAdvancedReminders;

    Widget proTile(BuildContext ctx, IconData icon, String title,
            String subtitle, List<DateTime> times) =>
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: pro ? null : const Icon(AppIcons.lock, size: 18),
          onTap: () => Navigator.pop(ctx, pro ? times : const <DateTime>[]),
        );

    final times = await showModalBottomSheet<List<DateTime>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Nhắc nợ lúc nào?')),
            ListTile(
              leading: const Icon(AppIcons.timer),
              title: const Text('1 phút nữa (để thử)'),
              onTap: () => Navigator.pop(
                  ctx, [DateTime.now().add(const Duration(minutes: 1))]),
            ),
            ListTile(
              leading: const Icon(AppIcons.moon),
              title: Text(
                  '20:00 ${tonight.day == now.day ? 'tối nay' : 'tối mai'}'),
              onTap: () => Navigator.pop(ctx, [tonight]),
            ),
            ListTile(
              leading: const Icon(AppIcons.sun),
              title: const Text('9:00 sáng mai'),
              onTap: () => Navigator.pop(ctx, [tomorrow]),
            ),
            ListTile(
              leading: const Icon(AppIcons.calendarRange),
              title: const Text('3 ngày nữa'),
              onTap: () =>
                  Navigator.pop(ctx, [now.add(const Duration(days: 3))]),
            ),
            const Divider(),
            proTile(ctx, AppIcons.bell, 'Nhắc nhiều mốc (Pro)',
                'Tối nay, sau 1 ngày và sau 3 ngày', multiStepReminders(now)),
            proTile(ctx, AppIcons.refreshCw, 'Nhắc mỗi tối trong 7 ngày (Pro)',
                '20:00 mỗi ngày, khỏi phải nhắn tay', dailyReminders(now)),
          ]),
        ),
      ),
    );
    if (times == null || !mounted) return;
    if (times.isEmpty) {
      await showProUpsell(context,
          title: 'Nhắc thêm vài lần trước hạn',
          message: 'Nhắc nhiều mốc và nhắc lặp lại là tính năng Pro, '
              'để bạn không phải nhắn tay.');
      return;
    }
    if (!await _takeReminderSlot()) return;
    var queued = false;
    try {
      for (final at in times) {
        // Mất mạng: các mốc còn lại vẫn vào hàng đợi, không báo lỗi giữa chừng.
        queued |= !await service.remind(
          ledger: ledger,
          toUid: debtorUid,
          amount: t.amount,
          message: _reminderText(),
          at: at,
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Không gửi được nhắc nợ: ${friendlyError(e)}');
      return;
    }
    if (mounted && queued) {
      showSnack(context,
          'Đang mất mạng: lời nhắc sẽ tự gửi khi có mạng, không cần gửi lại.');
      return;
    }
    if (mounted) {
      final who = _from!.name;
      showSnack(
          context,
          times.length == 1
              ? 'Máy của $who sẽ báo lúc ${formatDateTime(times.first)}'
              : 'Đã hẹn ${times.length} lần nhắc trên máy của $who, lần đầu '
                  'lúc ${formatDateTime(times.first)}');
    }
  }

  /// Đang ghi nhận "Đã trả": khóa nút để bấm liên tục không ghi nhiều lần.
  bool _paying = false;

  /// Hỏi số tiền đã trả (mặc định trả hết, sửa được để trả một phần).
  Future<void> _markPaid() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      await _doMarkPaid();
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _doMarkPaid() async {
    // Lấy số nợ còn lại mới nhất, không tin số trên màn hình (có thể đã cũ).
    final max = await App.settlements
        .maxPayable(widget.group.id!, t.fromId, t.toId);
    if (!mounted) return;
    if (max <= 0) {
      showSnack(context, '${_from!.name} đã trả hết cho ${_to!.name} rồi');
      Navigator.pop(context, true);
      return;
    }
    final suggested = t.amount < max ? t.amount : max;
    final controller = TextEditingController(text: '$suggested');
    var closed = false;
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: const Text('Xác nhận đã trả?'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${_from!.name} đã chuyển cho ${_to!.name}:'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  suffixText: '₫',
                  helperText: 'Sửa số tiền nếu chỉ trả một phần',
                  errorText: error,
                ),
              ),
            ]),
            actions: [
              TextButton(
                  onPressed: () {
                    if (closed) return;
                    closed = true;
                    Navigator.pop(ctx);
                  },
                  child: const Text('Hủy')),
              FilledButton(
                onPressed: () {
                  if (closed) return;
                  final v = parseVnd(controller.text);
                  if (v == null || v <= 0) {
                    setDialog(() => error = 'Nhập số tiền');
                  } else if (v > max) {
                    setDialog(() =>
                        error = 'Chỉ còn nợ ${formatVnd(max)}, không trả quá');
                  } else {
                    // Chặn bấm 2 lần khi hộp thoại đang đóng.
                    closed = true;
                    Navigator.pop(ctx, v);
                  }
                },
                child: const Text('Đã trả'),
              ),
            ],
          ),
        );
      },
    );
    // Không dispose controller ngay: hộp thoại còn đang chạy hiệu ứng đóng.
    if (amount == null || !mounted) return;
    try {
      await App.settlements.record(
        groupId: widget.group.id!,
        fromId: t.fromId,
        toId: t.toId,
        amount: amount,
      );
    } on OverpaymentException catch (e) {
      if (mounted) {
        showSnack(
            context,
            e.maxPayable == 0
                ? 'Khoản này đã trả hết rồi'
                : 'Chỉ còn nợ ${formatVnd(e.maxPayable)}, không ghi nhận thêm');
      }
      return;
    }
    await App.activities.log(
      groupId: widget.group.id,
      groupName: widget.group.name,
      kind: ActivityKind.settled,
      message: '${_from!.name} trả ${_to!.name}'
          '${amount < t.amount ? ' (một phần)' : ''}',
      amount: amount,
    );
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

    return Scaffold(
      appBar: AppBar(title: const Text('Thanh toán')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GradientPanel(
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _Person(_from!.name),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(AppIcons.arrowRight,
                      color: Colors.white, size: 28),
                ),
                _Person(to.name),
              ]),
              const SizedBox(height: 12),
              Text(formatVnd(t.amount),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800)),
              Text(widget.group.name,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
            ]),
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
                    icon: const Icon(AppIcons.landmark),
                    label: const Text('Thêm tài khoản'),
                  ),
                ]),
              ),
            )
          else ...[
            Card(
              clipBehavior: Clip.antiAlias,
              color: Colors.white,
              child: Padding(
               padding: const EdgeInsets.all(12),
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
            ),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: const Icon(AppIcons.landmark),
              title: Text(bank?.shortName ?? to.bankBin!),
              subtitle: Text('${to.accountNo}'
                  '${to.accountName == null ? '' : ' · ${to.accountName}'}'),
              trailing: IconButton(
                tooltip: 'Copy số tài khoản',
                icon: const Icon(AppIcons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: to.accountNo!));
                  showSnack(context, 'Đã copy số tài khoản');
                },
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(AppIcons.notebookPen),
              title: const Text('Nội dung chuyển khoản'),
              subtitle: Text(_note),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _saveQr,
              icon: const Icon(AppIcons.download),
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
                  icon: const Icon(AppIcons.megaphone),
                  label: Text(plan == Plan.doiNoThue ? 'Đòi nợ 😈' : 'Nhắc nợ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scheduleReminder,
                  icon: const Icon(AppIcons.alarmClockPlus),
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
            onPressed: _paying ? null : _markPaid,
            icon: const Icon(AppIcons.check),
            label: const Text('Đã trả'),
          ),
        ),
      ),
    );
  }
}

class _Person extends StatelessWidget {
  final String name;
  const _Person(this.name);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(2),
        decoration:
            const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: MemberAvatar(name, radius: 26),
      ),
      const SizedBox(height: 6),
      Text(name,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
    ]);
  }
}
