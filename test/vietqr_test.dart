import 'package:chia_tien/logic/emv_qr_parser.dart';
import 'package:chia_tien/logic/vietqr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('vietqr', () {
    test('bỏ dấu tiếng Việt', () {
      expect(removeDiacritics('Nguyễn Văn Đức'), 'Nguyen Van Duc');
      expect(removeDiacritics('Phòng 302 tiền điện'), 'Phong 302 tien dien');
      // Dấu dạng tổ hợp (e + dấu sắc rời)
      expect(removeDiacritics('Tién'), 'Tien');
    });

    test('nội dung chuyển khoản gọn và an toàn', () {
      expect(transferNote('Huy trả Nam - phòng 302!'), 'HUY TRA NAM PHONG 302');
      expect(transferNote('a' * 40).length, 25);
      expect(suggestedNote('Huy', 'Nam', 'Đi Đà Lạt'), 'HUY TRA NAM DI DA LAT');
    });

    test('link img.vietqr.io', () {
      final url = vietQrImageUrl(
        bin: '970436',
        accountNo: '0123456789',
        amount: 150000,
        note: 'Huy trả Nam',
        accountName: 'Nguyễn Văn Nam',
      );
      expect(
        url,
        'https://img.vietqr.io/image/970436-0123456789-compact2.png'
        '?amount=150000&addInfo=HUY%20TRA%20NAM&accountName=NGUYEN%20VAN%20NAM',
      );
    });
  });

  group('emv_qr_parser', () {
    test('CRC-16/CCITT-FALSE đúng giá trị chuẩn', () {
      expect(crc16('123456789'), '29B1');
    });

    test('đọc lại QR do buildBankQr tạo', () {
      final raw = buildBankQr(bin: '970436', accountNo: '0123456789');
      expect(hasValidCrc(raw), isTrue);
      final qr = parseBankQr(raw)!;
      expect(qr.bin, '970436');
      expect(qr.accountNo, '0123456789');
      expect(qr.amount, isNull);
    });

    test('QR có số tiền và nội dung', () {
      final raw = buildBankQr(
        bin: '970422',
        accountNo: '9999888877',
        amount: 50000,
        note: 'TRA NO',
      );
      final qr = parseBankQr(raw)!;
      expect(qr.bin, '970422');
      expect(qr.amount, 50000);
      expect(qr.note, 'TRA NO');
    });

    test('đọc tên người nhận ở tag 59 nếu có', () {
      var body = buildBankQr(bin: '970436', accountNo: '0123456789');
      body = body.substring(0, body.length - 8); // bỏ "6304" + CRC
      body += '5914NGUYEN VAN NAM6304';
      final qr = parseBankQr(body + crc16(body))!;
      expect(qr.accountName, 'NGUYEN VAN NAM');
    });

    test('sai CRC hoặc không phải QR ngân hàng thì trả null', () {
      final raw = buildBankQr(bin: '970436', accountNo: '0123456789');
      final broken = '${raw.substring(0, raw.length - 1)}'
          '${raw.endsWith('0') ? '1' : '0'}';
      expect(parseBankQr(broken), isNull);
      expect(parseBankQr('https://example.com'), isNull);
      expect(parseBankQr(''), isNull);
    });
  });
}
