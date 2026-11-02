import 'dart:math';

import '../models/expense.dart';
import '../models/member.dart';
import '../models/settlement.dart';
import 'balances.dart';
import 'debt_simplifier.dart';

/// Sổ chung: chủ sổ giữ dữ liệu gốc trên máy (sqflite) và đẩy một bản chụp
/// lên Firestore để các thành viên (mỗi người một tài khoản) cùng xem.
///
/// File này chỉ có phần chuyển đổi thuần Dart, không đụng Firebase, để test
/// được bằng `flutter test`.
///
/// Firestore không cho khóa Map là số nên id thành viên được ghi thành chuỗi.
Map<String, Object?> encodeLedgerSnapshot({
  required List<Member> members,
  required List<Expense> expenses,
  required List<Settlement> settlements,
}) =>
    {
      'members': [
        for (final m in members)
          {
            'id': m.id,
            'name': m.name,
            'bankBin': m.bankBin,
            'accountNo': m.accountNo,
            'accountName': m.accountName,
          },
      ],
      'expenses': [
        for (final e in expenses)
          {
            'id': e.id,
            'title': e.title,
            'amount': e.amount,
            'paidBy': e.paidBy,
            'splitType': e.splitType,
            'shares': {
              for (final s in e.shares.entries) '${s.key}': s.value,
            },
            'category': e.category,
            'note': e.note,
            'date': e.date.millisecondsSinceEpoch,
          },
      ],
      'settlements': [
        for (final s in settlements)
          {
            'id': s.id,
            'fromId': s.fromId,
            'toId': s.toId,
            'amount': s.amount,
            'paidAt': s.paidAt.millisecondsSinceEpoch,
            'note': s.note,
          },
      ],
    };

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

List<Map<String, dynamic>> _rows(Object? v) => [
      for (final r in (v as List?) ?? const [])
        Map<String, dynamic>.from(r as Map),
    ];

/// Dữ liệu một sổ chung đã đọc về, kèm số dư và gợi ý trả nợ tính sẵn.
class LedgerData {
  final List<Member> members;
  final List<Expense> expenses;
  final List<Settlement> settlements;
  final Map<int, int> balances;
  final List<Transfer> transfers;

  LedgerData._(this.members, this.expenses, this.settlements, this.balances,
      this.transfers);

  factory LedgerData({
    required List<Member> members,
    required List<Expense> expenses,
    required List<Settlement> settlements,
  }) {
    final balances = computeBalances(expenses, settlements,
        memberIds: members.map((m) => m.id!));
    return LedgerData._(
        members, expenses, settlements, balances, simplifyDebts(balances));
  }

  /// Đọc ngược từ [encodeLedgerSnapshot]. Dữ liệu thiếu thì coi như rỗng.
  factory LedgerData.decode(Map<String, dynamic>? snap) {
    final members = [
      for (final m in _rows(snap?['members']))
        Member(
          id: _int(m['id']),
          groupId: 0,
          name: m['name'] as String? ?? '?',
          bankBin: m['bankBin'] as String?,
          accountNo: m['accountNo'] as String?,
          accountName: m['accountName'] as String?,
        ),
    ];
    final expenses = [
      for (final e in _rows(snap?['expenses']))
        Expense(
          id: _int(e['id']),
          groupId: 0,
          title: e['title'] as String? ?? '',
          amount: _int(e['amount']),
          paidBy: _int(e['paidBy']),
          splitType: e['splitType'] as String? ?? SplitType.equal,
          shares: {
            for (final s in ((e['shares'] as Map?) ?? const {}).entries)
              int.parse('${s.key}'): _int(s.value),
          },
          category: e['category'] as String?,
          note: e['note'] as String?,
          date: DateTime.fromMillisecondsSinceEpoch(_int(e['date'])),
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    final settlements = [
      for (final s in _rows(snap?['settlements']))
        Settlement(
          id: _int(s['id']),
          groupId: 0,
          fromId: _int(s['fromId']),
          toId: _int(s['toId']),
          amount: _int(s['amount']),
          paidAt: DateTime.fromMillisecondsSinceEpoch(_int(s['paidAt'])),
          note: s['note'] as String?,
        ),
    ]..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return LedgerData(
        members: members, expenses: expenses, settlements: settlements);
  }

  Member? memberById(int? id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  String nameOf(int? id) => memberById(id)?.name ?? '?';

  int get totalSpent => expenses.fold(0, (sum, e) => sum + e.amount);
}

/// Những lượt "X trả chủ sổ" mà X đã có tài khoản trong sổ, tức là chủ sổ
/// gửi nhắc nợ được. [links] là uid -> id thành viên.
/// Trả về danh sách (lượt chuyển, uid của người nợ).
List<(Transfer, String)> remindableDebts({
  required List<Transfer> transfers,
  required int? ownerMemberId,
  required Map<String, int> links,
  required String ownerUid,
}) {
  if (ownerMemberId == null) return const [];
  return [
    for (final t in transfers)
      if (t.toId == ownerMemberId)
        for (final l in links.entries)
          if (l.value == t.fromId && l.key != ownerUid) (t, l.key),
  ];
}

/// Mã mời 6 ký tự, bỏ các chữ dễ nhầm (0/O, 1/I/L).
const inviteAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String generateInviteCode([Random? random]) {
  final r = random ?? Random.secure();
  return List.generate(
      6, (_) => inviteAlphabet[r.nextInt(inviteAlphabet.length)]).join();
}

/// Chuẩn hóa mã người dùng gõ: bỏ khoảng trắng, viết hoa.
String normalizeInviteCode(String input) =>
    input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

bool isValidInviteCode(String code) =>
    code.length == 6 && code.split('').every(inviteAlphabet.contains);
