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
}
