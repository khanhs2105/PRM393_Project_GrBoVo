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

  group('splitByWeights', () {
    test('chia theo phần 2:1:1', () {
      expect(splitByWeights({1: 2, 2: 1, 3: 1}, 100000),
          {1: 50000, 2: 25000, 3: 25000});
    });
    test('phần lẻ cho người trả khi bằng nhau', () {
      expect(splitByWeights({1: 1, 2: 1, 3: 1}, 100000, remainderTo: 2),
          {1: 33333, 2: 33334, 3: 33333});
      expect(splitByWeights({1: 1, 2: 1, 3: 1}, 100000),
          {1: 33334, 2: 33333, 3: 33333});
    });
    test('theo phần trăm (phần vạn)', () {
      expect(splitByWeights({1: 3333, 2: 3333, 3: 3334}, 100000),
          {1: 33330, 2: 33330, 3: 33340});
      expect(splitByWeights({1: 5000, 2: 5000}, 99999, remainderTo: 2),
          {1: 49999, 2: 50000});
    });
    test('tổng luôn bằng số tiền', () {
      for (final amount in [1, 7, 999, 123457, 1000001]) {
        final r = splitByWeights({1: 3, 2: 5, 3: 7, 4: 1}, amount);
        expect(r.values.reduce((a, b) => a + b), amount);
      }
    });
    test('bỏ người có 0 phần, báo lỗi khi tổng 0', () {
      expect(splitByWeights({1: 1, 2: 0}, 500), {1: 500});
      expect(() => splitByWeights({1: 0}, 500), throwsArgumentError);
      expect(() => splitByWeights({1: -1, 2: 2}, 500), throwsArgumentError);
    });
  });

  test('parsePercent', () {
    expect(parsePercent('50'), 5000);
    expect(parsePercent('33.33'), 3333);
    expect(parsePercent('33,33'), 3333);
    expect(parsePercent('25%'), 2500);
    expect(parsePercent('101'), isNull);
    expect(parsePercent('abc'), isNull);
    expect(parsePercent(''), isNull);
  });

  test('formatPercent', () {
    expect(formatPercent(5000), '50%');
    expect(formatPercent(3333), '33,33%');
    expect(formatPercent(3330), '33,3%');
    expect(formatPercent(1205), '12,05%');
  });

  group('rebalancePercent', () {
    test('3 người, gõ 1 người 50% thì 2 người kia mỗi người 25%', () {
      expect(rebalancePercent(locked: {1: 5000}, others: [2, 3]),
          {1: 5000, 2: 2500, 3: 2500});
    });
    test('tổng luôn 100% khi chưa vượt', () {
      final r = rebalancePercent(locked: {1: 1000}, others: [2, 3, 4]);
      expect(r.values.reduce((a, b) => a + b), percentScale);
      expect(r, {1: 1000, 2: 3000, 3: 3000, 4: 3000});
      final odd = rebalancePercent(locked: {}, others: [1, 2, 3]);
      expect(odd, {1: 3334, 2: 3333, 3: 3333});
    });
    test('đã gõ vượt 100% thì người còn lại 0%', () {
      expect(rebalancePercent(locked: {1: 7000, 2: 4000}, others: [3]),
          {1: 7000, 2: 4000, 3: 0});
    });
    test('không còn ai để chia thì giữ nguyên', () {
      expect(rebalancePercent(locked: {1: 5000, 2: 5000}, others: []),
          {1: 5000, 2: 5000});
    });
  });
}
