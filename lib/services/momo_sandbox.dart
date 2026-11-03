import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Gọi cổng thanh toán MoMo môi trường THỬ NGHIỆM (test-payment.momo.vn).
///
/// Các khóa dưới đây là bộ khóa mẫu công khai trong tài liệu và code mẫu của
/// MoMo, chỉ dùng được ở sandbox, không trừ tiền thật. Ứng dụng thật phải
/// ký và tạo đơn trên server, không để secretKey trong app.
class MomoKeys {
  final String partnerCode;
  final String accessKey;
  final String secretKey;
  const MomoKeys(this.partnerCode, this.accessKey, this.secretKey);
}

class MomoSandbox {
  static const _endpoint = 'https://test-payment.momo.vn/v2/gateway/api';

  /// Bộ khóa trong code mẫu chính thức hiện tại của MoMo (API v2).
  static const officialKeys = MomoKeys(
      'MOMO', 'F8BBA842ECF85', 'K951B6PE1waDMi640xX08PD3vg6EkVlz');

  /// Bộ khóa mẫu cũ, nhiều tài khoản đã bị MoMo tắt một số kiểu thanh toán.
  static const legacyKeys = MomoKeys(
      'MOMOBKUN20180529', 'klm05TvNBzhg7h7j', 'at67qH6mk8w5Y1nAyMoYKMWACiEi2bsa');

  /// Thử lần lượt: MoMo có lúc từ chối một bộ khóa / kiểu thanh toán với
  /// mã 99 ("Declined due to general reasons"), nên lỗi thì thử cái sau.
  /// payWithMethod mở trang có đủ cách trả: QR ví, thẻ ATM, thẻ quốc tế.
  static const attempts = [
    (officialKeys, 'payWithMethod'),
    (officialKeys, 'captureWallet'),
    (legacyKeys, 'captureWallet'),
    (legacyKeys, 'payWithATM'),
  ];

  /// MoMo bắt buộc có hai URL này; app không có server nên dùng trang của
  /// MoMo và tự hỏi trạng thái đơn bằng [query].
  static const _redirectUrl = 'https://momo.vn';
  static const _ipnUrl = 'https://momo.vn';

  static const _timeout = Duration(seconds: 20);

  /// Ký HMAC-SHA256 chuỗi raw.
  static String sign(String raw, MomoKeys keys) =>
      Hmac(sha256, utf8.encode(keys.secretKey))
          .convert(utf8.encode(raw))
          .toString();

  /// Chuỗi raw để ký khi tạo đơn (khóa xếp theo bảng chữ cái).
  static String createRaw({
    required MomoKeys keys,
    required String orderId,
    required int amount,
    required String orderInfo,
    required String requestType,
  }) =>
      'accessKey=${keys.accessKey}&amount=$amount&extraData='
      '&ipnUrl=$_ipnUrl&orderId=$orderId&orderInfo=$orderInfo'
      '&partnerCode=${keys.partnerCode}&redirectUrl=$_redirectUrl'
      '&requestId=$orderId&requestType=$requestType';

  /// Tạo đơn, thử lần lượt các cách trong [attempts] cho tới khi MoMo nhận.
  static Future<MomoOrder> create({
    required int amount,
    required String orderInfo,
  }) async {
    Object? lastError;
    for (final (keys, type) in attempts) {
      try {
        return await _create(keys, type, amount, orderInfo);
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? MomoException('MoMo từ chối tạo đơn', -1);
  }

  static Future<MomoOrder> _create(
      MomoKeys keys, String requestType, int amount, String orderInfo) async {
    final orderId = 'ALO${DateTime.now().microsecondsSinceEpoch}';
    final body = {
      'partnerCode': keys.partnerCode,
      'accessKey': keys.accessKey,
      'requestId': orderId,
      'amount': amount,
      'orderId': orderId,
      'orderInfo': orderInfo,
      'redirectUrl': _redirectUrl,
      'ipnUrl': _ipnUrl,
      'extraData': '',
      'requestType': requestType,
      'autoCapture': true,
      'lang': 'vi',
      'signature': sign(
          createRaw(
            keys: keys,
            orderId: orderId,
            amount: amount,
            orderInfo: orderInfo,
            requestType: requestType,
          ),
          keys),
    };
    final res = await _post('$_endpoint/create', body);
    final code = res['resultCode'];
    final payUrl = res['payUrl'];
    if (code != 0 || payUrl is! String || payUrl.isEmpty) {
      throw MomoException(res['message']?.toString() ?? 'MoMo từ chối tạo đơn',
          code is int ? code : -1);
    }
    return MomoOrder(orderId, payUrl, keys);
  }

  /// Hỏi trạng thái đơn. resultCode 0 là đã thanh toán, 1000 là đang chờ
  /// người dùng xác nhận, 7000/7002 là đang xử lý; mã khác là thất bại/hủy.
  static Future<int> query(MomoOrder order) async {
    final keys = order.keys;
    final raw = 'accessKey=${keys.accessKey}&orderId=${order.orderId}'
        '&partnerCode=${keys.partnerCode}&requestId=${order.orderId}';
    final res = await _post('$_endpoint/query', {
      'partnerCode': keys.partnerCode,
      'accessKey': keys.accessKey,
      'requestId': order.orderId,
      'orderId': order.orderId,
      'lang': 'vi',
      'signature': sign(raw, keys),
    });
    final code = res['resultCode'];
    return code is int ? code : -1;
  }

  /// Các mã còn đang chờ, chưa phải kết quả cuối.
  static bool isPending(int code) =>
      code == 1000 || code == 7000 || code == 7002 || code == 9000;

  static Future<Map<String, dynamic>> _post(
      String url, Map<String, dynamic> body) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final req = await client.postUrl(Uri.parse(url)).timeout(_timeout);
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode(body)));
      final resp = await req.close().timeout(_timeout);
      final text = await resp.transform(utf8.decoder).join().timeout(_timeout);
      final data = jsonDecode(text);
      if (data is! Map<String, dynamic>) {
        throw MomoException('MoMo trả về dữ liệu lạ', -1);
      }
      return data;
    } finally {
      client.close();
    }
  }
}

class MomoOrder {
  final String orderId;
  final String payUrl;

  /// Bộ khóa đã tạo đơn; hỏi trạng thái phải ký bằng đúng bộ này.
  final MomoKeys keys;
  const MomoOrder(this.orderId, this.payUrl, this.keys);
}

class MomoException implements Exception {
  final String message;
  final int code;
  MomoException(this.message, this.code);
  @override
  String toString() => 'MoMo: $message (mã $code)';
}
