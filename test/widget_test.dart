// File này có sẵn để `flutter create` không tạo test mẫu (test mẫu gọi MyApp
// sẽ lỗi vì app không có class đó).
import 'package:chia_tien/logic/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app định dạng tiền VND', () {
    expect(formatVnd(1500000), '1.500.000 ₫');
  });
}
