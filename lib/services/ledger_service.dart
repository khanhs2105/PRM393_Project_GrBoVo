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

  /// Thời hạn của một mã mời.
  static const inviteTtl = Duration(days: 7);

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
    // Nhóm đã có sổ chung thì dùng lại, không tạo sổ thứ hai (thành viên
    // ở sổ cũ sẽ không bao giờ thấy cập nhật nữa).
    final existing = await ledgerIdOf(groupId);
    if (existing != null) return existing;
    final group = await GroupRepository(_local!).getById(groupId);
    if (group == null) throw StateError('Không tìm thấy nhóm');
    final doc = _ledgers.doc();
    // Lưu khóa trước khi ghi: offline thì lệnh ghi vẫn nằm trong hàng đợi
    // và sẽ gửi khi có mạng, bấm lại không tạo thêm sổ.
    await _settings.set(_key(groupId), doc.id);
    try {
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
    } on TimeoutException {
      // Mất mạng: lệnh ghi vẫn chờ trong hàng đợi, giữ khóa.
      rethrow;
    } catch (_) {
      await _settings.set(_key(groupId), null);
      rethrow;
    }
    return doc.id;
  }

  /// Đẩy dữ liệu mới nhất của nhóm lên sổ chung (nếu nhóm đã bật).
  /// Lỗi mạng thì bỏ qua, lần mở nhóm sau sẽ đẩy lại. Trả về false nếu
  /// đẩy không được, để chủ sổ biết thành viên đang xem dữ liệu cũ.
  Future<bool> publish(int groupId) async {
    try {
      final id = await ledgerIdOf(groupId);
      if (id == null) return true;
      final group = await GroupRepository(_local!).getById(groupId);
      if (group == null) return true;
      await _ledgers.doc(id).update({
        'name': group.name,
        'type': group.type,
        'ownerName': _myName,
        'snapshot': await _snapshot(groupId),
        'updatedAt': FieldValue.serverTimestamp(),
      }).timeout(_timeout);
      return true;
    } catch (e) {
      debugPrint('Không đồng bộ được sổ chung: $e');
      return false;
    }
  }

  /// Đổi tên hiển thị của mình ở mọi sổ chung đang tham gia, để chủ sổ và
  /// người khác thấy tên mới. Lỗi mạng thì bỏ qua.
  Future<void> renameMe(String name) async {
    final me = uid;
    if (me == null || name.isEmpty) return;
    try {
      final q = await _ledgers
          .where('memberUids', arrayContains: me)
          .get()
          .timeout(_timeout);
      for (final d in q.docs) {
        await d.reference.update({
          'linkNames.$me': name,
          if (d.data()['ownerUid'] == me) 'ownerName': name,
        }).timeout(_timeout);
      }
    } catch (e) {
      debugPrint('Không đổi được tên ở sổ chung: $e');
    }
  }

  /// Chủ sổ gỡ mọi tài khoản đang đứng tên thành viên [memberId] (khi xóa
  /// thành viên đó khỏi nhóm trên máy).
  Future<void> removeAccountsOfMember(int groupId, int memberId) async {
    final id = await ledgerIdOf(groupId);
    if (id == null) return;
    final ledger = await fetch(id);
    if (ledger == null || !ledger.isOwner(uid ?? '')) return;
    for (final u in ledger.uidsOf(memberId)) {
      if (u != ledger.ownerUid) await removeAccount(id, u);
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
  /// Xóa luôn các mã mời của sổ. Lỗi (không phải mất mạng) thì giữ khóa
  /// trên máy và ném lỗi, để không bỏ rơi một sổ vẫn còn trên Firestore.
  Future<void> unshare(int groupId) async {
    final id = await ledgerIdOf(groupId);
    if (id == null) return;
    try {
      final doc = await _ledgers.doc(id).get().timeout(_timeout);
      final codes = [
        for (final c in (doc.data()?['inviteCodes'] as List?) ?? const []) '$c'
      ];
      final batch = _db.batch();
      for (final c in codes) {
        batch.delete(_invites.doc(c));
      }
      batch.delete(_ledgers.doc(id));
      await batch.commit().timeout(_timeout);
    } on TimeoutException {
      // Mất mạng: lệnh xóa đã vào hàng đợi, sẽ gửi khi có mạng.
    }
    await _settings.set(_key(groupId), null);
  }

  /// Thành viên tự rời sổ: không xem sổ và không nhận nhắc nợ nữa.
  Future<void> leave(String ledgerId) async {
    final me = _requireUid();
    await _ledgers.doc(ledgerId).update({
      'memberUids': FieldValue.arrayRemove([me]),
      'links.$me': FieldValue.delete(),
      'linkNames.$me': FieldValue.delete(),
    }).timeout(_timeout);
    await _cancelScheduled(ledgerId);
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
            // Mã chỉ dùng một lần và hết hạn sau [inviteTtl].
            'expiresAt': Timestamp.fromDate(DateTime.now().add(inviteTtl)),
          });
          // Ghi lại mã vào sổ để khi tắt sổ chung thì xóa được hết mã.
          tx.update(_ledgers.doc(ledger.id), {
            'inviteCodes': FieldValue.arrayUnion([code]),
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
    if (data['usedBy'] != null) {
      throw const FormatException(
          'Mã mời này đã được dùng. Nhờ chủ sổ tạo mã mới cho bạn nhé.');
    }
    final expires = data['expiresAt'];
    if (expires is! Timestamp || expires.toDate().isBefore(DateTime.now())) {
      throw const FormatException(
          'Mã mời đã hết hạn. Nhờ chủ sổ tạo mã mới cho bạn nhé.');
    }
    final ledgerId = data['ledgerId'] as String;
    // Đã ở trong sổ thì không nhập mã khác để đổi sang đứng tên người khác.
    try {
      final current = await fetch(ledgerId);
      if (current != null && current.links.containsKey(me)) {
        throw const FormatException('Bạn đã ở trong sổ này rồi.');
      }
    } on FirebaseException {
      // Chưa là thành viên nên chưa đọc được sổ: bình thường.
    }
    // Vào sổ và đánh dấu mã đã dùng trong cùng một lần ghi: rules kiểm cả
    // hai, mã không dùng lại được (kể cả sau khi chủ sổ gỡ tài khoản).
    final batch = _db.batch()
      ..update(_ledgers.doc(ledgerId), {
        'memberUids': FieldValue.arrayUnion([me]),
        'links.$me': (data['memberId'] as num).toInt(),
        'linkNames.$me': _myName,
        'lastJoinCode': code,
      })
      ..update(_invites.doc(code), {
        'usedBy': me,
        'usedAt': FieldValue.serverTimestamp(),
      });
    await batch.commit().timeout(_timeout);
    return ledgerId;
  }

  /// Chủ sổ gỡ một tài khoản khỏi sổ (vd. ai đó nhập nhầm mã).
  /// Mất mạng thì lệnh gỡ vào hàng đợi và tự gửi khi có mạng (không báo lỗi).
  Future<void> removeAccount(String ledgerId, String accountUid) async {
    try {
      await _ledgers.doc(ledgerId).update({
        'memberUids': FieldValue.arrayRemove([accountUid]),
        'links.$accountUid': FieldValue.delete(),
        'linkNames.$accountUid': FieldValue.delete(),
      }).timeout(_timeout);
    } on TimeoutException {
      debugPrint('Gỡ tài khoản sẽ gửi khi có mạng');
    }
  }

  /// Chủ sổ gửi nhắc nợ tới tài khoản [toUid]. Trả về true nếu đã gửi,
  /// false nếu đang mất mạng (lời nhắc tự gửi khi có mạng).
  Future<bool> remind({
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
    // Tạo id trước rồi set: mất mạng thì lệnh ghi nằm trong hàng đợi và tự
    // gửi khi có mạng. Trả về false (đang chờ mạng) thay vì báo lỗi, để
    // người dùng không bấm gửi lại thành 2 lời nhắc.
    final ref = _notices.doc();
    try {
      await ref.set({
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
    } on TimeoutException {
      return false;
    }
    return true;
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
    _watchPaidOff(me);
    _inbox = _notices
        .where('toUid', isEqualTo: me)
        .where('delivered', isEqualTo: false)
        .snapshots()
        .listen((q) async {
      final added = [
        for (final change in q.docChanges)
          if (change.type == DocumentChangeType.added) change.doc,
      ];
      // Mở app sau nhiều ngày: nhiều lời nhắc đã tới hạn cùng lúc. Mỗi sổ
      // chỉ hiện lời nhắc mới nhất, các cái cũ hơn chỉ đánh dấu đã nhận.
      final now = DateTime.now();
      final newestDue = <String, String>{};
      DateTime when(DocumentSnapshot<Map<String, dynamic>> d) =>
          (d.data()?['deliverAt'] as Timestamp?)?.toDate() ??
          (d.data()?['createdAt'] as Timestamp?)?.toDate() ??
          now;
      for (final d in added) {
        final at = (d.data()?['deliverAt'] as Timestamp?)?.toDate();
        if (at != null && at.isAfter(now)) continue;
        final ledgerId = d.data()?['ledgerId'] as String? ?? '';
        final cur = newestDue[ledgerId];
        final curDoc = cur == null ? null : added.firstWhere((x) => x.id == cur);
        if (curDoc == null || when(d).isAfter(when(curDoc))) {
          newestDue[ledgerId] = d.id;
        }
      }
      final shown = newestDue.values.toSet();
      for (final doc in added) {
        final n = LedgerNotice.fromDoc(doc);
        // Phòng hờ: chỉ hiện lời nhắc gửi cho đúng mình, không phải mình gửi.
        final data = doc.data() ?? const {};
        if (data['toUid'] != me || data['fromUid'] == me) continue;
        final deliverAt = (data['deliverAt'] as Timestamp?)?.toDate();
        try {
          final id = n.id.hashCode & 0x7fffffff;
          final title = '${n.fromName} nhắc nợ · ${n.ledgerName}';
          if (deliverAt != null && deliverAt.isAfter(now)) {
            // Lời nhắc hẹn giờ: đặt lịch ngay trên máy người nợ.
            await NotificationService.schedule(
                at: deliverAt, title: title, body: n.message, id: id);
            await _trackScheduled(n.ledgerId, id);
          } else if (shown.contains(doc.id)) {
            await NotificationService.show(
                id: id, title: title, body: n.message);
          }
          await doc.reference.update({
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
    await _paidWatch?.cancel();
    _paidWatch = null;
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _paidWatch;

  String _schedKey(String ledgerId) => 'reminders_${uid}_$ledgerId';

  Future<List<int>> _scheduledIds(String ledgerId) async {
    if (_local == null) return const [];
    final raw = await _settings.get(_schedKey(ledgerId));
    if (raw == null || raw.isEmpty) return const [];
    return [for (final p in raw.split(',')) ?int.tryParse(p)];
  }

  /// Nhớ id thông báo đã hẹn giờ của sổ [ledgerId], để hủy khi trả xong nợ.
  Future<void> _trackScheduled(String ledgerId, int id) async {
    if (_local == null) return;
    final ids = {...await _scheduledIds(ledgerId), id};
    await _settings.set(_schedKey(ledgerId), ids.join(','));
  }

  Future<void> _cancelScheduled(String ledgerId) async {
    final ids = await _scheduledIds(ledgerId);
    if (ids.isEmpty) return;
    for (final id in ids) {
      try {
        await NotificationService.cancel(id);
      } catch (e) {
        debugPrint('Không hủy được nhắc nợ #$id: $e');
      }
    }
    await _settings.set(_schedKey(ledgerId), null);
  }

  /// Theo dõi các sổ mình được mời: hết nợ chủ sổ (chủ sổ đã ghi nhận trả)
  /// hoặc bị gỡ khỏi sổ thì hủy các lời nhắc đã hẹn giờ trên máy, để không
  /// còn báo "Bạn đang nợ..." với số tiền cũ.
  void _watchPaidOff(String me) {
    _paidWatch?.cancel();
    _paidWatch = _ledgers
        .where('memberUids', arrayContains: me)
        .snapshots()
        .listen((q) async {
      for (final change in q.docChanges) {
        final ledgerId = change.doc.id;
        if (change.type == DocumentChangeType.removed) {
          await _cancelScheduled(ledgerId);
          continue;
        }
        final l = SharedLedger.fromDoc(change.doc);
        if (l.isOwner(me)) continue;
        final mine = l.memberIdOf(me);
        final owes = l.data.transfers
            .any((t) => t.fromId == mine && t.toId == l.ownerMemberId);
        if (!owes) await _cancelScheduled(ledgerId);
      }
    }, onError: (Object e) => debugPrint('paid watch: $e'));
  }
}

class _CodeTaken implements Exception {
  const _CodeTaken();
}
