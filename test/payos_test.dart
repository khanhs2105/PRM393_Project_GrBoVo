import 'package:chia_tien/services/payos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Body tạo link PayOS: ký HMAC-SHA256 trên 5 trường xếp theo tên', () {
    final body = Payos.buildCreateBody(
      orderCode: 123,
      amount: 29000,
      description: 'CHIPIN',
      checksumKey: 'KEY',
    );
    expect(body['returnUrl'], Payos.returnUrl);
    expect(body['cancelUrl'], Payos.cancelUrl);
    // Tính độc lập bằng HMACSHA256 của .NET.
    expect(
      body['signature'],
      'e8874b0ae404e41968b4e08cee22c2c433058cbff6af5d0b5449e335cb3391a1',
    );
  });

  test('Đọc URL PayOS trả về', () {
    final ok = Payos.parseReturn(
      Uri.parse(
        '${Payos.returnUrl}'
        '?code=00&id=abc&cancel=false&status=PAID&orderCode=123',
      ),
    );
    expect(ok.cancelled, isFalse);
    expect(ok.status, 'PAID');
    expect(ok.orderCode, 123);

    final cancel = Payos.parseReturn(
      Uri.parse(
        '${Payos.cancelUrl}'
        '?code=00&id=abc&cancel=true&status=CANCELLED&orderCode=123',
      ),
    );
    expect(cancel.cancelled, isTrue);
    expect(Payos.isResultUrl(Payos.cancelUrl), isTrue);
    expect(Payos.isResultUrl('https://pay.payos.vn/web/abc'), isFalse);
  });
}
