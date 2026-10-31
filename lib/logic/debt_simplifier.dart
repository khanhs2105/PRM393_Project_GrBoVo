import '../models/settlement.dart';

/// Rút gọn nợ: từ số dư ròng, tìm danh sách lượt chuyển tiền ít nhất có thể.
///
/// Thuật toán tham lam: mỗi vòng ghép người được nợ nhiều nhất với người nợ
/// nhiều nhất, chuyển số tiền nhỏ hơn trong hai số. Mỗi vòng có ít nhất một
/// người về 0, nên với n người có tối đa n - 1 lượt chuyển.
///
/// (Tìm số lượt ít nhất tuyệt đối là bài toán NP-khó, với nhóm vài người
/// thì cách tham lam này đủ tốt.)
List<Transfer> simplifyDebts(Map<int, int> balances) {
  final total = balances.values.fold<int>(0, (a, b) => a + b);
  if (total != 0) {
    throw ArgumentError('Tổng số dư phải bằng 0, đang là $total');
  }

  // [id, số tiền] với số tiền luôn dương.
  final creditors = [
    for (final e in balances.entries)
      if (e.value > 0) [e.key, e.value],
  ];
  final debtors = [
    for (final e in balances.entries)
      if (e.value < 0) [e.key, -e.value],
  ];

  // Sắp giảm dần theo số tiền, bằng nhau thì theo id để kết quả luôn cố định.
  int byAmountDesc(List<int> a, List<int> b) =>
      b[1] != a[1] ? b[1].compareTo(a[1]) : a[0].compareTo(b[0]);

  final result = <Transfer>[];
  while (creditors.isNotEmpty && debtors.isNotEmpty) {
    creditors.sort(byAmountDesc);
    debtors.sort(byAmountDesc);
    final c = creditors.first;
    final d = debtors.first;
    final x = c[1] < d[1] ? c[1] : d[1];

    result.add(Transfer(d[0], c[0], x));
    c[1] -= x;
    d[1] -= x;
    if (c[1] == 0) creditors.removeAt(0);
    if (d[1] == 0) debtors.removeAt(0);
  }
  return result;
}
