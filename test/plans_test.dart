import 'package:chia_tien/data/app_database.dart';
import 'package:chia_tien/data/settings_repository.dart';
import 'package:chia_tien/logic/plans.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Free không chặn thao tác cốt lõi, Pro mở tính năng nâng cao', () {
    expect(Plan.conNo.isPro, isFalse);
    expect(Plan.conNo.canSplitUnevenly, isFalse);
    expect(Plan.conNo.canExportReport, isFalse);
    expect(Plan.conNo.canAdvancedReminders, isFalse);
    expect(Plan.conNo.showsAds, isTrue);
    expect(Plan.conNo.canAttachReceipt, isFalse);
    for (final p in [Plan.chuNo, Plan.doiNoThue]) {
      expect(p.isPro, isTrue);
      expect(p.canSplitUnevenly, isTrue);
      expect(p.canExportReport, isTrue);
      expect(p.canAdvancedReminders, isTrue);
      expect(p.showsAds, isFalse);
    }
    expect(Plan.doiNoThue.canShakeToPick, isTrue);
    expect(Plan.chuNo.canShakeToPick, isFalse);
  });

  test('gói trả phí có giá niêm yết, Con Nợ miễn phí', () {
    expect(Plan.conNo.monthlyPrice, 0);
    expect(Plan.chuNo.monthlyPrice, 29000);
    expect(Plan.doiNoThue.monthlyPrice, 99000);
  });

  test('tin nhắn nhắc nợ có tên, số tiền và xoay vòng câu', () {
    for (final plan in Plan.values) {
      final a = reminderMessage(
        plan: plan,
        debtor: 'Nam',
        creditor: 'Huy',
        amount: 150000,
        group: 'Phòng 302',
      );
      expect(a, contains('Nam'));
      expect(a, contains('150.000 ₫'));
    }
    final m0 = reminderMessage(
      plan: Plan.doiNoThue,
      debtor: 'A',
      creditor: 'B',
      amount: 1,
      group: 'G',
    );
    final m1 = reminderMessage(
      plan: Plan.doiNoThue,
      debtor: 'A',
      creditor: 'B',
      amount: 1,
      group: 'G',
      variant: 1,
    );
    expect(m0, isNot(m1));
  });

  test('lưu và đọc gói', () async {
    sqfliteFfiInit();
    final db = await AppDatabase.open(databaseFactoryFfi, inMemoryDatabasePath);
    final settings = SettingsRepository(db);
    expect(await settings.currentPlan(), Plan.conNo);
    await settings.setPlan(Plan.doiNoThue);
    expect(await settings.currentPlan(), Plan.doiNoThue);
    await db.close();
  });
}
