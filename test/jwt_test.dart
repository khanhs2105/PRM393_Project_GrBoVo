import 'dart:convert';

import 'package:chia_tien/logic/jwt.dart';
import 'package:flutter_test/flutter_test.dart';

// Token mẫu có cùng cấu trúc với ID token của Firebase, ký bằng một khóa RSA
// 2048 bit tạo riêng cho test (không phải khóa thật của Google).
const token =
    'eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2V5LTEiLCJ0eXAiOiJKV1QifQ.eyJuYW1'
    'lIjoiSHV5IiwiaXNzIjoiaHR0cHM6Ly9zZWN1cmV0b2tlbi5nb29nbGUuY29tL2NoaXBpb'
    'i10ZXN0IiwiYXVkIjoiY2hpcGluLXRlc3QiLCJhdXRoX3RpbWUiOjE3OTM1MDAwMDAsInV'
    'zZXJfaWQiOiJ1aWQxMjMiLCJzdWIiOiJ1aWQxMjMiLCJpYXQiOjE3OTM1MDAwMDAsImV4c'
    'CI6MTc5MzUwMzYwMCwiZW1haWwiOiJodXlAZXhhbXBsZS5jb20iLCJlbWFpbF92ZXJpZml'
    'lZCI6ZmFsc2UsImZpcmViYXNlIjp7ImlkZW50aXRpZXMiOnsiZW1haWwiOlsiaHV5QGV4Y'
    'W1wbGUuY29tIl19LCJzaWduX2luX3Byb3ZpZGVyIjoicGFzc3dvcmQifX0.kXXmshrxe84'
    'EEXp-qeLHQmLK8Tfljdb8EBwNCOhdWSRxbKQ7c2DhsqYZ-crTghwpSgwNtD06hgAQ32Rc1'
    'dJCmr3UPoWalTvIjfCQsJS5rgJTls9JC3EtAE3uu5L5fAu5qU3sYtvg2yDK8fqNEWWjQ46'
    'uTL1cRGhuPkqAxdlM7sRQC3hLWC4ie7EbtgWJhKbZKvf1QjVkSdoyZmvSX5F36oSEP0v0F'
    'ouBnodcJ5h_X7Ll4_oZ57iqgfj0-HXxWsEDe7WxgG4JAg1IJ32Kxa4OfSWpSTdP41Hvmcn'
    'IckR9QZxewThkZXueOcs0mC1UGY5GFrZlVlphiIoaL8AOyQa7Zw';

const jwk = {
  'kty': 'RSA',
  'kid': 'test-key-1',
  'e': 'AQAB',
  'n':
    'qy5639yn_AzJMbypDG0ZouxaxBWgvs51DTajIvyEgSNmtVUK_rQMpzjiKDoNOYxHRFaYBb'
    'nkyIRJXj-DSoCcASlvGhzcW-5EkXy20LgiVDdvodVBuTeA5NkixGJgtJ-ts8fBZroeuU2d'
    'jdFcTpnqC6eX-ZPQqP0qKKCcyfvW-9Zzw3WLsrAFEq8pUTK6ooj-xToxBFfTCZklUs3aPR'
    '23Rrrq1EAzVyIkE0VVSlQ_I9zkrRlq-NcqqPfIJjGkGshHg0vc1OUhqdXc1ol74D98299U'
    'LID1Mi5dBrWAqM3Ttqf0FdxrzpDSMYgH-Ad7Mg0zHLssnDSbkumkjfQu49wq4w',
};

final issued = DateTime.fromMillisecondsSinceEpoch(1793500000 * 1000, isUtc: true);

void main() {
  final key = RsaPublicKey.fromJwk(jwk);

  test('tách được header và payload', () {
    final jwt = Jwt.parse(token);
    expect(jwt.algorithm, 'RS256');
    expect(jwt.keyId, 'test-key-1');
    expect(jwt.subject, 'uid123');
    expect(jwt.email, 'huy@example.com');
    expect(jwt.audience, ['chipin-test']);
    expect(jwt.issuedAt, issued);
    expect(jwt.expiresAt, issued.add(const Duration(hours: 1)));
  });

  test('chữ ký RS256 đúng với khóa công khai', () {
    expect(key.byteLength, 256);
    expect(Jwt.parse(token).verifyRs256(key), isTrue);
  });

  test('sửa payload thì chữ ký sai', () {
    final parts = token.split('.');
    final payload = jsonDecode(utf8.decode(base64UrlDecode(parts[1])))
        as Map<String, dynamic>;
    payload['sub'] = 'hacker';
    final forged = [
      parts[0],
      base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', ''),
      parts[2],
    ].join('.');
    final jwt = Jwt.parse(forged);
    expect(jwt.subject, 'hacker');
    expect(jwt.verifyRs256(key), isFalse);
  });

  test('khóa khác thì chữ ký sai', () {
    final other = RsaPublicKey(key.n - BigInt.two, key.e);
    expect(Jwt.parse(token).verifyRs256(other), isFalse);
  });

  test('claim Firebase hợp lệ khi còn hạn', () {
    final jwt = Jwt.parse(token);
    final now = issued.add(const Duration(minutes: 10));
    expect(jwt.firebaseClaimProblems(projectId: 'chipin-test', now: now),
        isEmpty);
    expect(jwt.isExpired(now), isFalse);
    expect(jwt.timeLeft(now), const Duration(minutes: 50));
  });

  test('báo lỗi khi hết hạn hoặc sai project', () {
    final jwt = Jwt.parse(token);
    final later = issued.add(const Duration(hours: 2));
    expect(jwt.isExpired(later), isTrue);
    expect(jwt.firebaseClaimProblems(projectId: 'chipin-test', now: later),
        contains('Token đã hết hạn'));
    final wrong = jwt.firebaseClaimProblems(
        projectId: 'khac', now: issued.add(const Duration(minutes: 1)));
    expect(wrong, hasLength(2)); // sai aud và sai iss
  });

  test('đọc được JWKS', () {
    final keys = parseJwks(jsonEncode({
      'keys': [jwk]
    }));
    expect(keys.keys, ['test-key-1']);
    expect(keys['test-key-1']!.n, key.n);
    expect(key.e, BigInt.from(65537));
  });

  test('chuỗi không phải JWT thì báo lỗi', () {
    expect(() => Jwt.parse('abc'), throwsFormatException);
    expect(() => Jwt.parse('a.b.c'), throwsFormatException);
  });
}
