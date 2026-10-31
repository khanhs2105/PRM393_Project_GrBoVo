/// Định dạng và chia tiền VND. Tiền luôn là số nguyên (đồng), không dùng double.
library;

/// 150000 -> "150.000 ₫", -50000 -> "-50.000 ₫"
String formatVnd(int amount) {
  final digits = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}$buf ₫';
}

/// Đọc số tiền người dùng gõ: "150000", "150.000", "150,000", "150k", "1.5tr".
/// Trả về null nếu không hợp lệ.
int? parseVnd(String input) {
  var s = input.trim().toLowerCase().replaceAll(' ', '').replaceAll('₫', '');
  s = s.replaceAll('đ', '').replaceAll('vnd', '');
  if (s.isEmpty) return null;

  var multiplier = 1;
  if (s.endsWith('k') || s.endsWith('n')) {
    multiplier = 1000;
    s = s.substring(0, s.length - 1);
  } else if (s.endsWith('tr')) {
    multiplier = 1000000;
    s = s.substring(0, s.length - 2);
  }

  if (multiplier == 1) {
    // Không có hậu tố: dấu . và , là dấu phân cách hàng nghìn.
    s = s.replaceAll('.', '').replaceAll(',', '');
    final v = int.tryParse(s);
    return (v == null || v < 0) ? null : v;
  }
  // Có hậu tố: cho phép số thập phân, ví dụ "1.5tr" hoặc "1,5tr".
  final v = double.tryParse(s.replaceAll(',', '.'));
  if (v == null || v < 0) return null;
  return (v * multiplier).round();
}

/// Chia đều [amount] cho [memberIds].
///
/// Phần lẻ không chia hết (ví dụ 100.000 cho 3 người dư 1 đồng) được dồn cho
/// [remainderTo] (thường là người trả tiền). Nếu [remainderTo] không nằm trong
/// danh sách thì dồn cho người đầu tiên. Tổng kết quả luôn đúng bằng [amount].
Map<int, int> splitEqual(int amount, List<int> memberIds, {int? remainderTo}) {
  if (memberIds.isEmpty) {
    throw ArgumentError('Phải có ít nhất 1 người để chia');
  }
  if (amount < 0) throw ArgumentError('Số tiền không được âm');

  final ids = memberIds.toSet().toList();
  final base = amount ~/ ids.length;
  final remainder = amount % ids.length;
  final shares = {for (final id in ids) id: base};
  final target = ids.contains(remainderTo) ? remainderTo! : ids.first;
  shares[target] = shares[target]! + remainder;
  return shares;
}

/// Kiểm tra khi chia theo số tiền cụ thể: tổng các phần phải bằng [amount]
/// và không có phần nào âm.
bool sharesMatchTotal(int amount, Map<int, int> shares) {
  if (shares.values.any((v) => v < 0)) return false;
  return shares.values.fold<int>(0, (a, b) => a + b) == amount;
}
