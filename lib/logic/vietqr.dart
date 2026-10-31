/// Tạo link ảnh QR chuyển khoản qua VietQR Quick Link (img.vietqr.io).
/// Không cần API key. Hiển thị bằng Image.network(url).
library;

/// compact | compact2 | qr_only | print
String vietQrImageUrl({
  required String bin,
  required String accountNo,
  required int amount,
  required String note,
  String? accountName,
  String template = 'compact2',
}) {
  final query = <String, String>{
    if (amount > 0) 'amount': '$amount',
    if (note.isNotEmpty) 'addInfo': transferNote(note),
    if (accountName != null && accountName.isNotEmpty)
      'accountName': removeDiacritics(accountName).toUpperCase(),
  };
  // Mã hóa khoảng trắng thành %20 (Uri.https mặc định dùng dấu +).
  final qs = query.entries
      .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
      .join('&');
  return 'https://img.vietqr.io/image/$bin-$accountNo-$template.png'
      '${qs.isEmpty ? '' : '?$qs'}';
}

/// Nội dung chuyển khoản: bỏ dấu, viết hoa, chỉ giữ chữ số và khoảng trắng,
/// cắt còn [maxLength] ký tự vì nhiều ngân hàng giới hạn độ dài nội dung.
String transferNote(String text, {int maxLength = 25}) {
  final cleaned = removeDiacritics(text)
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.length <= maxLength
      ? cleaned
      : cleaned.substring(0, maxLength).trim();
}

/// Gợi ý nội dung: "HUY TRA NAM PHONG 302"
String suggestedNote(String fromName, String toName, String groupName) =>
    transferNote('$fromName tra $toName $groupName');

const _withDiacritics =
    'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ'
    'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
const _withoutDiacritics =
    'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd'
    'AAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';

/// "Nguyễn Văn Đức" -> "Nguyen Van Duc"
String removeDiacritics(String s) {
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final i = _withDiacritics.indexOf(ch);
    buf.write(i >= 0 ? _withoutDiacritics[i] : ch);
  }
  // Một số bàn phím gõ dấu dạng tổ hợp (chữ + dấu rời), bỏ luôn các dấu rời.
  return buf.toString().replaceAll(RegExp('[\u0300-\u036f]'), '');
}
