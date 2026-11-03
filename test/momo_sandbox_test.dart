import 'package:chia_tien/services/momo_sandbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chuỗi ký tạo đơn MoMo đúng thứ tự và chữ ký HMAC-SHA256', () {
    final raw = MomoSandbox.createRaw(
      keys: MomoSandbox.officialKeys,
      orderId: 'ALO1',
      amount: 29000,
      orderInfo: 'Test',
      requestType: 'payWithMethod',
    );
    expect(
        raw,
        'accessKey=F8BBA842ECF85&amount=29000&extraData='
        '&ipnUrl=https://momo.vn&orderId=ALO1&orderInfo=Test'
        '&partnerCode=MOMO&redirectUrl=https://momo.vn'
        '&requestId=ALO1&requestType=payWithMethod');
    expect(MomoSandbox.sign(raw, MomoSandbox.officialKeys),
        '893879e13bbe7debdb9c6bacfa1e54710779fd714a8330e6d2a9a985276d3894');
  });

  test('thử bộ khóa chính thức trước, bộ khóa cũ sau', () {
    expect(MomoSandbox.attempts.first.$1.partnerCode, 'MOMO');
    expect(MomoSandbox.attempts.first.$2, 'payWithMethod');
    expect(MomoSandbox.attempts.last.$1.partnerCode, 'MOMOBKUN20180529');
  });

  test('mã đang chờ của MoMo', () {
    expect(MomoSandbox.isPending(1000), isTrue);
    expect(MomoSandbox.isPending(0), isFalse);
    expect(MomoSandbox.isPending(99), isFalse);
  });
}
