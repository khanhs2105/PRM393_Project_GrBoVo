import 'package:chia_tien/logic/emv_qr_parser.dart';
import 'package:chia_tien/logic/money.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lỗi chức năng ở báo cáo kiểm thử lần 2.
void main() {
  group('M1/L1–L4: đọc số tiền', () {
    test('số kiểu ngân hàng có phần thập phân', () {
      expect(parseVnd('150.000,00'), 150000);
      expect(parseVnd('150,000.00'), 150000);
      expect(parseVnd('12.345,67'), 12346);
      expect(parseVnd('1500000.00'), 1500000);
    });
    test('số mơ hồ bị từ chối thay vì đoán sai', () {
      expect(parseVnd('1.5'), isNull);
      expect(parseVnd('1.2.3'), isNull);
    });
    test('hậu tố k / tr', () {
      expect(parseVnd('0.500k'), 500);
      expect(parseVnd('1.250tr'), 1250000);
      expect(parseVnd('2.500k'), 2500000);
      expect(parseVnd('2.5k'), 2500);
    });
    test('hậu tố vnđ', () {
      expect(parseVnd('150000 vnđ'), 150000);
      expect(parseVnd('150.000 VND'), 150000);
      expect(parseVnd('150.000đ'), 150000);
    });
    test('phần trăm NaN bị từ chối', () {
      expect(parsePercent('NaN'), isNull);
      expect(parsePercent('Infinity'), isNull);
      expect(parsePercent('12.5'), 1250);
    });
  });

  group('L5: số tiền trong QR', () {
    String tlv(String tag, String v) =>
        '$tag${v.length.toString().padLeft(2, '0')}$v';
    String qr(String amount) {
      final merchant = tlv('00', napasGuid) +
          tlv('01', tlv('00', '970436') + tlv('01', '0123456789'));
      return tlv('00', '01') + tlv('38', merchant) + tlv('54', amount);
    }

    test('NaN / âm / số mũ thì bỏ qua số tiền', () {
      for (final a in ['NaN', '-5000', '1e5', 'Infinity']) {
        final r = parseBankQr(qr(a), checkCrc: false);
        expect(r, isNotNull);
        expect(r!.amount, isNull, reason: a);
      }
    });
    test('số hợp lệ vẫn đọc được', () {
      expect(parseBankQr(qr('50000'), checkCrc: false)!.amount, 50000);
      expect(parseBankQr(qr('50000.00'), checkCrc: false)!.amount, 50000);
    });
  });
}
