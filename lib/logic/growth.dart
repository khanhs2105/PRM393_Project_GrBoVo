/// Logic theo chiến lược marketing: dùng thử Pro, quảng cáo ở bản Free,
/// lịch nhắc nợ và giới hạn số lần nhắc mỗi ngày. Toàn bộ là Dart thuần để
/// test được không cần Flutter.
library;

import 'plans.dart';

// ---------------- Dùng thử Pro ----------------

/// Số ngày dùng thử Pro miễn phí (mỗi máy được một lần).
const proTrialDays = 7;

/// Đề nghị dùng thử khi nhóm từ chừng này người vừa chốt bill đầu tiên.
const trialOfferMinMembers = 3;

/// Gói thực sự áp dụng: đang dùng thử thì bản Free được nâng lên Chủ Nợ.
Plan effectivePlan(Plan purchased, DateTime? trialUntil, DateTime now) {
  if (purchased.isPro) return purchased;
  if (trialUntil != null && now.isBefore(trialUntil)) return Plan.chuNo;
  return purchased;
}

/// Có nên đề nghị dùng thử sau khi vừa thêm khoản chi không.
/// Chỉ đề nghị đúng lúc nhóm vừa nhận được giá trị (bill đầu tiên).
bool shouldOfferTrial({
  required Plan plan,
  required bool trialUsed,
  required int memberCount,
  required int expenseCount,
}) =>
    !plan.isPro &&
    !trialUsed &&
    memberCount >= trialOfferMinMembers &&
    expenseCount == 1;

// ---------------- Quảng cáo (giả) ----------------

/// Đếm thao tác đã có kết quả, cứ [every] lần thì hiện một quảng cáo.
/// Quy tắc theo chiến lược:
/// - chỉ hiện sau khi người dùng đã có kết quả (gọi [onResult] lúc đó);
/// - không hiện trong lần mở app đầu tiên ([firstSession]);
/// - không hiện cho gói Pro;
/// - không gọi ở màn nhắc nợ và trong thông báo (do chỗ gọi đảm bảo).
class AdPolicy {
  final int every;
  int _count = 0;
  AdPolicy({this.every = 3});

  bool onResult({required Plan plan, required bool firstSession}) {
    if (!plan.showsAds || firstSession) return false;
    _count++;
    return _count % every == 0;
  }
}

class FakeAd {
  final String emoji;
  final String brand;
  final String text;
  const FakeAd(this.emoji, this.brand, this.text);
}

/// Quảng cáo vui tự viết. Không có quảng cáo cho vay hay tín dụng.
const fakeAds = [
  FakeAd('🧋', 'Trà Sữa Tình Bạn',
      'Mua 1 ly, bạn thân uống ké nửa ly. Nhớ chia bill bằng app này nhé.'),
  FakeAd('🍜', 'Phở Ông Chủ Nợ',
      'Bát phở to nhất quận. Ai trả tiền thì quyết định bằng cách lắc điện thoại.'),
  FakeAd('🛵', 'Xe Ôm Chở Nợ',
      'Chở bạn tới tận nhà người đang nợ. Đùa thôi, chỉ chở đi ăn.'),
  FakeAd('🧠', 'Khóa học "Nói chuyện tiền không ngại"',
      'Bài 1: mở app, bấm Nhắc nợ. Hết khóa.'),
  FakeAd('🏝️', 'Tour Đà Lạt 3N2Đ',
      'Đi 6 người, về 6 người, nợ 0 người. Chốt bill ngay trong app.'),
];

FakeAd pickAd(int seed) => fakeAds[seed.abs() % fakeAds.length];

// ---------------- Nhắc nợ ----------------

/// Mỗi khoản nợ chỉ được nhắc tối đa chừng này lần một ngày, để nhắc nợ
/// không thành quấy rối.
const maxRemindersPerDay = 3;

const reminderLimitMessage =
    'Hôm nay nhắc khoản này $maxRemindersPerDay lần rồi. '
    'Để mai nhắc tiếp cho giữ tình nhé 🙏';

/// Khóa lưu số lần nhắc của một khoản nợ trong ngày [day].
String reminderCountKey(int groupId, int fromId, int toId, DateTime day) =>
    'remind_${groupId}_${fromId}_${toId}_'
    '${day.year}${day.month.toString().padLeft(2, '0')}'
    '${day.day.toString().padLeft(2, '0')}';

bool canRemindAgain(int countToday) => countToday < maxRemindersPerDay;

/// 20:00 gần nhất sau [now] (tối nay, hoặc tối mai nếu đã quá 20:00).
DateTime nextEvening(DateTime now) {
  final tonight = DateTime(now.year, now.month, now.day, 20);
  return tonight.isAfter(now) ? tonight : tonight.add(const Duration(days: 1));
}

/// Pro: nhắc nhiều mốc, tối nay (hoặc tối mai), sau đó 1 ngày và 3 ngày.
List<DateTime> multiStepReminders(DateTime now) {
  final first = nextEvening(now);
  return [
    first,
    DateTime(first.year, first.month, first.day + 1, 20),
    DateTime(first.year, first.month, first.day + 3, 20),
  ];
}

/// Pro: nhắc lặp lại mỗi tối lúc 20:00 trong [days] ngày.
List<DateTime> dailyReminders(DateTime now, {int days = 7}) {
  final first = nextEvening(now);
  return [
    for (var i = 0; i < days; i++)
      DateTime(first.year, first.month, first.day + i, 20),
  ];
}
