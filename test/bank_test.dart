import 'dart:io';

import 'package:chia_tien/models/bank.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('đọc assets/banks.json và tìm theo BIN', () {
    final banks = parseBanks(File('assets/banks.json').readAsStringSync());
    expect(banks.length, greaterThan(30));
    expect(findBankByBin(banks, '970436')!.shortName, 'Vietcombank');
    expect(findBankByBin(banks, '000000'), isNull);
  });

  test('đọc định dạng của api.vietqr.io', () {
    final banks = parseBanks(
      '{"code":"00","data":[{"bin":"970422","code":"MB","shortName":"MBBank","name":"Quân đội"}]}',
    );
    expect(banks.single.bin, '970422');
  });
}
