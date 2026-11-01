/// Danh mục khoản chi. Người dùng có thể tự chọn (lưu ở cột expenses.category);
/// nếu không chọn thì đoán từ nội dung để hiện icon và màu.
library;

import 'vietqr.dart';

enum ExpenseCategory { food, drink, rent, utilities, transport, shopping, fun, other }

const _keywords = <ExpenseCategory, List<String>>{
  ExpenseCategory.drink: [
    'cafe', 'ca phe', 'coffee', 'tra sua', 'nuoc ep', 'sinh to', 'bia', 'ruou',
    'highlands', 'phuc long', 'starbucks', 'tra chanh',
  ],
  ExpenseCategory.food: [
    'an', 'com', 'bun', 'pho', 'lau', 'nuong', 'banh', 'mi', 'pizza', 'ga',
    'kfc', 'lotteria', 'sushi', 'oc', 'chao', 'xoi', 'bua', 'trua', 'toi', 'sang',
  ],
  ExpenseCategory.rent: ['phong', 'nha', 'tro', 'thue', 'coc'],
  ExpenseCategory.utilities: [
    'dien', 'nuoc', 'wifi', 'internet', 'mang', 'gas', 'rac', 've sinh', 'giay',
  ],
  ExpenseCategory.transport: [
    'xang', 'grab', 'be', 'taxi', 'xe', 've xe', 'tau', 'may bay', 'gui xe',
  ],
  ExpenseCategory.shopping: ['sieu thi', 'cho', 'mua', 'shopee', 'do dung'],
  ExpenseCategory.fun: [
    'phim', 'cgv', 'karaoke', 'game', 'bida', 'du lich', 'khach san', 'homestay',
    'concert', 've',
  ],
};

/// "Lẩu Thái" -> food, "Tiền điện tháng 10" -> utilities.
/// So khớp theo cả từ (bỏ dấu) để "an" không khớp nhầm "nhan".
ExpenseCategory categorize(String title) {
  final words = ' ${removeDiacritics(title).toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  for (final entry in _keywords.entries) {
    for (final k in entry.value) {
      if (words.contains(' $k ')) return entry.key;
    }
  }
  return ExpenseCategory.other;
}

/// Tên tiếng Việt hiện trên giao diện.
const categoryLabels = <ExpenseCategory, String>{
  ExpenseCategory.food: 'Ăn uống',
  ExpenseCategory.drink: 'Cà phê, trà sữa',
  ExpenseCategory.rent: 'Tiền nhà',
  ExpenseCategory.utilities: 'Điện, nước, mạng',
  ExpenseCategory.transport: 'Đi lại',
  ExpenseCategory.shopping: 'Mua sắm',
  ExpenseCategory.fun: 'Giải trí, du lịch',
  ExpenseCategory.other: 'Khác',
};

/// Đọc tên danh mục đã lưu trong database. null hoặc tên lạ: null.
ExpenseCategory? categoryFromName(String? name) {
  for (final c in ExpenseCategory.values) {
    if (c.name == name) return c;
  }
  return null;
}
