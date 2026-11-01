import '../logic/categories.dart';

/// Cách chia một khoản chi.
class SplitType {
  static const equal = 'equal';
  static const exact = 'exact';

  /// Theo phần, ví dụ 2:1:1.
  static const shares = 'shares';

  /// Theo phần trăm, trọng số lưu bằng phần vạn (100% = 10000).
  static const percent = 'percent';

  static const all = [equal, exact, shares, percent];

  static String label(String type) => switch (type) {
        equal => 'Chia đều',
        exact => 'Theo số tiền',
        shares => 'Theo phần',
        percent => 'Theo %',
        _ => type,
      };
}

/// Một khoản chi. [shares] là số tiền mỗi thành viên phải chịu,
/// tổng của [shares] luôn bằng [amount].
class Expense {
  final int? id;
  final int groupId;
  final String title;

  /// Số tiền VND, luôn là số nguyên.
  final int amount;
  final int paidBy;

  /// Một trong [SplitType.all].
  final String splitType;

  /// memberId -> số tiền phải chịu
  final Map<int, int> shares;

  /// memberId -> trọng số đã nhập khi chia theo phần hoặc theo %.
  /// Lưu lại để mở form sửa thấy đúng số đã nhập. Rỗng với 2 kiểu còn lại.
  final Map<int, int> weights;

  /// Tên [ExpenseCategory] người dùng chọn. null: tự đoán từ [title].
  final String? category;
  final String? note;
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
    this.weights = const {},
    this.category,
    this.note,
    this.receiptPath,
    required this.date,
  });

  /// Danh mục để hiện: cái người dùng chọn, không thì đoán từ nội dung.
  ExpenseCategory get effectiveCategory =>
      categoryFromName(category) ?? categorize(title);

  /// Chỉ các cột của bảng expenses, shares lưu ở bảng expense_shares.
  Map<String, Object?> toMap() => {
        'id': id,
        'group_id': groupId,
        'title': title,
        'amount': amount,
        'paid_by': paidBy,
        'split_type': splitType,
        'category': category,
        'note': note,
        'receipt_path': receiptPath,
        'date': date.millisecondsSinceEpoch,
      };

  factory Expense.fromMap(Map<String, Object?> m, Map<int, int> shares,
          [Map<int, int> weights = const {}]) =>
      Expense(
        id: m['id'] as int?,
        groupId: m['group_id'] as int,
        title: m['title'] as String,
        amount: m['amount'] as int,
        paidBy: m['paid_by'] as int,
        splitType: m['split_type'] as String,
        shares: shares,
        weights: weights,
        category: m['category'] as String?,
        note: m['note'] as String?,
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
    Map<int, int>? weights,
    String? category,
    String? note,
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
        weights: weights ?? this.weights,
        category: category ?? this.category,
        note: note ?? this.note,
        receiptPath: receiptPath ?? this.receiptPath,
        date: date ?? this.date,
      );
}
