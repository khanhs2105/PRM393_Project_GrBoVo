import 'package:chia_tien/logic/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatVnd', () {
    test('có dấu chấm hàng nghìn', () {
      expect(formatVnd(0), '0 ₫');
      expect(formatVnd(999), '999 ₫');
      expect(formatVnd(1000), '1.000 ₫');
      expect(formatVnd(150000), '150.000 ₫');
      expect(formatVnd(12345678), '12.345.678 ₫');
      expect(formatVnd(-50000), '-50.000 ₫');
    });
  });

  group('parseVnd', () {
    test('các kiểu gõ thường gặp', () {
      expect(parseVnd('150000'), 150000);
      expect(parseVnd('150.000'), 150000);
      expect(parseVnd('150,000'), 150000);
      expect(parseVnd('150k'), 150000);
      expect(parseVnd('150 K'), 150000);
      expect(parseVnd('1.5tr'), 1500000);
      expect(parseVnd('1,5tr'), 1500000);
      expect(parseVnd('200.000đ'), 200000);
    });
    test('không hợp lệ', () {
      expect(parseVnd(''), isNull);
      expect(parseVnd('abc'), isNull);
      expect(parseVnd('-5000'), isNull);
    });
  });

  group('splitEqual', () {
    test('chia hết', () {
      expect(splitEqual(300000, [1, 2, 3]), {1: 100000, 2: 100000, 3: 100000});
    });
    test('phần lẻ dồn cho người trả, tổng vẫn đúng', () {
      final s = splitEqual(100000, [1, 2, 3], remainderTo: 2);
      expect(s, {1: 33333, 2: 33334, 3: 33333});
      expect(sharesMatchTotal(100000, s), isTrue);
    });
    test('người trả không tham gia thì dồn cho người đầu tiên', () {
      expect(splitEqual(10, [4, 5, 6], remainderTo: 9), {4: 4, 5: 3, 6: 3});
    });
    test('id trùng chỉ tính một lần', () {
      expect(splitEqual(100, [1, 1, 2]), {1: 50, 2: 50});
    });
    test('danh sách rỗng báo lỗi', () {
      expect(() => splitEqual(100, []), throwsArgumentError);
    });
  });

  test('sharesMatchTotal', () {
    expect(sharesMatchTotal(100, {1: 60, 2: 40}), isTrue);
    expect(sharesMatchTotal(100, {1: 60, 2: 30}), isFalse);
    expect(sharesMatchTotal(100, {1: 120, 2: -20}), isFalse);
  });
}
