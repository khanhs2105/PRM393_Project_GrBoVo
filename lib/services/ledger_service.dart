import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../data/group_repository.dart';
import '../data/group_summary.dart';
import '../data/settings_repository.dart';
import '../logic/ledger_snapshot.dart';
import '../logic/money.dart';
import '../models/member.dart';
import 'notification_service.dart';

/// Một sổ chung trên Firestore.
class SharedLedger {
  final String id;
  final String name;
  final String type;
  final String ownerUid;
  final String ownerName;

  /// Chủ sổ là thành viên nào trong sổ.
  final int? ownerMemberId;

  /// Mọi tài khoản trong sổ, kể cả chủ sổ.
  final List<String> memberUids;

  /// uid -> id thành viên mà tài khoản đó đứng tên.
  final Map<String, int> links;

  /// uid -> tên hiển thị của tài khoản (lúc tham gia).
  final Map<String, String> linkNames;
  final LedgerData data;
  final DateTime? updatedAt;

  const SharedLedger({
    required this.id,
    required this.name,
    required this.type,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerMemberId,
    required this.memberUids,
    required this.links,
    required this.linkNames,
    required this.data,
    required this.updatedAt,
  });

  factory SharedLedger.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SharedLedger(
      id: doc.id,
      name: d['name'] as String? ?? 'Sổ chung',
      type: d['type'] as String? ?? 'other',
      ownerUid: d['ownerUid'] as String? ?? '',
      ownerName: d['ownerName'] as String? ?? 'Chủ sổ',
      ownerMemberId: (d['ownerMemberId'] as num?)?.toInt(),
      memberUids: [
        for (final u in (d['memberUids'] as List?) ?? const []) '$u'
      ],
      links: {
        for (final e in ((d['links'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as num).toInt(),
      },
      linkNames: {
        for (final e in ((d['linkNames'] as Map?) ?? const {}).entries)
          '${e.key}': '${e.value}',
      },
      data: LedgerData.decode(
          (d['snapshot'] as Map?)?.cast<String, dynamic>()),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool isOwner(String? uid) => uid != null && uid == ownerUid;

  /// Thành viên mà tài khoản [uid] đứng tên, null nếu chưa liên kết.
  int? memberIdOf(String? uid) => uid == null ? null : links[uid];

  /// Các tài khoản đã liên kết với thành viên [memberId].
  List<String> uidsOf(int? memberId) => [
        for (final e in links.entries)
          if (e.value == memberId) e.key,
      ];

  /// Tên tài khoản đứng tên thành viên [memberId], null nếu chưa ai nhận.
  String? accountNameOf(int? memberId) {
    final uids = uidsOf(memberId);
    if (uids.isEmpty) return null;
    return uids.map((u) => linkNames[u] ?? 'Tài khoản').join(', ');
  }
}

/// Lời nhắc nợ chủ sổ gửi cho một thành viên.
class LedgerNotice {
  final String id;
  final String ledgerId;
  final String ledgerName;
  final String fromName;
  final int amount;
  final String message;
  final DateTime? createdAt;
  final bool delivered;

  const LedgerNotice({
    required this.id,
    required this.ledgerId,
    required this.ledgerName,
    required this.fromName,
    required this.amount,
    required this.message,
    required this.createdAt,
    required this.delivered,
  });

  factory LedgerNotice.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return LedgerNotice(
      id: doc.id,
      ledgerId: d['ledgerId'] as String? ?? '',
      ledgerName: d['ledgerName'] as String? ?? '',
      fromName: d['fromName'] as String? ?? 'Chủ sổ',
      amount: (d['amount'] as num?)?.toInt() ?? 0,
      message: d['message'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      delivered: d['delivered'] == true,
    );
  }
}

/// Sổ chung nhiều tài khoản:
///
/// - Chủ sổ tạo nhóm trên máy như cũ rồi bật "sổ chung". App đẩy bản chụp
///   nhóm lên `ledgers/{id}` mỗi khi mở hoặc sửa nhóm.
/// - Chủ sổ tạo mã mời cho từng thành viên (`invites/{mã}`). Người được mời
///   đăng nhập tài khoản của mình, nhập mã là vào sổ và đứng tên đúng thành
///   viên đó, nên app biết thành viên nào là tài khoản nào.
/// - Chỉ chủ sổ ghi `notifications`, mỗi lời nhắc gửi tới một uid. App của
///   người nhận lắng nghe và bật thông báo trên máy.
///
/// Firestore rules (firestore.rules) chặn: người ngoài đọc sổ, thành viên sửa
/// sổ, và ai không phải chủ sổ gửi nhắc nợ.
class LedgerService {
  LedgerService(
      {FirebaseFirestore? firestore, FirebaseAuth? auth, Database? localDb})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _local = localDb;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  Database? _local;

  /// Gắn database trên máy của tài khoản đang đăng nhập (App.openForUser).
  void attach(Database db) => _local = db;

  static const _timeout = Duration(seconds: 15);

  String? get uid => _auth.currentUser?.uid;

  String get _myName {
    final u = _auth.currentUser;
    final n = u?.displayName?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return u?.email?.split('@').first ?? 'Bạn';
  }

  String _requireUid() {
    final u = uid;
    if (u == null) throw StateError('Bạn chưa đăng nhập');
    return u;
  }

  CollectionReference<Map<String, dynamic>> get _ledgers =>
      _db.collection('ledgers');
  CollectionReference<Map<String, dynamic>> get _invites =>
      _db.collection('invites');
  CollectionReference<Map<String, dynamic>> get _notices =>
      _db.collection('notifications');

  SettingsRepository get _settings => SettingsRepository(_local!);

  // Khóa lưu trên máy: nhóm nào đã thành sổ chung nào. Gắn theo uid để
  // đăng nhập tài khoản khác trên cùng máy thì không nhận nhầm.
  String _key(int groupId) => 'ledger_${uid}_$groupId';

  /// Id sổ chung của nhóm [groupId] trên máy này, null nếu chưa bật.
  Future<String?> ledgerIdOf(int groupId) async {
    if (uid == null || _local == null) return null;
    return _settings.get(_key(groupId));
  }

  Future<Map<String, Object?>> _snapshot(int groupId) async {
    final s = await GroupSummary.load(_local!, groupId);
    return encodeLedgerSnapshot(
        members: s.members, expenses: s.expenses, settlements: s.settlements);
  }

  /// Bật sổ chung cho nhóm: tạo `ledgers/{id}` với chủ sổ là mình.
  Future<String> share(int groupId, {required int ownerMemberId}) async {
    final me = _requireUid();
    final group = await GroupRepository(_local!).getById(groupId);
    if (group == null) throw StateError('Không tìm thấy nhóm');
    final doc = _ledgers.doc();
    await doc.set({
      'name': group.name,
      'type': group.type,
      'ownerUid': me,
      'ownerName': _myName,
      'ownerMemberId': ownerMemberId,
      'memberUids': [me],
      'links': {me: ownerMemberId},
      'linkNames': {me: _myName},
      'snapshot': await _snapshot(groupId),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
    await _settings.set(_key(groupId), doc.id);
    return doc.id;
  }

  /// Đẩy dữ liệu mới nhất của nhóm lên sổ chung (nếu nhóm đã bật).
  /// Lỗi mạng thì bỏ qua, lần mở nhóm sau sẽ đẩy lại.
  Future<void> publish(int groupId) async {
    try {
      final id = await ledgerIdOf(groupId);
      if (id == null) return;
      final group = await GroupRepository(_local!).getById(groupId);
      if (group == null) return;
      await _ledgers.doc(id).update({
        'name': group.name,
        'type': group.type,
        'ownerName': _myName,
        'snapshot': await _snapshot(groupId),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(_timeout);
    } catch (e) {
      debugPrint('Không đồng bộ được sổ chung: $e');
    }
  }

  /// Đổi "chủ sổ là thành viên nào".
  Future<void> setOwnerMember(String ledgerId, int memberId) async {
    final me = _requireUid();
    await _ledgers.doc(ledgerId).update({
      'ownerMemberId': memberId,
      'links.$me': memberId,
    }).timeout(_timeout);
  }

  /// Tắt sổ chung: xóa sổ trên Firestore, thành viên không xem được nữa.
  Future<void> unshare(int groupId) async {
    final id = await ledgerIdOf(groupId);
    if (id == null) return;
    try {
      await _ledgers.doc(id).delete().timeout(_timeout);
    } catch (e) {
      debugPrint('Không xóa được sổ chung: $e');
    }
    await _settings.set(_key(groupId), null);
  }

  Future<SharedLedger?> fetch(String ledgerId) async {
    final doc = await _ledgers.doc(ledgerId).get().timeout(_timeout);
    return doc.exists ? SharedLedger.fromDoc(doc) : null;
  }

  /// Sổ đang mở, tự cập nhật khi chủ sổ sửa. null nếu sổ bị xóa hoặc mình
  /// không còn quyền xem.
  Stream<SharedLedger?> watch(String ledgerId) => _ledgers
      .doc(ledgerId)
      .snapshots()
      .map((d) => d.exists ? SharedLedger.fromDoc(d) : null);

  /// Các sổ người khác mời mình vào (không gồm sổ mình làm chủ).
  Stream<List<SharedLedger>> joinedLedgers() {
    final me = uid;
    if (me == null) return Stream.value(const []);
    return _ledgers
        .where('memberUids', arrayContains: me)
        .snapshots()
        .map((q) => [
              for (final d in q.docs)
                if (d.data()['ownerUid'] != me) SharedLedger.fromDoc(d),
            ]);
  }

  /// Tạo mã mời cho thành viên [member]: ai nhập mã này sẽ đứng tên
  /// thành viên đó trong sổ.
  Future<String> createInvite(SharedLedger ledger, Member member) async {
    final me = _requireUid();
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = generateInviteCode();
      final ref = _invites.doc(code);
      try {
        // create (không ghi đè): mã trùng của sổ khác thì rules từ chối.
        await _db.runTransaction((tx) async {
          final existing = await tx.get(ref);
          if (existing.exists) throw const _CodeTaken();
          tx.set(ref, {
            'ledgerId': ledger.id,
            'ledgerName': ledger.name,
            'memberId': member.id,
            'memberName': member.name,
            'ownerUid': me,
            'ownerName': _myName,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }).timeout(_timeout);
        return code;
      } on _CodeTaken {
        continue;
      }
    }
    throw StateError('Không tạo được mã mời, thử lại nhé');
  }

  /// Nhập mã mời: vào sổ và đứng tên thành viên ghi trong mã.
  /// Trả về id sổ.
  Future<String> join(String rawCode) async {
    final me = _requireUid();
    final code = normalizeInviteCode(rawCode);
    if (!isValidInviteCode(code)) {
      throw const FormatException('Mã mời gồm 6 ký tự, ví dụ K7QX2M');
    }
    final inv = await _invites.doc(code).get().timeout(_timeout);
    final data = inv.data();
    if (!inv.exists || data == null) {
      throw const FormatException('Mã mời không đúng hoặc đã bị xóa');
    }
    if (data['ownerUid'] == me) {
      throw const FormatException(
          'Đây là mã của sổ do bạn tạo. Gửi mã cho bạn bè để họ nhập nhé.');
    }
    final ledgerId = data['ledgerId'] as String;
    await _ledgers.doc(ledgerId).update({
      'memberUids': FieldValue.arrayUnion([me]),
      'links.$me': (data['memberId'] as num).toInt(),
      'linkNames.$me': _myName,
      'lastJoinCode': code,
    }).timeout(_timeout);
    return ledgerId;
  }

  /// Chủ sổ gỡ một tài khoản khỏi sổ (vd. ai đó nhập nhầm mã).
  Future<void> removeAccount(String ledgerId, String accountUid) =>
      _ledgers.doc(ledgerId).update({
        'memberUids': FieldValue.arrayRemove([accountUid]),
        'links.$accountUid': FieldValue.delete(),
        'linkNames.$accountUid': FieldValue.delete(),
      }).timeout(_timeout);

  /// Chủ sổ gửi nhắc nợ tới tài khoản [toUid].
  Future<void> remind({
    required SharedLedger ledger,
    required String toUid,
    required int amount,
    required String message,
    DateTime? at,
  }) async {
    final me = _requireUid();
    if (!ledger.isOwner(me)) {
      throw StateError('Chỉ chủ sổ mới gửi được nhắc nợ');
    }
    if (toUid == me) {
      throw StateError('Không tự nhắc nợ chính mình được');
    }
    await _notices.add({
      // Hẹn giờ: máy người nợ nhận ngay rồi tự đặt lịch trên máy họ.
      if (at != null) 'deliverAt': Timestamp.fromDate(at),
      'ledgerId': ledger.id,
      'ledgerName': ledger.name,
      'fromUid': me,
      'fromName': _myName,
      'toUid': toUid,
      'amount': amount,
      'message': message,
      'delivered': false,
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }

  /// Tìm tài khoản của người nợ trong lượt chuyển [t] của nhóm [groupId]
  /// để gửi nhắc nợ tới máy họ. Trả về (sổ, uid người nợ), hoặc ném
  /// [StateError] với lời giải thích nếu không gửi được.
  Future<(SharedLedger, String)> debtorAccount(
      int groupId, int fromId, int toId) async {
    final me = _requireUid();
    final id = await ledgerIdOf(groupId);
    if (id == null) {
      throw StateError('Nhóm chưa bật sổ chung. Vào tab Thành viên > '
          'Bật sổ chung rồi mời người nợ, lời nhắc mới tới được máy họ.');
    }
    final ledger = await fetch(id);
    if (ledger == null) throw StateError('Không đọc được sổ chung');
    if (!ledger.isOwner(me)) {
      throw StateError('Chỉ chủ sổ mới gửi được nhắc nợ');
    }
    if (toId != ledger.ownerMemberId) {
      throw StateError('Chỉ nhắc được người đang nợ bạn (chủ sổ).');
    }
    final uids = ledger.uidsOf(fromId).where((u) => u != me).toList();
    if (uids.isEmpty) {
      throw StateError('Người này chưa có tài khoản trong sổ. Vào tab '
          'Thành viên, bấm "Mời" và gửi mã cho họ trước.');
    }
    return (ledger, uids.first);
  }

  /// Câu nhắc mặc định.
  String defaultReminder(SharedLedger ledger, String debtorName, int amount) =>
      'Alo $debtorName, trả tiền! Bạn đang nợ $_myName ${formatVnd(amount)} '
      'trong sổ "${ledger.name}".';

  /// Lời nhắc mình nhận được trong một sổ, mới nhất trước.
  Stream<List<LedgerNotice>> noticesFor(String ledgerId) {
    final me = uid;
    if (me == null) return Stream.value(const []);
    // Hai điều kiện bằng (==) không cần tạo composite index; sắp xếp ở máy.
    return _notices
        .where('toUid', isEqualTo: me)
        .where('ledgerId', isEqualTo: ledgerId)
        .snapshots()
        .map((q) => [for (final d in q.docs) LedgerNotice.fromDoc(d)]
          ..sort((a, b) => (b.createdAt ?? DateTime.now())
              .compareTo(a.createdAt ?? DateTime.now())));
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _inbox;

  /// Lắng nghe lời nhắc gửi tới mình. Lời nhắc mới thì bật thông báo trên
  /// máy rồi đánh dấu đã nhận để không báo lại. Gọi khi đã đăng nhập.
  Future<void> startInbox() async {
    final me = uid;
    if (me == null) return;
    await stopInbox();
    try {
      await NotificationService.requestPermission();
    } catch (e) {
      debugPrint('Không xin được quyền thông báo: $e');
    }
    _inbox = _notices
        .where('toUid', isEqualTo: me)
        .where('delivered', isEqualTo: false)
        .snapshots()
        .listen((q) async {
      for (final change in q.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final n = LedgerNotice.fromDoc(change.doc);
        // Phòng hờ: chỉ hiện lời nhắc gửi cho đúng mình, không phải mình gửi.
        final data = change.doc.data() ?? const {};
        if (data['toUid'] != me || data['fromUid'] == me) continue;
        final deliverAt = (data['deliverAt'] as Timestamp?)?.toDate();
        try {
          final id = n.id.hashCode & 0x7fffffff;
          final title = '${n.fromName} nhắc nợ · ${n.ledgerName}';
          if (deliverAt != null && deliverAt.isAfter(DateTime.now())) {
            // Lời nhắc hẹn giờ: đặt lịch ngay trên máy người nợ.
            await NotificationService.schedule(
                at: deliverAt, title: title, body: n.message, id: id);
          } else {
            await NotificationService.show(
                id: id, title: title, body: n.message);
          }
          await change.doc.reference.update({
            'delivered': true,
            'deliveredAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Không hiện được nhắc nợ: $e');
        }
      }
    }, onError: (Object e) => debugPrint('inbox: $e'));
  }

  Future<void> stopInbox() async {
    await _inbox?.cancel();
    _inbox = null;
  }
}

class _CodeTaken implements Exception {
  const _CodeTaken();
}
