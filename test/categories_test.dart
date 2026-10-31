import 'package:chia_tien/logic/categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('đoán loại khoản chi', () {
    expect(categorize('Lẩu Thái'), ExpenseCategory.food);
    expect(categorize('Trà sữa'), ExpenseCategory.drink);
    expect(categorize('Tiền phòng tháng 11'), ExpenseCategory.rent);
    expect(categorize('Tiền điện tháng 10'), ExpenseCategory.utilities);
    expect(categorize('Wifi'), ExpenseCategory.utilities);
    expect(categorize('Đổ xăng'), ExpenseCategory.transport);
    expect(categorize('Xem phim CGV'), ExpenseCategory.fun);
    expect(categorize('Linh tinh'), ExpenseCategory.other);
    // "an" không khớp nhầm trong "nhan"
    expect(categorize('Quà sinh nhật'), ExpenseCategory.other);
  });
}
