import 'dart:math';

import 'package:chia_tien/logic/ledger_snapshot.dart';
import 'package:chia_tien/models/expense.dart';
import 'package:chia_tien/models/member.dart';
import 'package:chia_tien/models/settlement.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final members = [
    const Member(id: 1, groupId: 9, name: 'Huy', bankBin: '970436', accountNo: '123'),
    const Member(id: 2, groupId: 9, name: 'Nam'),
    const Member(id: 3, groupId: 9, name: 'Lan'),
  ];
  final expenses = [
    Expense(
      id: 10,
      groupId: 9,
      title: 'Lẩu',
      amount: 300000,
      paidBy: 1,
      splitType: SplitType.equal,
      shares: const {1: 100000, 2: 100000, 3: 100000},
      date: DateTime(2026, 11, 1, 19),
    ),
  ];
  final settlements = [
    Settlement(
        id: 5, groupId: 9, fromId: 3, toId: 1, amount: 100000,
        paidAt: DateTime(2026, 11, 2)),
  ];

  group('Bản chụp sổ chung', () {
    test('khóa Map là chuỗi để Firestore nhận', () {
      final snap = encodeLedgerSnapshot(
          members: members, expenses: expenses, settlements: settlements);
      final e = (snap['expenses'] as List).first as Map;
      expect((e['shares'] as Map).keys, everyElement(isA<String>()));
    });

    test('ghi rồi đọc lại ra cùng số dư', () {
      final snap = encodeLedgerSnapshot(
          members: members, expenses: expenses, settlements: settlements);
      final d = LedgerData.decode(snap);
      expect(d.members.map((m) => m.name), ['Huy', 'Nam', 'Lan']);
      expect(d.memberById(1)!.hasBank, isTrue);
      expect(d.expenses.single.shares, {1: 100000, 2: 100000, 3: 100000});
      expect(d.balances, {1: 100000, 2: -100000, 3: 0});
      expect(d.transfers, [const Transfer(2, 1, 100000)]);
      expect(d.totalSpent, 300000);
    });

    test('dữ liệu rỗng không lỗi', () {
      final d = LedgerData.decode(null);
      expect(d.members, isEmpty);
      expect(d.transfers, isEmpty);
      expect(d.nameOf(4), '?');
    });
  });

  group('Ai được nhắc nợ', () {
    const transfers = [Transfer(2, 1, 50000), Transfer(3, 4, 20000)];

    test('chỉ người nợ chủ sổ và đã có tài khoản', () {
      final r = remindableDebts(
        transfers: transfers,
        ownerMemberId: 1,
        links: {'owner': 1, 'uNam': 2, 'uLan': 3},
        ownerUid: 'owner',
      );
      expect(r, [(const Transfer(2, 1, 50000), 'uNam')]);
    });

    test('người nợ chưa nhập mã thì không nhắc được', () {
      final r = remindableDebts(
        transfers: transfers,
        ownerMemberId: 1,
        links: {'owner': 1},
        ownerUid: 'owner',
      );
      expect(r, isEmpty);
    });

    test('chưa chọn chủ sổ là ai thì không nhắc', () {
      expect(
          remindableDebts(
              transfers: transfers,
              ownerMemberId: null,
              links: {'uNam': 2},
              ownerUid: 'owner'),
          isEmpty);
    });
  });

  group('Mã mời', () {
    test('6 ký tự, không có chữ dễ nhầm', () {
      final r = Random(1);
      for (var i = 0; i < 200; i++) {
        final c = generateInviteCode(r);
        expect(isValidInviteCode(c), isTrue, reason: c);
        expect(c, isNot(matches(RegExp('[01OIL]'))));
      }
    });

    test('chuẩn hóa mã người dùng gõ', () {
      expect(normalizeInviteCode(' k7q-x2m '), 'K7QX2M');
      expect(isValidInviteCode(normalizeInviteCode('k7qx2m')), isTrue);
      expect(isValidInviteCode('K7QX'), isFalse);
      expect(isValidInviteCode('K7QX0M'), isFalse);
    });
  });
}
