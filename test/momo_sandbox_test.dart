import 'package:chia_tien/services/momo_sandbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chuỗi ký tạo đơn MoMo đúng thứ tự và chữ ký HMAC-SHA256', () {
    final raw = MomoSandbox.createRaw(
      orderId: 'ALO1',
      amount: 29000,
      orderInfo: 'Test',
      requestType: 'payWithATM',
    );
    expect(
        raw,
        'accessKey=klm05TvNBzhg7h7j&amount=29000&extraData='
        '&ipnUrl=https://momo.vn&orderId=ALO1&orderInfo=Test'
        '&partnerCode=MOMOBKUN20180529&redirectUrl=https://momo.vn'
        '&requestId=ALO1&requestType=payWithATM');
    expect(MomoSandbox.sign(raw),
        '8dac2e27599736a0ad48eb31ee6eb64d064c9b3e46a4b9b5bc0b1a603a4fb319');
  });

  test('mã đang chờ của MoMo', () {
    expect(MomoSandbox.isPending(1000), isTrue);
    expect(MomoSandbox.isPending(0), isFalse);
    expect(MomoSandbox.isPending(1006), isFalse);
  });
}
