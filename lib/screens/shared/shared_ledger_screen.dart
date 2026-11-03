import 'package:flutter/material.dart';

import '../../logic/money.dart';
import '../../logic/vietqr.dart';
import '../../models/member.dart';
import '../../models/settlement.dart';
import '../../services/app_services.dart';
import '../../services/ledger_service.dart';
import '../../theme.dart';
import '../../widgets/app_icons.dart';
import '../../widgets/common.dart';
import '../../widgets/ui.dart';
import '../../services/friendly_error.dart';

/// Nhập mã mời để vào sổ chung của người khác. Vào được thì mở sổ luôn.
Future<void> showJoinLedgerDialog(BuildContext context) async {
  final service = App.shared;
  if (service == null) {
    showSnack(context, 'Chưa kết nối được Firebase');
    return;
  }
  final controller = TextEditingController();
  var busy = false;
  final ledgerId = await showDialog<String>(
    context: context,
    // Không cho bấm ra ngoài để đóng khi đang vào sổ (xem PopScope dưới).
    barrierDismissible: false,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(builder: (ctx, setState) {
        Future<void> submit() async {
          setState(() {
            busy = true;
            error = null;
          });
          try {
            final id = await service.join(controller.text);
            if (ctx.mounted) Navigator.pop(ctx, id);
          } on FormatException catch (e) {
            if (ctx.mounted) setState(() => error = e.message);
          } catch (e) {
            if (ctx.mounted) {
              setState(() => error = 'Không vào được sổ: ${friendlyError(e)}');
            }
          } finally {
            if (ctx.mounted) setState(() => busy = false);
          }
        }

        // Đang vào sổ thì không cho đóng hộp thoại (nút Back).
        return PopScope(
          canPop: !busy,
          child: AlertDialog(
          title: const Text('Nhập mã mời'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Chủ sổ gửi cho bạn một mã 6 ký tự. Nhập vào để xem '
                'sổ chung và nhận nhắc nợ trên tài khoản của bạn.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              style: const TextStyle(
                  fontSize: 22, letterSpacing: 6, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'K7QX2M',
                errorText: error,
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => busy ? null : submit(),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            FilledButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Vào sổ'),
            ),
          ],
        ),
        );
      });
    },
  );
  if (ledgerId == null || !context.mounted) return;
  showSnack(context, 'Đã vào sổ chung');
  await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SharedLedgerScreen(ledgerId: ledgerId)));
}

/// Mục "Sổ bạn được mời" trên màn chính. Không có sổ nào thì ẩn.
class SharedLedgersSection extends StatefulWidget {
  const SharedLedgersSection({super.key});

  @override
  State<SharedLedgersSection> createState() => _SharedLedgersSectionState();
}

class _SharedLedgersSectionState extends State<SharedLedgersSection> {
  // Giữ một stream, không tạo lại mỗi lần màn chính dựng lại.
  final _stream = App.shared?.joinedLedgers();

  @override
  Widget build(BuildContext context) {
    final service = App.shared;
    if (service == null || _stream == null) return const SizedBox.shrink();
    return StreamBuilder<List<SharedLedger>>(
      stream: _stream,
      builder: (context, snap) {
        final ledgers = snap.data ?? const [];
        if (ledgers.isEmpty) return const SizedBox.shrink();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader('Sổ bạn được mời',
                  trailing: Text('${ledgers.length} sổ',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant))),
              for (final l in ledgers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _JoinedLedgerCard(ledger: l, myUid: service.uid),
                ),
              const SizedBox(height: 6),
            ]);
      },
    );
  }
}

class _JoinedLedgerCard extends StatelessWidget {
  final SharedLedger ledger;
  final String? myUid;
  const _JoinedLedgerCard({required this.ledger, required this.myUid});

  @override
  Widget build(BuildContext context) {
    final me = ledger.memberIdOf(myUid);
    final balance = ledger.data.balances[me] ?? 0;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        leading: IconTile(groupTypeIcon(ledger.type),
            groupTypeColor(ledger.type),
            size: 44),
        title: Text(ledger.name,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            'Chủ sổ: ${ledger.ownerName} · Bạn là ${ledger.data.nameOf(me)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, fontSize: 12)),
        trailing: SignedAmount(balance),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SharedLedgerScreen(ledgerId: ledger.id))),
      ),
    );
  }
}

/// Sổ chung nhìn từ phía thành viên: chỉ xem, không sửa. Tự cập nhật khi
/// chủ sổ thêm khoản chi hay ghi nhận trả tiền.
class SharedLedgerScreen extends StatefulWidget {
  final String ledgerId;
  const SharedLedgerScreen({super.key, required this.ledgerId});

