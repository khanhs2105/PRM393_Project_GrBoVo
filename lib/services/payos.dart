import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Khóa PayOS của nhóm (đăng ký tại https://my.payos.vn, tạo "Kênh thanh
/// toán" gắn tài khoản ngân hàng, rồi copy 3 khóa ở trang kênh đó).
/// PayOS không có sandbox: tiền chuyển là tiền thật, vào thẳng tài khoản
/// ngân hàng đã gắn. App thật phải gọi PayOS từ server, không để khóa trong app.
class PayosConfig {
  static const clientId = 'c66c75c2-57ba-42f2-ba7e-814c6c26962c';
  static const apiKey = 'e9e17a00-b91e-4bb8-bc4c-732a9c23cb41';
  static const checksumKey = 'da85855d62b530b9efaef65c018a92851afc355696adfde53ea7bf27ec8a9f37';

  static bool get isConfigured => true;
}

/// Link thanh toán PayOS vừa tạo.
class PayosLink {
  final int orderCode;
  final Uri checkoutUrl;
  const PayosLink(this.orderCode, this.checkoutUrl);
}

/// Kết quả PayOS chuyển về returnUrl / cancelUrl.
class PayosReturn {
  final String code;
  final String status;
  final bool cancelled;
  final int? orderCode;

  const PayosReturn({
    required this.code,
    required this.status,
    required this.cancelled,
    required this.orderCode,
  });
}

class PayosException implements Exception {
  final String message;
  PayosException(this.message);
  @override
  String toString() => message;
}

/// Tạo link thanh toán PayOS (VietQR) và hỏi lại trạng thái đơn.
class Payos {
  static const apiBase = 'https://api-merchant.payos.vn';

  /// Không cần server thật: WebView chặn 2 URL này lại để đọc kết quả.
  static const returnUrl = 'https://alotratien.app/payos-return';
  static const cancelUrl = 'https://alotratien.app/payos-cancel';

  /// Chuỗi ký theo tài liệu PayOS: 5 trường xếp theo tên, nối bằng &.
  static String signatureData({
    required int amount,
    required String cancelUrl,
    required String description,
    required int orderCode,
    required String returnUrl,
  }) =>
      'amount=$amount&cancelUrl=$cancelUrl&description=$description'
      '&orderCode=$orderCode&returnUrl=$returnUrl';

  static String hmacSha256(String key, String data) =>
      Hmac(sha256, utf8.encode(key)).convert(utf8.encode(data)).toString();

  /// Thân request tạo link. [description] tối đa 25 ký tự (tài khoản ngân
  /// hàng chưa liên kết thì PayOS chỉ nhận 9 ký tự).
  static Map<String, Object> buildCreateBody({
    required int orderCode,
    required int amount,
    required String description,
    String checksumKey = PayosConfig.checksumKey,
  }) {
    final sig = hmacSha256(
      checksumKey,
      signatureData(
        amount: amount,
        cancelUrl: cancelUrl,
        description: description,
        orderCode: orderCode,
        returnUrl: returnUrl,
      ),
    );
    return {
      'orderCode': orderCode,
      'amount': amount,
      'description': description,
      'returnUrl': returnUrl,
      'cancelUrl': cancelUrl,
      'signature': sig,
    };
  }

  static Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Map<String, Object>? body,
  ]) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(method, Uri.parse('$apiBase$path'));
      req.headers
        ..set('x-client-id', PayosConfig.clientId)
        ..set('x-api-key', PayosConfig.apiKey)
        ..contentType = ContentType.json;
      if (body != null) req.write(jsonEncode(body));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['code'] != '00' || json['data'] == null) {
        throw PayosException('PayOS báo lỗi ${json['code']}: ${json['desc']}');
      }
      return json['data'] as Map<String, dynamic>;
    } on SocketException {
      throw PayosException('Không kết nối được PayOS, kiểm tra mạng');
    } on FormatException {
      throw PayosException('PayOS trả về dữ liệu lạ');
    } finally {
      client.close();
    }
  }

  /// Gọi PayOS tạo link thanh toán. [amount] tính bằng đồng.
  static Future<PayosLink> createLink({
    required int amount,
    required String description,
  }) async {
    // orderCode phải là số nguyên dương, không trùng giữa các đơn.
    final orderCode = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final data = await _call(
      'POST',
      '/v2/payment-requests',
      buildCreateBody(
        orderCode: orderCode,
        amount: amount,
        description: description,
      ),
    );
    return PayosLink(orderCode, Uri.parse(data['checkoutUrl'] as String));
  }

  /// Hỏi lại PayOS trạng thái đơn (PENDING, PAID, CANCELLED...). URL trả về
  /// không có chữ ký nên phải hỏi lại server PayOS mới tin được là đã trả.
  static Future<String> getStatus(int orderCode) async {
    final data = await _call('GET', '/v2/payment-requests/$orderCode');
    return data['status'] as String? ?? '';
  }

  static bool isResultUrl(String url) =>
      url.startsWith(returnUrl) || url.startsWith(cancelUrl);

  static PayosReturn parseReturn(Uri uri) {
    final q = uri.queryParameters;
    return PayosReturn(
      code: q['code'] ?? '',
      status: q['status'] ?? '',
      cancelled: q['cancel'] == 'true' || uri.toString().startsWith(cancelUrl),
      orderCode: int.tryParse(q['orderCode'] ?? ''),
    );
  }
}
