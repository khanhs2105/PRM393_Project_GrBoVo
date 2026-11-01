import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../logic/jwt.dart';
import '../services/app_services.dart';
import '../services/jwt_verifier.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/ui.dart';

/// Hiển thị ID token (JWT) của người đang đăng nhập: 3 phần tô màu như
/// jwt.io, header/payload đã giải mã, hạn dùng và kết quả kiểm chữ ký.
class JwtScreen extends StatefulWidget {
  const JwtScreen({super.key});

  @override
  State<JwtScreen> createState() => _JwtScreenState();
}

class _JwtScreenState extends State<JwtScreen> {
  late Future<JwtCheck> _future = App.auth!.verifyCurrentToken();

  static const _headerColor = Color(0xFFE5395B);
  static const _payloadColor = Color(0xFF8E44AD);
  static const _sigColor = Color(0xFF0097D6);

  void _refresh() => setState(
      () => _future = App.auth!.verifyCurrentToken(forceRefresh: true));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('JWT của bạn'),
        actions: [
          IconButton(
            tooltip: 'Xin token mới',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<JwtCheck>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Không lấy được token',
              message: '${snap.error}',
              actionLabel: 'Thử lại',
              onAction: _refresh,
            );
          }
          final check = snap.data;
          if (check == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _body(context, check);
        },
      ),
    );
  }

  Widget _body(BuildContext context, JwtCheck check) {
    final jwt = check.jwt;
    final left = jwt.timeLeft();
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12.5);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _verdict(check),
        const SectionHeader('Hạn dùng'),
        Card(
          child: Column(children: [
            _row('Cấp lúc (iat)',
                jwt.issuedAt == null ? '-' : formatDateTime(jwt.issuedAt!.toLocal())),
            _row('Hết hạn (exp)',
                jwt.expiresAt == null ? '-' : formatDateTime(jwt.expiresAt!.toLocal())),
            _row(
                'Còn lại',
                left.isNegative
                    ? 'Đã hết hạn'
                    : '${left.inMinutes} phút ${left.inSeconds % 60} giây'),
            _row('Người dùng (sub)', jwt.subject ?? '-'),
            _row('Thuật toán', '${jwt.algorithm} · kid ${_short(jwt.keyId)}'),
          ]),
        ),
        SectionHeader('Token (${jwt.raw.length} ký tự)',
            trailing: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: jwt.raw));
                if (context.mounted) showSnack(context, 'Đã chép token');
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Chép'),
            )),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText.rich(TextSpan(style: mono, children: [
              TextSpan(
                  text: jwt.encodedHeader,
                  style: const TextStyle(color: _headerColor)),
              const TextSpan(text: '.'),
              TextSpan(
                  text: jwt.encodedPayload,
                  style: const TextStyle(color: _payloadColor)),
              const TextSpan(text: '.'),
              TextSpan(
                  text: jwt.encodedSignature,
                  style: const TextStyle(color: _sigColor)),
            ])),
          ),
        ),
        const SectionHeader('Header'),
        _json(Jwt.pretty(jwt.header), _headerColor, mono),
        const SectionHeader('Payload (các claim)'),
        _json(Jwt.pretty(jwt.payload), _payloadColor, mono),
        const SectionHeader('Chữ ký'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'RSASSA-PKCS1-v1_5 SHA-256 (${jwt.signature.length * 8} bit) trên '
              'chuỗi "header.payload", ký bằng khóa bí mật của Google. App tải '
              'khóa công khai từ ${FirebaseJwtVerifier.jwksUrl} rồi tự kiểm.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }

  Widget _verdict(JwtCheck c) {
    final ok = c.ok;
    final color = ok ? AppTheme.owed : AppTheme.owe;
    final lines = <String>[
      c.signatureValid ? 'Chữ ký RS256 hợp lệ' : 'Chữ ký chưa xác minh được',
      if (c.keyError != null) c.keyError!,
      if (c.claimProblems.isEmpty)
        'Claim hợp lệ: iss, aud, exp, iat, sub'
      else
        ...c.claimProblems,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconTile(ok ? Icons.verified_user : Icons.gpp_maybe, color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ok ? 'Token hợp lệ' : 'Token chưa hợp lệ',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 4),
              for (final l in lines) Text('• $l'),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _row(String label, String value) => ListTile(
        dense: true,
        title: Text(label),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 210),
          child: Text(value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );

  Widget _json(String text, Color color, TextStyle mono) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SelectableText(text, style: mono.copyWith(color: color)),
        ),
      );

  static String _short(String? s) =>
      s == null ? '-' : (s.length > 10 ? '${s.substring(0, 10)}…' : s);
}
