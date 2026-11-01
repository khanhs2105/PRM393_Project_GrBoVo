import 'dart:convert';
import 'dart:io';

import '../logic/jwt.dart';

/// Kết quả kiểm tra một ID token.
class JwtCheck {
  final Jwt jwt;
  final bool signatureValid;
  final List<String> claimProblems;

  /// Lỗi khi tải khóa công khai (không có mạng...). null là tải được.
  final String? keyError;

  const JwtCheck(this.jwt, this.signatureValid, this.claimProblems,
      [this.keyError]);

  bool get ok => signatureValid && claimProblems.isEmpty;
}

/// Tự kiểm tra ID token của Firebase ngay trên máy, giống cách server làm:
/// 1. Tải khóa công khai của Google (JWKS) theo `kid` trong header.
/// 2. Kiểm chữ ký RS256.
/// 3. Kiểm các claim: exp, iat, aud, iss, sub.
///
/// Thực tế Firestore cũng kiểm token này ở phía server rồi mới cho đọc/ghi
/// (biến request.auth trong firestore.rules). Màn này để nhìn thấy quá trình đó.
class FirebaseJwtVerifier {
  static const jwksUrl =
      'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

  Map<String, RsaPublicKey> _keys = const {};
  DateTime? _fetchedAt;

  Future<Map<String, RsaPublicKey>> _loadKeys({bool force = false}) async {
    final fresh = _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(hours: 1);
    if (!force && fresh && _keys.isNotEmpty) return _keys;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(jwksUrl));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw HttpException('Tải khóa lỗi HTTP ${res.statusCode}');
      }
      _keys = parseJwks(await res.transform(utf8.decoder).join());
      _fetchedAt = DateTime.now();
      return _keys;
    } finally {
      client.close();
    }
  }

  Future<JwtCheck> verify(String token, {required String projectId}) async {
    final jwt = Jwt.parse(token);
    final problems = jwt.firebaseClaimProblems(projectId: projectId);
    try {
      var keys = await _loadKeys();
      // Google đổi khóa định kỳ: không thấy kid thì tải lại một lần.
      if (!keys.containsKey(jwt.keyId)) keys = await _loadKeys(force: true);
      final key = keys[jwt.keyId];
      if (key == null) {
        return JwtCheck(jwt, false, problems,
            'Không tìm thấy khóa công khai có kid = ${jwt.keyId}');
      }
      return JwtCheck(jwt, jwt.verifyRs256(key), problems);
    } catch (e) {
      return JwtCheck(jwt, false, problems, 'Không tải được khóa công khai: $e');
    }
  }
}
