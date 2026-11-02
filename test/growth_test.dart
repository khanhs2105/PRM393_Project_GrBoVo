import 'package:chia_tien/logic/growth.dart';
import 'package:chia_tien/logic/plans.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 2, 14, 30);

  test('dùng thử nâng Free lên Chủ Nợ cho tới hạn', () {
    final until = now.add(const Duration(days: proTrialDays));
    expect(effectivePlan(Plan.conNo, null, now), Plan.conNo);
    expect(effectivePlan(Plan.conNo, until, now), Plan.chuNo);
    expect(effectivePlan(Plan.conNo, until, until), Plan.conNo);
    expect(effectivePlan(Plan.doiNoThue, until, now), Plan.doiNoThue);
  });

  test('chỉ đề nghị dùng thử sau bill đầu tiên của nhóm từ 3 người', () {
    bool offer({
      Plan plan = Plan.conNo,
      bool used = false,
      int members = 3,
      int expenses = 1,
    }) =>
        shouldOfferTrial(
            plan: plan,
            trialUsed: used,
            memberCount: members,
            expenseCount: expenses);
    expect(offer(), isTrue);
    expect(offer(members: 2), isFalse);
    expect(offer(expenses: 2), isFalse);
    expect(offer(used: true), isFalse);
    expect(offer(plan: Plan.chuNo), isFalse);
  });

  test('quảng cáo sau mỗi 3 thao tác, không hiện lần mở đầu và cho Pro', () {
    final ads = AdPolicy();
    final shown = [
      for (var i = 0; i < 6; i++)
        ads.onResult(plan: Plan.conNo, firstSession: false),
    ];
    expect(shown, [false, false, true, false, false, true]);

    final first = AdPolicy();
    for (var i = 0; i < 6; i++) {
      expect(first.onResult(plan: Plan.conNo, firstSession: true), isFalse);
      expect(first.onResult(plan: Plan.chuNo, firstSession: false), isFalse);
    }
  });

  test('quảng cáo không có nội dung cho vay', () {
    for (final ad in fakeAds) {
      final text = '${ad.brand} ${ad.text}'.toLowerCase();
      expect(text, isNot(contains('vay')));
      expect(text, isNot(contains('tín dụng')));
    }
    expect(pickAd(-7), isA<FakeAd>());
  });

  test('giới hạn số lần nhắc mỗi ngày', () {
    expect(canRemindAgain(0), isTrue);
    expect(canRemindAgain(maxRemindersPerDay - 1), isTrue);
    expect(canRemindAgain(maxRemindersPerDay), isFalse);
    expect(reminderCountKey(1, 2, 3, now), 'remind_1_2_3_20261102');
  });

  test('lịch nhắc nhiều mốc và nhắc mỗi tối', () {
    expect(nextEvening(now), DateTime(2026, 11, 2, 20));
    expect(nextEvening(DateTime(2026, 11, 2, 21)), DateTime(2026, 11, 3, 20));
    expect(multiStepReminders(now), [
      DateTime(2026, 11, 2, 20),
      DateTime(2026, 11, 3, 20),
      DateTime(2026, 11, 5, 20),
    ]);
    final daily = dailyReminders(DateTime(2026, 11, 28, 22));
    expect(daily.length, 7);
    expect(daily.first, DateTime(2026, 11, 29, 20));
    expect(daily.last, DateTime(2026, 12, 5, 20));
  });
}
