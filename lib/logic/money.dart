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

/// Chia [amount] theo trọng số: chia theo phần (2:1:1) hoặc theo % (trọng số
/// là phần vạn, 100% = 10000).
///
/// Dùng phương pháp phần dư lớn nhất: mỗi người nhận phần nguyên trước, số
/// đồng còn dư chia lần lượt cho người có phần lẻ lớn nhất. Nếu bằng nhau thì
/// ưu tiên [remainderTo] rồi theo thứ tự trong [weights]. Tổng luôn bằng
/// [amount]. Người có trọng số 0 bị bỏ khỏi kết quả.
Map<int, int> splitByWeights(Map<int, int> weights, int amount,
    {int? remainderTo}) {
  if (amount < 0) throw ArgumentError('Số tiền không được âm');
  if (weights.values.any((w) => w < 0)) {
    throw ArgumentError('Trọng số không được âm');
  }
  final active = {
    for (final e in weights.entries)
      if (e.value > 0) e.key: e.value,
  };
  final total = active.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) throw ArgumentError('Phải có ít nhất 1 người để chia');

  final shares = <int, int>{};
  final fractions = <int, int>{};
  var given = 0;
  active.forEach((id, w) {
    shares[id] = amount * w ~/ total;
    fractions[id] = amount * w % total;
    given += shares[id]!;
  });
  // List.sort không ổn định, nên khi bằng nhau thì xét vị trí ban đầu.
  final position = {for (final (i, id) in active.keys.indexed) id: i};
  final order = active.keys.toList()..sort((a, b) {
    final byFraction = fractions[b]!.compareTo(fractions[a]!);
    if (byFraction != 0) return byFraction;
    if (a == remainderTo) return -1;
    if (b == remainderTo) return 1;
    return position[a]!.compareTo(position[b]!);
  });
  var left = amount - given;
  for (var i = 0; left > 0; i = (i + 1) % order.length, left--) {
    shares[order[i]] = shares[order[i]]! + 1;
  }
  return shares;
}

/// 100% tính bằng phần vạn.
const percentScale = 10000;

/// "33.33", "33,33", "50%" -> 3333, 3333, 5000 (phần vạn). Không hợp lệ: null.
int? parsePercent(String input) {
  final s = input.trim().replaceAll('%', '').replaceAll(',', '.');
  if (s.isEmpty) return null;
  final v = double.tryParse(s);
  if (v == null || v < 0 || v > 100) return null;
  return (v * 100).round();
}

/// 3333 -> "33,33%", 5000 -> "50%".
String formatPercent(int basisPoints) {
  final whole = basisPoints ~/ 100;
  final frac = basisPoints % 100;
  if (frac == 0) return '$whole%';
  final f = frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '');
  return '$whole,$f%';
}

/// Chia lại phần trăm: người trong [locked] giữ nguyên số đã gõ, phần còn lại
/// của 100% chia đều cho [others] (phần lẻ cho người đầu tiên). Nếu [locked]
/// đã vượt 100% thì [others] nhận 0%. Kết quả tính bằng phần vạn.
Map<int, int> rebalancePercent({
  required Map<int, int> locked,
  required List<int> others,
}) {
  final result = {...locked};
  if (others.isEmpty) return result;
  final used = locked.values.fold<int>(0, (a, b) => a + b);
  final left = used >= percentScale ? 0 : percentScale - used;
  result.addAll(splitEqual(left, others, remainderTo: others.first));
  return result;
}
