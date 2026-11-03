/// Đọc mã QR chuyển khoản ngân hàng Việt Nam (chuẩn EMVCo, NAPAS 247 / VietQR).
///
/// Mã QR là một chuỗi các trường TLV nối nhau:
///   [tag 2 chữ số][độ dài 2 chữ số][giá trị]
/// Ví dụ "000201" là tag 00, dài 02, giá trị "01".
///
/// Các tag cần dùng:
///   38  thông tin người nhận (NAPAS), bên trong lại là TLV:
///       00  GUID, luôn là "A000000727"
///       01  thông tin tài khoản, bên trong lại là TLV:
///           00  BIN ngân hàng (6 số, ví dụ 970436)
///           01  số tài khoản hoặc số thẻ
///       02  "QRIBFTTA" (chuyển vào tài khoản) hoặc "QRIBFTTC" (vào thẻ)
///   54  số tiền (không bắt buộc)
///   59  tên người nhận (không bắt buộc, nhiều ngân hàng không ghi)
///   62  thông tin thêm, sub-tag 08 là nội dung chuyển khoản
///   63  mã kiểm tra CRC-16 của toàn bộ chuỗi phía trước
library;

const napasGuid = 'A000000727';

class BankAccountQr {
  final String bin;
  final String accountNo;
  final String? accountName;
  final int? amount;
  final String? note;

  const BankAccountQr({
    required this.bin,
    required this.accountNo,
    this.accountName,
    this.amount,
    this.note,
  });

  @override
  String toString() =>
      'BankAccountQr(bin: $bin, accountNo: $accountNo, name: $accountName)';
}

/// Tách chuỗi thành map tag -> giá trị. Trả về null nếu chuỗi sai cấu trúc.
Map<String, String>? parseTlv(String data) {
  final result = <String, String>{};
  var i = 0;
  while (i < data.length) {
    if (i + 4 > data.length) return null;
    final tag = data.substring(i, i + 2);
    final lenText = data.substring(i + 2, i + 4);
    // Độ dài luôn là 2 chữ số (chặn "-1" làm substring ném RangeError).
    if (!RegExp(r'^\d\d$').hasMatch(lenText)) return null;
    final len = int.parse(lenText);
    if (i + 4 + len > data.length) return null;
    result[tag] = data.substring(i + 4, i + 4 + len);
    i += 4 + len;
  }
  return result;
}

/// CRC-16/CCITT-FALSE (đa thức 0x1021, giá trị đầu 0xFFFF), in hoa 4 ký tự hex.
String crc16(String data) {
  var crc = 0xFFFF;
  for (final byte in data.codeUnits) {
    crc ^= (byte & 0xFF) << 8;
    for (var b = 0; b < 8; b++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
}

/// Kiểm tra mã CRC ở cuối chuỗi (tag 63 luôn nằm cuối, dài 4).
bool hasValidCrc(String raw) {
  if (raw.length < 8) return false;
  final body = raw.substring(0, raw.length - 4);
  if (!body.endsWith('6304')) return false;
  return crc16(body) == raw.substring(raw.length - 4).toUpperCase();
}

/// Đọc QR ngân hàng. Trả về null nếu đây không phải QR chuyển khoản NAPAS
/// (ví dụ QR MoMo, QR link web) hoặc mã bị hỏng.
BankAccountQr? parseBankQr(String raw, {bool checkCrc = true}) {
  final data = raw.trim();
  if (checkCrc && !hasValidCrc(data)) return null;

  final root = parseTlv(data);
  if (root == null || root['00'] != '01') return null;

  final merchant = root['38'];
  if (merchant == null) return null;
  final m = parseTlv(merchant);
  if (m == null || m['00'] != napasGuid || m['01'] == null) return null;

  final beneficiary = parseTlv(m['01']!);
  final bin = beneficiary?['00'];
  final accountNo = beneficiary?['01'];
  if (bin == null || accountNo == null || bin.isEmpty || accountNo.isEmpty) {
    return null;
  }

  final name = root['59']?.trim();
  final additional = root['62'] == null ? null : parseTlv(root['62']!);
  return BankAccountQr(
    bin: bin,
    accountNo: accountNo,
    accountName: (name == null || name.isEmpty) ? null : name,
    amount: _qrAmount(root['54']),
    note: additional?['08'],
  );
}

/// Tạo chuỗi QR chuyển khoản (chiều ngược lại của [parseBankQr]).
/// App dùng ảnh từ img.vietqr.io nên không cần hàm này để hiển thị, nhưng nó
/// tiện cho unit test và cho trường hợp muốn tự vẽ QR khi không có mạng.
String buildBankQr({
  required String bin,
  required String accountNo,
  int? amount,
  String? note,
}) {
  String tlv(String tag, String value) =>
      '$tag${value.length.toString().padLeft(2, '0')}$value';

  final beneficiary = tlv('00', bin) + tlv('01', accountNo);
  final merchant =
      tlv('00', napasGuid) + tlv('01', beneficiary) + tlv('02', 'QRIBFTTA');
  final body = StringBuffer()
    ..write(tlv('00', '01'))
    ..write(tlv('01', amount == null ? '11' : '12')) // 11 tĩnh, 12 động
    ..write(tlv('38', merchant))
    ..write(tlv('53', '704')) // VND
    ..write(amount == null ? '' : tlv('54', '$amount'))
    ..write(tlv('58', 'VN'))
    ..write(note == null || note.isEmpty ? '' : tlv('62', tlv('08', note)))
    ..write('6304');
  return '$body${crc16(body.toString())}';
}

/// Số tiền trong QR (tag 54): chỉ nhận số không âm dạng "50000" hoặc
/// "50000.00". "NaN", "Infinity", số âm hay số mũ thì bỏ qua (null).
int? _qrAmount(String? raw) {
  if (raw == null || !RegExp(r'^\d+(\.\d+)?$').hasMatch(raw)) return null;
  final v = double.tryParse(raw);
  if (v == null || !v.isFinite || v > 1e12) return null;
  return v.round();
}
