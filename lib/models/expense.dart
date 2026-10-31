/// Một khoản chi. [shares] là số tiền mỗi thành viên phải chịu,
/// tổng của [shares] luôn bằng [amount].
class Expense {
  final int? id;
  final int groupId;
  final String title;

  /// Số tiền VND, luôn là số nguyên.
  final int amount;
  final int paidBy;

  /// equal | exact
  final String splitType;

  /// memberId -> số tiền phải chịu
  final Map<int, int> shares;
  final String? receiptPath;
  final DateTime date;

  const Expense({
    this.id,
    required this.groupId,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.splitType,
    required this.shares,
    this.receiptPath,
    required this.date,
  });

  /// Chỉ các cột của bảng expenses, shares lưu ở bảng expense_shares.
  Map<String, Object?> toMap() => {
        'id': id,
        'group_id': groupId,
        'title': title,
        'amount': amount,
        'paid_by': paidBy,
        'split_type': splitType,
        'receipt_path': receiptPath,
        'date': date.millisecondsSinceEpoch,
      };

  factory Expense.fromMap(Map<String, Object?> m, Map<int, int> shares) =>
      Expense(
        id: m['id'] as int?,
        groupId: m['group_id'] as int,
        title: m['title'] as String,
        amount: m['amount'] as int,
        paidBy: m['paid_by'] as int,
        splitType: m['split_type'] as String,
        shares: shares,
        receiptPath: m['receipt_path'] as String?,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
      );

  Expense copyWith({
    int? id,
    String? title,
    int? amount,
    int? paidBy,
    String? splitType,
    Map<int, int>? shares,
    String? receiptPath,
    DateTime? date,
  }) =>
      Expense(
        id: id ?? this.id,
        groupId: groupId,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        paidBy: paidBy ?? this.paidBy,
        splitType: splitType ?? this.splitType,
        shares: shares ?? this.shares,
        receiptPath: receiptPath ?? this.receiptPath,
        date: date ?? this.date,
      );
}
