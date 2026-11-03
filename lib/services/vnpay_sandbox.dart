import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Khóa VNPay sandbox của nhóm (đăng ký miễn phí tại
/// https://sandbox.vnpayment.vn/devreg/, VNPay gửi về email).
/// Chỉ dùng cho môi trường thử nghiệm: app thật phải tạo URL và kiểm chữ ký
/// trên server, không để HashSecret trong app.
class VnpayConfig {
  static const tmnCode = 'DIEN_TMN_CODE';
  static const hashSecret = 'DIEN_HASH_SECRET';

  static bool get isConfigured =>
      !tmnCode.startsWith('DIEN_') && !hashSecret.startsWith('DIEN_');
}

/// Kết quả VNPay trả về qua returnUrl.
class VnpayResult {
  final bool validSignature;
  final String responseCode;
  final String transactionStatus;
  final String txnRef;
  final String transactionNo;
  final String bankCode;

  const VnpayResult({
    required this.validSignature,
    required this.responseCode,
    required this.transactionStatus,
    required this.txnRef,
    required this.transactionNo,
    required this.bankCode,
  });

  bool get success =>
      validSignature && responseCode == '00' && transactionStatus == '00';

  /// Câu giải thích cho các mã lỗi hay gặp.
  String get message {
    if (!validSignature) return 'Chữ ký trả về không hợp lệ';
    return switch (responseCode) {
      '00' => 'Giao dịch thành công',
      '07' => 'Giao dịch bị nghi ngờ gian lận',
      '09' => 'Thẻ chưa đăng ký Internet Banking',
      '10' => 'Xác thực thông tin thẻ sai quá 3 lần',
      '11' => 'Hết hạn chờ thanh toán',
      '12' => 'Thẻ bị khóa',
      '13' => 'Nhập sai OTP',
      '24' => 'Bạn đã hủy giao dịch',
      '51' => 'Tài khoản không đủ số dư',
      '65' => 'Vượt hạn mức giao dịch trong ngày',
      '75' => 'Ngân hàng đang bảo trì',
      '79' => 'Nhập sai mật khẩu quá số lần quy định',
      _ => 'Giao dịch không thành công (mã $responseCode)',
    };
  }
}

/// Tạo URL thanh toán VNPay sandbox (API 2.1.0) và kiểm kết quả trả về.
class VnpaySandbox {
  static const payUrl = 'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html';

  /// Không cần server thật: WebView chặn URL này lại để đọc kết quả.
  static const returnUrl = 'https://alotratien.app/vnpay-return';

  /// Mã hóa giống URLEncoder của Java / urlencode của PHP (dấu cách -> +),
  /// đúng như code mẫu của VNPay khi tạo chuỗi ký.
  static String _enc(String s) => Uri.encodeQueryComponent(s);

  /// Chuỗi dữ liệu để ký: các tham số xếp theo tên, nối bằng &.
  static String hashData(Map<String, String> params) {
    final keys = params.keys
        .where((k) => params[k] != null && params[k]!.isNotEmpty)
        .toList()
      ..sort();
    return keys.map((k) => '${_enc(k)}=${_enc(params[k]!)}').join('&');
  }

  static String hmacSha512(String secret, String data) =>
      Hmac(sha512, utf8.encode(secret)).convert(utf8.encode(data)).toString();

  /// yyyyMMddHHmmss theo giờ Việt Nam (GMT+7) như VNPay yêu cầu.
  static String vnTime(DateTime t) {
    final v = t.toUtc().add(const Duration(hours: 7));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${v.year}${two(v.month)}${two(v.day)}'
        '${two(v.hour)}${two(v.minute)}${two(v.second)}';
  }

  /// Dựng URL mở trang thanh toán. [amount] tính bằng đồng.
  static Uri buildPaymentUrl({
    required int amount,
    required String orderInfo,
    required String txnRef,
    DateTime? now,
    String tmnCode = VnpayConfig.tmnCode,
    String hashSecret = VnpayConfig.hashSecret,
  }) {
    final created = now ?? DateTime.now();
    final params = <String, String>{
      'vnp_Version': '2.1.0',
      'vnp_Command': 'pay',
      'vnp_TmnCode': tmnCode,
      'vnp_Amount': '${amount * 100}',
      'vnp_CurrCode': 'VND',
      'vnp_TxnRef': txnRef,
      'vnp_OrderInfo': orderInfo,
      'vnp_OrderType': 'other',
      'vnp_Locale': 'vn',
      'vnp_ReturnUrl': returnUrl,
      'vnp_IpAddr': '127.0.0.1',
      'vnp_CreateDate': vnTime(created),
      'vnp_ExpireDate': vnTime(created.add(const Duration(minutes: 15))),
    };
    final data = hashData(params);
    final hash = hmacSha512(hashSecret, data);
    return Uri.parse('$payUrl?$data&vnp_SecureHash=$hash');
  }

  /// Đọc và kiểm chữ ký URL VNPay chuyển về returnUrl.
  static VnpayResult parseReturn(Uri uri,
      {String hashSecret = VnpayConfig.hashSecret}) {
    final q = Map<String, String>.from(uri.queryParameters);
    final received = q.remove('vnp_SecureHash') ?? '';
    q.remove('vnp_SecureHashType');
    q.removeWhere((k, _) => !k.startsWith('vnp_'));
    final expected = hmacSha512(hashSecret, hashData(q));
    return VnpayResult(
      validSignature: expected.toLowerCase() == received.toLowerCase(),
      responseCode: q['vnp_ResponseCode'] ?? '',
      transactionStatus: q['vnp_TransactionStatus'] ?? '',
      txnRef: q['vnp_TxnRef'] ?? '',
      transactionNo: q['vnp_TransactionNo'] ?? '',
      bankCode: q['vnp_BankCode'] ?? '',
    );
  }

  static bool isReturnUrl(String url) => url.startsWith(returnUrl);
}
