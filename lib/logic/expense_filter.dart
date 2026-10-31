/// Tìm kiếm và lọc khoản chi.
library;

import '../models/expense.dart';
import 'categories.dart';
import 'vietqr.dart';

String _normalize(String s) => removeDiacritics(s).toLowerCase().trim();

/// Giữ khoản chi khớp mọi điều kiện:
/// - [query]: có trong nội dung hoặc ghi chú, không phân biệt dấu và hoa thường.
/// - [category]: đúng danh mục.
/// - [memberId]: người đó trả hoặc có phần trong khoản chi.
List<Expense> filterExpenses(
  List<Expense> expenses, {
  String query = '',
  ExpenseCategory? category,
  int? memberId,
}) {
  final q = _normalize(query);
  return [
    for (final e in expenses)
      if ((q.isEmpty ||
              _normalize(e.title).contains(q) ||
              _normalize(e.note ?? '').contains(q)) &&
          (category == null || e.effectiveCategory == category) &&
          (memberId == null ||
              e.paidBy == memberId ||
              e.shares.containsKey(memberId)))
        e,
  ];
}
