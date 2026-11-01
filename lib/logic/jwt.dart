/// Đọc và kiểm tra JWT (JSON Web Token).
///
/// Firebase Auth cấp cho mỗi người dùng đã đăng nhập một "ID token". Token này
/// chính là một JWT gồm 3 phần ngăn bởi dấu chấm:
///   header.payload.signature
/// - header: thuật toán ký (RS256) và mã khóa `kid`.
/// - payload: các "claim" như `sub` (uid), `email`, `iat` (lúc cấp), `exp` (hết hạn).
/// - signature: chữ ký RSA-SHA256 của Google trên chuỗi "header.payload".
///
/// File này không phụ thuộc Flutter hay Firebase nên kiểm thử được bằng unit test.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Khóa công khai RSA (modulus n, số mũ e).
class RsaPublicKey {
  final BigInt n;
  final BigInt e;
  const RsaPublicKey(this.n, this.e);

  /// Đọc từ một JWK ({"kty":"RSA","n":"...","e":"AQAB"}).
  factory RsaPublicKey.fromJwk(Map<String, dynamic> jwk) {
    if (jwk['kty'] != null && jwk['kty'] != 'RSA') {
      throw FormatException('Khóa không phải RSA: ${jwk['kty']}');
    }
    return RsaPublicKey(
      bytesToBigInt(base64UrlDecode(jwk['n'] as String)),
      bytesToBigInt(base64UrlDecode(jwk['e'] as String)),
    );
  }

  /// Độ dài khóa tính bằng byte (256 với khóa 2048 bit).
  int get byteLength => (n.bitLength + 7) ~/ 8;
}

/// Đọc danh sách khóa JWKS ({"keys":[{kid, n, e, ...}]}) thành map kid → khóa.
Map<String, RsaPublicKey> parseJwks(String json) {
  final data = jsonDecode(json) as Map<String, dynamic>;
  return {
    for (final k in (data['keys'] as List).cast<Map<String, dynamic>>())
      if (k['kid'] is String) k['kid'] as String: RsaPublicKey.fromJwk(k),
  };
}

/// Giải mã base64url, chấp nhận chuỗi thiếu dấu "=" ở cuối như trong JWT.
Uint8List base64UrlDecode(String s) => base64Url.decode(base64Url.normalize(s));

BigInt bytesToBigInt(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b);
  }
  return r;
}

Uint8List bigIntToBytes(BigInt v, int length) {
  final out = Uint8List(length);
  var x = v;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (x & BigInt.from(0xff)).toInt();
    x = x >> 8;
  }
  return out;
}

/// Phần đầu cố định của DigestInfo SHA-256 trong chuẩn PKCS#1 v1.5.
const _sha256DigestInfo = [
  0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, //
  0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
];

/// Một JWT đã tách ra 3 phần.
class Jwt {
  final String raw;
  final String encodedHeader;
  final String encodedPayload;
  final String encodedSignature;
  final Map<String, dynamic> header;
  final Map<String, dynamic> payload;
  final Uint8List signature;

  Jwt._(this.raw, this.encodedHeader, this.encodedPayload,
      this.encodedSignature, this.header, this.payload, this.signature);

  /// Tách token. Ném [FormatException] nếu không đúng dạng JWT.
  factory Jwt.parse(String token) {
    final parts = token.trim().split('.');
    if (parts.length != 3) {
      throw const FormatException('JWT phải có đúng 3 phần ngăn bởi dấu chấm');
    }
    Map<String, dynamic> json(String part, String name) {
      try {
        final v = jsonDecode(utf8.decode(base64UrlDecode(part)));
        if (v is Map<String, dynamic>) return v;
      } catch (_) {}
      throw FormatException('Phần $name của JWT không phải JSON hợp lệ');
    }

    return Jwt._(
      token.trim(),
      parts[0],
      parts[1],
      parts[2],
      json(parts[0], 'header'),
      json(parts[1], 'payload'),
      base64UrlDecode(parts[2]),
    );
  }

  String? get algorithm => header['alg'] as String?;
  String? get keyId => header['kid'] as String?;
  String? get subject => payload['sub'] as String?;
  String? get issuer => payload['iss'] as String?;
  String? get email => payload['email'] as String?;

