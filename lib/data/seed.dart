import 'package:sqflite_common/sqlite_api.dart';

import '../logic/money.dart';
import '../models/expense.dart';
import '../models/group.dart';
import '../models/member.dart';
import 'expense_repository.dart';
import 'group_repository.dart';

/// Tạo dữ liệu mẫu để demo nếu database đang trống.
/// Số tài khoản ở đây là số giả, chỉ để hiện QR khi demo.
Future<void> seedIfEmpty(Database db) async {
  final groups = GroupRepository(db);
  if ((await groups.getAll()).isNotEmpty) return;

  final expenses = ExpenseRepository(db);
  final now = DateTime.now();

  // Nhóm 1: phòng trọ
  final roomId = await groups.create(
    Group(name: 'Phòng 302', type: 'room', createdAt: now),
    [
      const Member(
        groupId: 0,
        name: 'Huy',
        bankBin: '970436',
        accountNo: '0123456789',
        accountName: 'NGUYEN QUANG HUY',
      ),
      const Member(
        groupId: 0,
        name: 'Nam',
        bankBin: '970422',
        accountNo: '9704229999',
        accountName: 'TRAN VAN NAM',
      ),
      const Member(groupId: 0, name: 'Minh'),
      const Member(groupId: 0, name: 'Tuấn'),
    ],
  );
  final room = await groups.members(roomId);
  final roomIds = room.map((m) => m.id!).toList();

  Future<void> add(
    int groupId,
    String title,
    int amount,
    int paidBy,
    List<int> ids,
    int daysAgo,
  ) {
    return expenses.save(
      Expense(
        groupId: groupId,
        title: title,
        amount: amount,
        paidBy: paidBy,
        splitType: 'equal',
        shares: splitEqual(amount, ids, remainderTo: paidBy),
        date: now.subtract(Duration(days: daysAgo)),
      ),
    );
  }

  await add(roomId, 'Tiền phòng tháng 11', 4000000, roomIds[0], roomIds, 5);
  await add(roomId, 'Tiền điện tháng 10', 685000, roomIds[1], roomIds, 4);
  await add(roomId, 'Wifi', 220000, roomIds[0], roomIds, 3);
  await add(roomId, 'Nước uống + giấy vệ sinh', 157000, roomIds[2], roomIds, 1);

  // Nhóm 2: đi ăn
  final mealId = await groups.create(
    Group(
      name: 'Đi ăn lẩu',
      type: 'meal',
      createdAt: now.add(const Duration(seconds: 1)),
    ),
    [
      const Member(
        groupId: 0,
        name: 'Huy',
        bankBin: '970436',
        accountNo: '0123456789',
        accountName: 'NGUYEN QUANG HUY',
      ),
      const Member(groupId: 0, name: 'Lan'),
      const Member(groupId: 0, name: 'Phương'),
    ],
  );
  final meal = (await groups.members(mealId)).map((m) => m.id!).toList();
  await add(mealId, 'Lẩu Thái', 720000, meal[0], meal, 0);
  await add(mealId, 'Trà sữa', 100000, meal[1], meal, 0);
}
