/// Các gói tài khoản "troll". Không có thanh toán thật: bấm nâng cấp là
/// lưu gói vào máy (bảng app_settings).
library;

import 'money.dart';

enum Plan {
  /// Miễn phí.
  conNo(
    title: 'Con Nợ',
    price: 'Miễn phí (vì bạn còn đang nợ)',
    slogan: 'Đủ dùng để biết mình nợ ai.',
    maxGroups: 2,
    perks: [
      'Tối đa 2 nhóm',
      'Nhắc nợ lịch sự, nhẹ nhàng như người yêu cũ',
      'Huy hiệu "Đang cố gắng" 🥲',
    ],
  ),

  chuNo(
    title: 'Chủ Nợ',
    price: '29.000 ₫/tháng (chia đều cho cả nhóm cũng được)',
    slogan: 'Dành cho người luôn ứng tiền trước.',
    maxGroups: null,
    perks: [
      'Không giới hạn nhóm',
      'Nhắc nợ cấp 2: thân thiện nhưng có chút cà khịa',
      'Ảnh hóa đơn làm bằng chứng',
      'Huy hiệu "Người tốt bụng" 😇',
    ],
  ),

  doiNoThue(
    title: 'Đòi Nợ Thuê',
    price: '99.000 ₫/tháng, hoặc 1 bát phở mỗi tuần',
    slogan: 'Không ai thoát được. Kể cả bạn thân.',
    maxGroups: null,
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
    required this.slogan,
    required this.maxGroups,
    required this.perks,
  });

  final String title;
  final String price;
  final String slogan;

  /// null là không giới hạn.
  final int? maxGroups;
  final List<String> perks;

  bool canCreateGroup(int currentGroups) =>
      maxGroups == null || currentGroups < maxGroups!;

  bool get canAttachReceipt => this != Plan.conNo;
  bool get canShakeToPick => this == Plan.doiNoThue;

  static Plan fromName(String? name) =>
      Plan.values.firstWhere((p) => p.name == name, orElse: () => Plan.conNo);
}

/// Câu báo khi gói Con Nợ chạm giới hạn nhóm.
const groupLimitMessage =
    'Gói Con Nợ chỉ được 2 nhóm thôi. Trả hết nợ rồi nâng cấp nhé 😌';

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