  /// `aud` có thể là chuỗi hoặc mảng chuỗi.
  List<String> get audience {
    final a = payload['aud'];
    if (a is String) return [a];
    if (a is List) return a.whereType<String>().toList();
    return const [];
  }

  DateTime? _time(String key) {
    final v = payload[key];
    return v is num
        ? DateTime.fromMillisecondsSinceEpoch((v * 1000).round(), isUtc: true)
        : null;
  }

  DateTime? get issuedAt => _time('iat');
  DateTime? get expiresAt => _time('exp');
  DateTime? get authTime => _time('auth_time');

  bool isExpired([DateTime? now]) {
    final exp = expiresAt;
    return exp == null || !exp.isAfter(now ?? DateTime.now());
  }

  /// Thời gian còn lại trước khi hết hạn (âm nếu đã hết hạn).
  Duration timeLeft([DateTime? now]) =>
      (expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .difference(now ?? DateTime.now());

  /// Chuỗi đã được ký: "header.payload".
  String get signingInput => '$encodedHeader.$encodedPayload';

  /// Kiểm tra chữ ký RS256 (RSASSA-PKCS1-v1_5 + SHA-256) bằng khóa công khai.
  bool verifyRs256(RsaPublicKey key) {
    if (algorithm != 'RS256') return false;
    final k = key.byteLength;
    if (signature.length != k) return false;
    final s = bytesToBigInt(signature);
    if (s >= key.n) return false;
    final em = bigIntToBytes(s.modPow(key.e, key.n), k);

    final hash = sha256.convert(ascii.encode(signingInput)).bytes;
    final t = [..._sha256DigestInfo, ...hash];
    if (k < t.length + 11) return false;
    final expected = Uint8List(k)
      ..[0] = 0x00
      ..[1] = 0x01;
    final psEnd = k - t.length - 1;
    for (var i = 2; i < psEnd; i++) {
      expected[i] = 0xff;
    }
    expected[psEnd] = 0x00;
    expected.setRange(psEnd + 1, k, t);

    // So sánh hết cả mảng, không dừng sớm.
    var diff = 0;
    for (var i = 0; i < k; i++) {
      diff |= em[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// Kiểm tra các claim theo yêu cầu của Firebase cho ID token
  /// (https://firebase.google.com/docs/auth/admin/verify-id-tokens).
  /// Trả về danh sách lỗi, rỗng nghĩa là hợp lệ.
  List<String> firebaseClaimProblems({
    required String projectId,
    DateTime? now,
    Duration leeway = const Duration(minutes: 5),
  }) {
    now ??= DateTime.now();
    final problems = <String>[];
    if (algorithm != 'RS256') {
      problems.add('alg phải là RS256 (đang là $algorithm)');
    }
    if (keyId == null || keyId!.isEmpty) problems.add('Thiếu kid trong header');
    final exp = expiresAt;
    if (exp == null) {
      problems.add('Thiếu exp');
    } else if (!exp.isAfter(now)) {
      problems.add('Token đã hết hạn');
    }
    final iat = issuedAt;
    if (iat == null) {
      problems.add('Thiếu iat');
    } else if (iat.isAfter(now.add(leeway))) {
      problems.add('iat nằm ở tương lai');
    }
    final auth = authTime;
    if (auth != null && auth.isAfter(now.add(leeway))) {
      problems.add('auth_time nằm ở tương lai');
    }
    if (!audience.contains(projectId)) {
      problems.add('aud phải là "$projectId"');
    }
    final iss = 'https://securetoken.google.com/$projectId';
    if (issuer != iss) problems.add('iss phải là "$iss"');
    if (subject == null || subject!.isEmpty) {
      problems.add('sub (uid) không được rỗng');
    } else if (subject!.length > 128) {
      problems.add('sub dài quá 128 ký tự');
    }
    return problems;
  }

  /// JSON có thụt lề để hiển thị.
  static String pretty(Map<String, dynamic> m) =>
      const JsonEncoder.withIndent('  ').convert(m);
}
