/// Các gói tài khoản "troll". Không có thanh toán thật: bấm nâng cấp là
/// lưu gói vào máy (bảng app_settings).
library;

import 'money.dart';

enum Plan {
  /// Miễn phí. Theo chiến lược: bản Free dùng được thật, không chặn thao tác
  /// cốt lõi (tạo nhóm, chia đều, ghi nợ, nhắc hạn cơ bản).
  conNo(
    title: 'Con Nợ',
    price: 'Miễn phí (vì bạn còn đang nợ)',
    monthlyPrice: 0,
    slogan: 'Bản miễn phí dùng được thật, không giới hạn thao tác.',
    perks: [
      'Không giới hạn nhóm và khoản chi',
      'Tự động chia đều',
      'Hẹn nhắc nợ 1 mốc, lịch sự như người yêu cũ',
      'Có quảng cáo (quảng cáo vui, không phải cho vay đâu)',
      'Huy hiệu "Đang cố gắng" 🥲',
    ],
  ),

  chuNo(
    title: 'Chủ Nợ',
    price: '29.000 ₫/tháng (chia đều cho cả nhóm cũng được)',
    monthlyPrice: 2000,
    slogan: 'Dành cho người luôn ứng tiền trước.',
    perks: [
      'Chia không đều: theo số tiền, theo phần, theo %',
      'Xuất báo cáo CSV (mở bằng Excel)',
      'Nhắc nợ nhiều mốc, nhắc lặp lại mỗi tối',
      'Mẫu tin nhắc khéo cấp 2: thân thiện nhưng có chút cà khịa',
      'Ảnh hóa đơn làm bằng chứng',
      'Không quảng cáo',
      'Huy hiệu "Người tốt bụng" 😇',
    ],
  ),

  doiNoThue(
    title: 'Đòi Nợ Thuê',
    price: '99.000 ₫/tháng, hoặc 1 bát phở mỗi tuần',
    monthlyPrice: 2999,
    slogan: 'Không ai thoát được. Kể cả bạn thân.',
    perks: [
      'Mọi thứ của gói Chủ Nợ',
      'Nhắc nợ cấp 3: drama, không trả không yên',
      'Lắc điện thoại để random người bao bữa',
      'Huy hiệu "Ác quỷ thu nợ" 😈',
    ],
  );

  const Plan({
    required this.title,
    required this.price,
    required this.monthlyPrice,
    required this.slogan,
    required this.perks,
  });

  final String title;
  final String price;

  /// Giá niêm yết mỗi tháng (đồng), chỉ để hiện trên màn thanh toán giả.
  /// Khi thanh toán luôn được giảm 100% nên không ai bị trừ tiền.
  final int monthlyPrice;
  final String slogan;
  final List<String> perks;

  /// Gói trả phí (Pro). Con Nợ là bản Free.
  bool get isPro => this != Plan.conNo;

  bool get canSplitUnevenly => isPro;
  bool get canExportReport => isPro;
  bool get canAdvancedReminders => isPro;
  bool get showsAds => !isPro;
  bool get canAttachReceipt => isPro;
  bool get canShakeToPick => this == Plan.doiNoThue;

  static Plan fromName(String? name) =>
      Plan.values.firstWhere((p) => p.name == name, orElse: () => Plan.conNo);
}

/// Tin nhắn nhắc nợ, gắt dần theo gói. [variant] chọn một trong các câu
/// (truyền số ngẫu nhiên hoặc số lần đã nhắc để mỗi lần một câu khác).
String reminderMessage({
  required Plan plan,
  required String debtor,
  required String creditor,
  required int amount,
  required String group,
  int variant = 0,
}) {
  final money = formatVnd(amount);
  final templates = switch (plan) {
    Plan.conNo => [
        'Chào $debtor, bạn còn nợ $creditor $money ở nhóm "$group". Khi nào tiện thì chuyển nhé 🙏',
        '$debtor ơi, nhắc nhẹ khoản $money trả cho $creditor ("$group") nha. Cảm ơn bạn!',
      ],
    Plan.chuNo => [
        '$debtor ơi, $money của $creditor đang nhớ bạn lắm đó 🥺 Quét QR là xong trong 10 giây.',
        'Tiền không mọc trên cây, nhưng $money bạn nợ $creditor thì vẫn đang chờ 🌱',
        'Nhắc lần này cho đẹp: $debtor trả $creditor $money ("$group"). Lần sau là cà khịa thật đấy 😏',
      ],
    Plan.doiNoThue => [
        '🚨 THÔNG BÁO KHẨN 🚨 $debtor đang nợ $creditor $money. Cả nhóm "$group" đều đã biết.',
        '$debtor, ví của bạn có thể quên, nhưng app này thì không. $money cho $creditor. Ngay. 😈',
        'Đây là tin nhắc thứ N. $creditor đã bắt đầu kể chuyện bạn nợ $money cho người khác nghe rồi đấy 👀',
        'Mỗi ngày không trả $money cho $creditor, một chú mèo buồn 😿 Hãy cứu mèo.',
      ],
  };
  return templates[variant.abs() % templates.length];
}
