import 'package:chia_tien/data/app_database.dart';
import 'package:chia_tien/data/settings_repository.dart';
import 'package:chia_tien/logic/plans.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('giới hạn nhóm theo gói', () {
    expect(Plan.conNo.canCreateGroup(1), isTrue);
    expect(Plan.conNo.canCreateGroup(2), isFalse);
    expect(Plan.chuNo.canCreateGroup(100), isTrue);
    expect(Plan.conNo.canAttachReceipt, isFalse);
    expect(Plan.doiNoThue.canShakeToPick, isTrue);
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