  @override
  State<SharedLedgerScreen> createState() => _SharedLedgerScreenState();
}

class _SharedLedgerScreenState extends State<SharedLedgerScreen> {
  late final _stream = App.shared!.watch(widget.ledgerId);

  @override
  Widget build(BuildContext context) {
    final service = App.shared!;
    return StreamBuilder<SharedLedger?>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasError) {
          return Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()));
        }
        // Lỗi quyền (bị gỡ khỏi sổ) cũng coi như không mở được.
        final ledger = snap.hasError ? null : snap.data;
        if (ledger == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: AppIcons.cloudOff,
              title: 'Không mở được sổ',
              message: 'Sổ đã bị chủ sổ xóa, hoặc bạn không còn trong sổ.',
            ),
          );
        }
        return _LedgerView(ledger: ledger, myUid: service.uid);
      },
    );
  }
}

class _LedgerView extends StatelessWidget {
  final SharedLedger ledger;
  final String? myUid;
  const _LedgerView({required this.ledger, required this.myUid});

  /// Tự rời sổ (nhập nhầm mã, hoặc không muốn ở trong sổ nữa).
  Future<void> _leave(BuildContext context) async {
    final ok = await confirm(
        context,
        'Rời sổ "${ledger.name}"?',
        'Bạn sẽ không xem được sổ và không nhận nhắc nợ nữa. Muốn vào lại '
            'thì nhờ chủ sổ gửi mã mời mới.',
        ok: 'Rời sổ');
    if (!ok) return;
    try {
      await App.shared!.leave(ledger.id);
      if (context.mounted) {
        showSnack(context, 'Đã rời sổ');
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'Chưa rời sổ được: ${friendlyError(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = ledger.data;
    final me = ledger.memberIdOf(myUid);
    final myBalance = d.balances[me] ?? 0;
    final iOwe = [for (final t in d.transfers) if (t.fromId == me) t];
    final owedToMe = [for (final t in d.transfers) if (t.toId == me) t];
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(ledger.name), actions: [
        if (!ledger.isOwner(myUid))
          IconButton(
            tooltip: 'Rời sổ',
            icon: const Icon(AppIcons.logOut),
            onPressed: () => _leave(context),
          ),
      ]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _Header(ledger: ledger, me: me, balance: myBalance),
          const SizedBox(height: 8),
          Text(
              'Chỉ chủ sổ (${ledger.ownerName}) thêm khoản chi và ghi nhận '
              'trả tiền. Chuyển khoản xong thì báo chủ sổ để gạch nợ nhé.',
              style: TextStyle(color: muted, fontSize: 12)),
          _NoticesSection(ledgerId: ledger.id),
          SectionHeader('Bạn cần trả',
              trailing: Text('${iOwe.length} lượt',
                  style: TextStyle(color: muted, fontSize: 12))),
          if (iOwe.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('🎉 Bạn không nợ ai trong sổ này.',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          for (final t in iOwe)
            _PayCard(
              ledgerName: ledger.name,
              me: d.memberById(t.fromId),
              to: d.memberById(t.toId),
              toUid: ledger.uidsOf(t.toId).firstOrNull,
              amount: t.amount,
            ),
          if (owedToMe.isNotEmpty) ...[
            const SectionHeader('Người khác cần trả bạn'),
            Card(
              child: Column(children: [
                for (final t in owedToMe)
                  ListTile(
                    leading: MemberAvatar(d.nameOf(t.fromId),
                        uid: ledger.uidsOf(t.fromId).firstOrNull),
                    title: Text(d.nameOf(t.fromId)),
                    trailing: SignedAmount(t.amount),
                  ),
              ]),
            ),
          ],
          const SectionHeader('Số dư cả nhóm'),
          Card(
            child: Column(children: [
              for (final m in d.members)
                ListTile(
                  leading: MemberAvatar(m.name,
                      uid: ledger.uidsOf(m.id).firstOrNull),
                  title: Text(m.id == me ? '${m.name} (bạn)' : m.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      ledger.accountNameOf(m.id) == null
                          ? 'Chưa có tài khoản'
                          : 'Tài khoản: ${ledger.accountNameOf(m.id)}',
                      style: TextStyle(fontSize: 12, color: muted)),
                  trailing: SignedAmount(d.balances[m.id] ?? 0),
                ),
            ]),
          ),
          SectionHeader('Khoản chi',
              trailing: Text(formatVnd(d.totalSpent),
                  style: TextStyle(color: muted, fontSize: 12))),
          if (d.expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Chưa có khoản chi nào.',
                  style: TextStyle(color: muted)),
            ),
          if (d.expenses.isNotEmpty)
            Card(
              child: Column(children: [
                for (final e in d.expenses)
                  ListTile(
                    title: Text(e.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${d.nameOf(e.paidBy)} trả · ${formatDate(e.date)}'
                        '${(e.shares[me] ?? 0) > 0 ? ' · phần bạn ${formatVnd(e.shares[me]!)}' : ''}',
                        style: TextStyle(fontSize: 12, color: muted)),
                    trailing: Text(formatVnd(e.amount),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          if (d.settlements.isNotEmpty) ...[
            const SectionHeader('Đã trả'),
            Card(
              child: Column(children: [
                for (final Settlement s in d.settlements)
                  ListTile(
                    leading: const IconTile(AppIcons.check, AppTheme.owed,
                        size: 36),
                    title: Text('${d.nameOf(s.fromId)} → ${d.nameOf(s.toId)}'),
                    subtitle: Text(formatDateTime(s.paidAt),
                        style: TextStyle(fontSize: 12, color: muted)),
                    trailing: Text(formatVnd(s.amount),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ],
          if (ledger.updatedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('Cập nhật lúc ${formatDateTime(ledger.updatedAt!)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final SharedLedger ledger;
  final int? me;
  final int balance;
  const _Header({required this.ledger, required this.me, required this.balance});

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.85);
    final label = balance < 0
        ? 'Bạn đang nợ'
        : balance > 0
            ? 'Bạn được nợ'
            : 'Bạn đã sòng phẳng';
    return GradientPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Chủ sổ: ${ledger.ownerName}',
            style: TextStyle(color: muted, fontSize: 13)),
        Text('Bạn là ${ledger.data.nameOf(me)} trong sổ này',
            style: TextStyle(color: muted, fontSize: 13)),
        const SizedBox(height: 10),
        Text(label, style: TextStyle(color: muted, fontSize: 13)),
        Text(formatVnd(balance.abs()),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// Một khoản mình cần trả, bấm "Mã QR" để chuyển khoản ngay.
class _PayCard extends StatelessWidget {
  final String ledgerName;
  final Member? me;
  final Member? to;
  final String? toUid;
  final int amount;
  const _PayCard(
      {required this.ledgerName,
      required this.me,
      required this.to,
      this.toUid,
      required this.amount});

  void _showQr(BuildContext context) {
    final m = to!;
    final url = vietQrImageUrl(
      bin: m.bankBin!,
      accountNo: m.accountNo!,
      amount: amount,
      note: suggestedNote(me?.name ?? '', m.name, ledgerName),
      accountName: m.accountName,
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Trả ${m.name} ${formatVnd(amount)}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.network(url,
              height: 300,
              errorBuilder: (_, _, _) =>
                  const Text('Không tải được mã QR, kiểm tra mạng.')),
          const SizedBox(height: 8),
          Text('${m.accountNo} · ${m.accountName ?? ''}',
              textAlign: TextAlign.center),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = to?.name ?? '?';
    final canQr = to?.hasBank ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            MemberAvatar(name, radius: 20, uid: toUid),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trả $name',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                    Text(formatVnd(amount),
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.owe)),
                  ]),
            ),
            if (canQr)
              FilledButton.icon(
                onPressed: () => _showQr(context),
                icon: const Icon(AppIcons.qrCode, size: 18),
                label: const Text('Mã QR'),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Lời nhắc chủ sổ đã gửi cho mình trong sổ này.
class _NoticesSection extends StatefulWidget {
  final String ledgerId;
  const _NoticesSection({required this.ledgerId});

  @override
  State<_NoticesSection> createState() => _NoticesSectionState();
}

class _NoticesSectionState extends State<_NoticesSection> {
  late final _stream = App.shared!.noticesFor(widget.ledgerId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LedgerNotice>>(
      stream: _stream,
      builder: (context, snap) {
        final notices = snap.data ?? const [];
        if (notices.isEmpty) return const SizedBox.shrink();
        final muted = Theme.of(context).colorScheme.onSurfaceVariant;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader('Nhắc nợ từ chủ sổ'),
              Card(
                child: Column(children: [
                  for (final n in notices.take(5))
                    ListTile(
                      leading: const IconTile(AppIcons.bell, AppTheme.owe,
                          size: 36),
                      title: Text(n.message),
                      subtitle: Text(
                          n.createdAt == null
                              ? n.fromName
                              : '${n.fromName} · ${formatDateTime(n.createdAt!)}',
                          style: TextStyle(fontSize: 12, color: muted)),
                    ),
                ]),
              ),
            ]);
      },
    );
  }
}
