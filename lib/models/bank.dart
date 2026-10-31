import 'dart:convert';

/// Ngân hàng trong danh sách của VietQR (api.vietqr.io/v2/banks).
class Bank {
  final String bin;
  final String code;
  final String shortName;
  final String name;
  final String? logo;

  const Bank({
    required this.bin,
    required this.code,
    required this.shortName,
    required this.name,
    this.logo,
  });

  factory Bank.fromJson(Map<String, dynamic> j) => Bank(
        bin: j['bin'].toString(),
        code: j['code'] as String,
        shortName: (j['shortName'] ?? j['short_name']) as String,
        name: j['name'] as String,
        logo: j['logo'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'bin': bin,
        'code': code,
        'shortName': shortName,
        'name': name,
        'logo': logo,
      };
}

/// Đọc danh sách ngân hàng từ chuỗi JSON (assets/banks.json, hoặc trường
/// "data" của api.vietqr.io/v2/banks).
/// Trong Flutter: parseBanks(await rootBundle.loadString('assets/banks.json'))
List<Bank> parseBanks(String jsonText) {
  final decoded = jsonDecode(jsonText);
  final list = decoded is Map ? decoded['data'] as List : decoded as List;
  return list.map((e) => Bank.fromJson(e as Map<String, dynamic>)).toList();
}

Bank? findBankByBin(List<Bank> banks, String? bin) {
  if (bin == null) return null;
  for (final b in banks) {
    if (b.bin == bin) return b;
  }
  return null;
}
