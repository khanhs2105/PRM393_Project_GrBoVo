import 'package:chia_tien/services/vnpay_sandbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const data = 'vnp_Amount=2900000&vnp_Command=pay'
      '&vnp_CreateDate=20261103093000&vnp_CurrCode=VND'
      '&vnp_ExpireDate=20261103094500&vnp_IpAddr=127.0.0.1&vnp_Locale=vn'
      '&vnp_OrderInfo=Nang+cap+goi+chuNo+ma+ALO1&vnp_OrderType=other'
      '&vnp_ReturnUrl=https%3A%2F%2Falotratien.app%2Fvnpay-return'
      '&vnp_TmnCode=TESTCODE&vnp_TxnRef=ALO1&vnp_Version=2.1.0';
  const hash = '15c18e3039a3507b1975bc451b4986045961a893a65b19ed76536bbe5ff32edd'
      '9de5772a500b9c4af023377cc4ed666780f494dc40a3d68f8600f23090abbed2';

  test('URL VNPay: tham số xếp theo tên, giờ GMT+7, chữ ký HMAC-SHA512', () {
    final url = VnpaySandbox.buildPaymentUrl(
      amount: 29000,
      orderInfo: 'Nang cap goi chuNo ma ALO1',
      txnRef: 'ALO1',
      now: DateTime.utc(2026, 11, 3, 2, 30),
      tmnCode: 'TESTCODE',
      hashSecret: 'SECRET',
    );
    expect(url.toString(),
        '${VnpaySandbox.payUrl}?$data&vnp_SecureHash=$hash');
  });

  test('đọc kết quả trả về và kiểm chữ ký', () {
    final params = {
      'vnp_Amount': '2900000',
      'vnp_BankCode': 'NCB',
      'vnp_ResponseCode': '00',
      'vnp_TransactionStatus': '00',
      'vnp_TxnRef': 'ALO1',
      'vnp_TransactionNo': '14000001',
      'vnp_OrderInfo': 'Nang cap goi chuNo ma ALO1',
    };
    final sig =
        VnpaySandbox.hmacSha512('SECRET', VnpaySandbox.hashData(params));
    final ok = VnpaySandbox.parseReturn(
        Uri.parse('${VnpaySandbox.returnUrl}?'
            '${VnpaySandbox.hashData(params)}&vnp_SecureHashType=HmacSHA512'
            '&vnp_SecureHash=$sig'),
        hashSecret: 'SECRET');
    expect(ok.success, isTrue);
    expect(ok.bankCode, 'NCB');

    final tampered = VnpaySandbox.parseReturn(
        Uri.parse('${VnpaySandbox.returnUrl}?'
            '${VnpaySandbox.hashData({...params, 'vnp_Amount': '100'})}'
            '&vnp_SecureHash=$sig'),
        hashSecret: 'SECRET');
    expect(tampered.success, isFalse);
  });

  test('hủy giao dịch báo đúng lý do', () {
    final params = {'vnp_ResponseCode': '24', 'vnp_TransactionStatus': '02'};
    final sig =
        VnpaySandbox.hmacSha512('SECRET', VnpaySandbox.hashData(params));
    final r = VnpaySandbox.parseReturn(
        Uri.parse('${VnpaySandbox.returnUrl}?'
            '${VnpaySandbox.hashData(params)}&vnp_SecureHash=$sig'),
        hashSecret: 'SECRET');
    expect(r.success, isFalse);
    expect(r.message, 'Bạn đã hủy giao dịch');
  });
}
