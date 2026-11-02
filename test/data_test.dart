import 'dart:io';

import 'package:chia_tien/data/activity_repository.dart';
import 'package:chia_tien/data/app_database.dart';
import 'package:chia_tien/data/expense_repository.dart';
import 'package:chia_tien/data/group_repository.dart';
import 'package:chia_tien/data/group_summary.dart';
import 'package:chia_tien/data/seed.dart';
import 'package:chia_tien/data/settlement_repository.dart';
import 'package:chia_tien/logic/money.dart';
import 'package:chia_tien/models/expense.dart';
import 'package:chia_tien/models/group.dart';
import 'package:chia_tien/models/member.dart';
import 'package:chia_tien/models/activity.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late GroupRepository groups;
  late ExpenseRepository expenses;
  late SettlementRepository settlements;

  setUp(() async {
    db = await AppDatabase.open(databaseFactoryFfi, inMemoryDatabasePath);
    groups = GroupRepository(db);
    expenses = ExpenseRepository(db);
    settlements = SettlementRepository(db);
  });
  tearDown(() => db.close());

  Future<(int, List<int>)> makeGroup() async {
    final id = await groups.create(
      Group(name: 'Test', createdAt: DateTime(2026, 11, 1)),
      [
        for (final n in ['An', 'Bình', 'Chi']) Member(groupId: 0, name: n),
      ],
    );
    return (id, (await groups.members(id)).map((m) => m.id!).toList());
  }

  test('tạo nhóm với thành viên', () async {
    final (id, ids) = await makeGroup();
    expect(ids.length, 3);
    expect((await groups.getById(id))!.name, 'Test');
    expect((await groups.members(id)).map((m) => m.name), [
      'An',
      'Bình',
      'Chi',
    ]);
  });

  test('thêm, sửa, xóa khoản chi kèm shares', () async {
    final (gid, ids) = await makeGroup();
    final id = await expenses.save(
      Expense(
        groupId: gid,
        title: 'Ăn tối',
        amount: 100000,
        paidBy: ids[0],
        splitType: 'equal',
        shares: splitEqual(100000, ids, remainderTo: ids[0]),
        date: DateTime(2026, 11, 1),
      ),
    );
    var e = (await expenses.byGroup(gid)).single;
    expect(e.shares, {ids[0]: 33334, ids[1]: 33333, ids[2]: 33333});

    await expenses.save(
      e.copyWith(
        amount: 60000,
        shares: {ids[1]: 30000, ids[2]: 30000},
        splitType: 'exact',
      ),
    );
    e = (await expenses.getById(id))!;
    expect(e.amount, 60000);
    expect(e.shares, {ids[1]: 30000, ids[2]: 30000});

    await expenses.delete(id);
    expect(await expenses.byGroup(gid), isEmpty);
    // shares bị xóa theo nhờ ON DELETE CASCADE
    expect(await db.query('expense_shares'), isEmpty);
  });

  test('không lưu khoản chi có tổng phần sai', () async {
    final (gid, ids) = await makeGroup();
    expect(
      () => expenses.save(
        Expense(
          groupId: gid,
          title: 'Sai',
          amount: 100,
          paidBy: ids[0],
          splitType: 'exact',
          shares: {ids[0]: 50, ids[1]: 40},
          date: DateTime(2026, 11, 1),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('tóm tắt nhóm: số dư, gợi ý, trả tiền', () async {
    final (gid, ids) = await makeGroup();
    await expenses.save(
      Expense(
        groupId: gid,
        title: 'Lẩu',
        amount: 300000,
        paidBy: ids[0],
        splitType: 'equal',
        shares: splitEqual(300000, ids),
        date: DateTime(2026, 11, 1),
      ),
    );
    var s = await GroupSummary.load(db, gid);
    expect(s.totalSpent, 300000);
    expect(s.balances, {ids[0]: 200000, ids[1]: -100000, ids[2]: -100000});
    expect(s.transfers.length, 2);

    await settlements.markPaid(gid, s.transfers.first);
    s = await GroupSummary.load(db, gid);
    expect(s.transfers.length, 1);
    expect(s.settlements.length, 1);
  });

  test('không xóa được thành viên đã có khoản chi', () async {
    final (gid, ids) = await makeGroup();
    await expenses.save(
      Expense(
        groupId: gid,
        title: 'x',
        amount: 1000,
        paidBy: ids[0],
        splitType: 'equal',
        shares: splitEqual(1000, [ids[0], ids[1]]),
        date: DateTime(2026, 11, 1),
      ),
    );
    expect(await groups.deleteMember(ids[1]), isFalse);
    expect(await groups.deleteMember(ids[2]), isTrue);
  });

  test('nhân bản nhóm: chép thành viên, không chép khoản chi', () async {
    final (id, ids) = await makeGroup();
    await groups.updateMember((await groups.members(id))
        .first
        .copyWith(bankBin: '970436', accountNo: '0123'));
    await expenses.save(Expense(
      groupId: id,
      title: 'Lẩu',
      amount: 300000,
      paidBy: ids[0],
      splitType: SplitType.equal,
      shares: {for (final m in ids) m: 100000},
      date: DateTime(2026, 11, 1),
    ));
    final copyId = await groups.duplicate(id, 'Test lần 2');
    expect(copyId, isNot(id));
    expect((await groups.getById(copyId))!.name, 'Test lần 2');
    final copied = await groups.members(copyId);
    expect(copied.map((m) => m.name), ['An', 'Bình', 'Chi']);
    expect(copied.first.accountNo, '0123');
    expect(copied.every((m) => !ids.contains(m.id)), isTrue);
    expect(await expenses.byGroup(copyId), isEmpty);
    expect((await groups.members(id)).length, 3);
  });

  test('xóa nhóm xóa luôn dữ liệu con', () async {
    final (gid, _) = await makeGroup();
    await groups.delete(gid);
    expect(await db.query('members'), isEmpty);
  });

  test('dữ liệu mẫu tạo được và chỉ tạo một lần', () async {
    await seedIfEmpty(db);
    await seedIfEmpty(db);
    final all = await groups.getAll();
    expect(all.map((g) => g.name), ['Đi ăn lẩu', 'Phòng 302']);
    final s = await GroupSummary.load(db, all.last.id!);
    expect(s.balances.values.reduce((a, b) => a + b), 0);
    expect(s.transfers.length, lessThanOrEqualTo(3));
  });

  test('lưu danh mục, ghi chú và trọng số khi chia theo phần', () async {
    final (gid, ids) = await makeGroup();
    final weights = {ids[0]: 2, ids[1]: 1, ids[2]: 1};
    final id = await expenses.save(
      Expense(
        groupId: gid,
        title: 'Đi chợ',
        amount: 400000,
        paidBy: ids[0],
        splitType: SplitType.shares,
        shares: splitByWeights(weights, 400000),
        weights: weights,
        category: 'food',
        note: 'Chợ Bến Thành',
        date: DateTime(2026, 11, 1),
      ),
    );
    final e = (await expenses.getById(id))!;
    expect(e.weights, weights);
    expect(e.shares, {ids[0]: 200000, ids[1]: 100000, ids[2]: 100000});
    expect(e.category, 'food');
    expect(e.note, 'Chợ Bến Thành');
    expect((await expenses.byGroup(gid)).single.weights, weights);
  });

  test('ghi nhận trả một phần', () async {
    final (gid, ids) = await makeGroup();
    await expenses.save(
      Expense(
        groupId: gid,
        title: 'Lẩu',
        amount: 300000,
        paidBy: ids[0],
        splitType: SplitType.equal,
        shares: splitEqual(300000, ids),
        date: DateTime(2026, 11, 1),
      ),
    );
    await settlements.record(
      groupId: gid,
      fromId: ids[1],
      toId: ids[0],
      amount: 40000,
      note: 'tiền mặt',
    );
    final s = await GroupSummary.load(db, gid);
    expect(s.balances[ids[1]], -60000);
    expect(s.settlements.single.note, 'tiền mặt');
    expect(
      () => settlements.record(
          groupId: gid, fromId: ids[0], toId: ids[0], amount: 1),
      throwsArgumentError,
    );
  });

  test('không trả được quá số nợ, bấm "Đã trả" lần 2 bị chặn', () async {
    final (gid, ids) = await makeGroup();
    await expenses.save(
      Expense(
        groupId: gid,
        title: 'Lẩu',
        amount: 300000,
        paidBy: ids[0],
        splitType: SplitType.equal,
        shares: splitEqual(300000, ids),
        date: DateTime(2026, 11, 1),
      ),
    );
    final t = (await GroupSummary.load(db, gid)).transfers.first;
    expect(await settlements.maxPayable(gid, t.fromId, t.toId), t.amount);

    // Bấm liên tục 3 lần cùng lúc: chỉ lần đầu được ghi.
    final results = await Future.wait([
      for (var i = 0; i < 3; i++)
        settlements
            .markPaid(gid, t)
            .then<Object>((id) => id, onError: (Object e) => e),
    ]);
    expect(results.whereType<int>().length, 1);
    expect(results.whereType<OverpaymentException>().length, 2);
    expect((await settlements.byGroup(gid)).length, 1);
    expect(await settlements.maxPayable(gid, t.fromId, t.toId), 0);

    // Người kia trả quá số nợ cũng bị chặn, trả đúng thì được.
    final other = ids.firstWhere((id) => id != ids[0] && id != t.fromId);
    await expectLater(
      settlements.record(
          groupId: gid, fromId: other, toId: ids[0], amount: 100001),
      throwsA(isA<OverpaymentException>()
          .having((e) => e.maxPayable, 'maxPayable', 100000)),
    );
    await settlements.record(
        groupId: gid, fromId: other, toId: ids[0], amount: 100000);
    final s = await GroupSummary.load(db, gid);
    expect(s.transfers, isEmpty);
    expect(s.balances.values.every((b) => b == 0), isTrue);
  });

  test('lịch sử hoạt động mới nhất trước, lọc theo nhóm', () async {
    final log = ActivityRepository(db);
    await log.log(
        groupId: 1,
        groupName: 'A',
        kind: ActivityKind.expenseAdded,
        message: 'một',
        at: DateTime(2026, 11, 1));
    await log.log(
        groupId: 2,
        groupName: 'B',
        kind: ActivityKind.settled,
        message: 'hai',
        amount: 5000,
        at: DateTime(2026, 11, 2));
    expect((await log.recent()).map((a) => a.message), ['hai', 'một']);
    expect((await log.recent(groupId: 1)).single.message, 'một');
    expect((await log.recent()).first.amount, 5000);
  });

  test('nâng cấp database bản 1 lên bản 2 giữ nguyên dữ liệu', () async {
    final dir = await Directory.systemTemp.createTemp('chipin_test');
    final path = '${dir.path}/old.db';
    // Tạo database theo cấu trúc bản 1.
    final old = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
              'CREATE TABLE groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL, created_at INTEGER NOT NULL)');
          await db.execute(
              'CREATE TABLE members (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id INTEGER NOT NULL, name TEXT NOT NULL, bank_bin TEXT, account_no TEXT, account_name TEXT)');
          await db.execute(
              'CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id INTEGER NOT NULL, title TEXT NOT NULL, amount INTEGER NOT NULL, paid_by INTEGER NOT NULL, split_type TEXT NOT NULL, receipt_path TEXT, date INTEGER NOT NULL)');
          await db.execute(
              'CREATE TABLE expense_shares (expense_id INTEGER NOT NULL, member_id INTEGER NOT NULL, amount INTEGER NOT NULL, PRIMARY KEY (expense_id, member_id))');
          await db.execute(
              'CREATE TABLE settlements (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id INTEGER NOT NULL, from_id INTEGER NOT NULL, to_id INTEGER NOT NULL, amount INTEGER NOT NULL, paid_at INTEGER NOT NULL)');
          await db.execute(
              'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)');
        },
      ),
    );
    await old.insert('groups', {'name': 'Cũ', 'type': 'meal', 'created_at': 0});
    await old.insert('members', {'group_id': 1, 'name': 'An'});
    await old.insert('expenses', {
      'group_id': 1,
      'title': 'Phở',
      'amount': 50000,
      'paid_by': 1,
      'split_type': 'equal',
      'date': 0,
    });
    await old.insert(
        'expense_shares', {'expense_id': 1, 'member_id': 1, 'amount': 50000});
    await old.close();

    final upgraded = await AppDatabase.open(databaseFactoryFfi, path);
    expect(await upgraded.getVersion(), AppDatabase.version);
    final e = (await ExpenseRepository(upgraded).byGroup(1)).single;
    expect(e.title, 'Phở');
    expect(e.category, isNull);
    expect(e.weights, isEmpty);
    await ActivityRepository(upgraded).log(
        groupId: 1, groupName: 'Cũ', kind: ActivityKind.groupEdited, message: 'x');
    expect((await ActivityRepository(upgraded).recent()).length, 1);
    await upgraded.close();
    await dir.delete(recursive: true);
  });
}
