import 'package:chia_tien/logic/emv_qr_parser.dart';
import 'package:chia_tien/logic/export.dart';
import 'package:chia_tien/logic/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseVnd', () {
    test('"2.500k" là 2.500.000 chứ không phải 2.500', () {
      expect(parseVnd('2.500k'), 2500000);
      expect(parseVnd('1,200k'), 1200000);
      expect(parseVnd('1.500.000'), 1500000);
    });
    test('vẫn đọc số thập phân có hậu tố', () {
      expect(parseVnd('1.5tr'), 1500000);
      expect(parseVnd('1,5tr'), 1500000);
      expect(parseVnd('2.5k'), 2500);
    });
    test('chặn số mũ, vô cực, số âm và số quá lớn', () {
      expect(parseVnd('1e309k'), isNull);
      expect(parseVnd('1e3k'), isNull);
      expect(parseVnd('-5k'), isNull);
      expect(parseVnd('-50000'), isNull);
      expect(parseVnd('9000000000000000000'), isNull);
      expect(parseVnd('2000000tr'), isNull);
      expect(parseVnd('$maxVnd'), maxVnd);
    });
  });

  test('csvCell chặn chèn công thức Excel ở ô chữ', () {
    expect(csvCell('=HYPERLINK("http://x","Bấm")'),
        '"\'=HYPERLINK(""http://x"",""Bấm"")"');
    expect(csvCell('+1+1'), "'+1+1");
    expect(csvCell('@SUM(A1)'), "'@SUM(A1)");
    expect(csvCell('-50'), "'-50");
    expect(csvCell(-50), '-50', reason: 'ô số giữ nguyên');
    expect(csvCell('Ăn trưa'), 'Ăn trưa');
  });

  test('parseTlv: độ dài âm hoặc không phải số thì trả null, không ném lỗi', () {
    expect(parseTlv('00-1abc'), isNull);
    expect(parseTlv('00+1abc'), isNull);
    expect(parseTlv('0002ab'), {'00': 'ab'});
  });
}
