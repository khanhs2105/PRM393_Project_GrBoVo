import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../data/cloud_backup.dart';
import '../models/user_profile.dart';
import 'avatar_cache.dart';
import 'jwt_verifier.dart';

/// Đăng ký, đăng nhập, đăng xuất bằng Firebase Auth (email + mật khẩu) và
/// lưu hồ sơ người dùng vào Cloud Firestore.
///
/// Cấu trúc Firestore:
///   users/{uid}                  hồ sơ: tên, email, gói, lần đăng nhập...
///   users/{uid}/backups/latest   bản sao lưu dữ liệu nhóm trên máy
/// Chỉ chủ tài khoản đọc/ghi được (xem firestore.rules).
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final verifier = FirebaseJwtVerifier();

  /// Ghi hồ sơ không được làm treo màn hình khi mạng chậm.
  static const _profileTimeout = Duration(seconds: 8);
  static const _backupTimeout = Duration(seconds: 30);

  Stream<User?> authStateChanges() => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  /// Project id của Firebase, cũng là giá trị `aud` trong JWT.
  String get projectId => Firebase.app().options.projectId;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _avatarDoc(String uid) =>
      _db.collection('avatars').doc(uid);

  DocumentReference<Map<String, dynamic>> _backupDoc(String uid) =>
      _userDoc(uid).collection('backups').doc('latest');

  String _requireUid() {
    final u = _auth.currentUser;
    if (u == null) throw StateError('Bạn chưa đăng nhập');
    return u.uid;
  }

  /// Tạo tài khoản mới rồi tạo hồ sơ trong Firestore.
  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? plan,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    final user = cred.user!;
    // Tài khoản đã tạo xong: lỗi mạng khi đặt tên không được làm hỏng cả
    // lần đăng ký (bấm lại sẽ báo "Email đã được đăng ký").
    try {
      await user.updateDisplayName(name.trim());
    } catch (e) {
      debugPrint('Chưa đặt được tên hiển thị: $e');
    }
    await _safe(_userDoc(user.uid).set({
      'uid': user.uid,
      'displayName': name.trim(),
      'email': user.email,
      'plan': plan,
      'provider': 'password',
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
      'loginCount': 1,
    }));
  }

  /// Đăng nhập và cập nhật lần đăng nhập gần nhất. Trả về hồ sơ (nếu đọc được)
  /// để app lấy lại gói đã mua.
  Future<UserProfile?> signIn(
      {required String email, required String password}) async {
    final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    final user = cred.user!;
    await _safe(_userDoc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'lastLoginAt': FieldValue.serverTimestamp(),
      'loginCount': FieldValue.increment(1),
    }, SetOptions(merge: true)));
    try {
      final snap = await _userDoc(user.uid).get().timeout(_profileTimeout);
      final data = snap.data();
      // Ảnh đặt trước khi có bản công khai: chép sang avatars/{uid}.
      final avatar = data?['avatar'];
      if (avatar is String && avatar.isNotEmpty) {
        await _safe(_avatarDoc(user.uid).set({
          'avatar': avatar,
          'updatedAt': FieldValue.serverTimestamp(),
        }));
      }
      return data == null ? null : _profile(user.uid, data);
    } catch (e) {
      debugPrint('Không đọc được hồ sơ: $e');
      return null;
    }
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  /// Hồ sơ của người đang đăng nhập, tự cập nhật khi Firestore thay đổi.
  Stream<UserProfile?> profileChanges() {
    final uid = _requireUid();
    return _userDoc(uid)
        .snapshots()
        .map((s) => s.data() == null ? null : _profile(uid, s.data()!));
  }

  /// Cập nhật tên hiển thị (cả trên Firebase Auth) và số điện thoại.
  Future<void> updateProfile({
    required String name,
    required String? phone,
  }) async {
    final uid = _requireUid();
    await _auth.currentUser!.updateDisplayName(name.trim());
    final p = phone?.trim() ?? '';
    await _userDoc(uid).set({
      'displayName': name.trim(),
      'phone': p.isEmpty ? FieldValue.delete() : p,
    }, SetOptions(merge: true)).timeout(_profileTimeout);
  }

  /// Lưu ảnh đại diện (JPEG đã thu nhỏ). null là xóa ảnh.
  Future<void> updateAvatar(Uint8List? jpeg) async {
    final uid = _requireUid();
    // Rules cho phép chuỗi base64 < 400.000 ký tự, tức ảnh < ~299.000 byte.
    if (jpeg != null && jpeg.length > 290 * 1024) {
      throw StateError('Ảnh quá lớn, chọn ảnh khác nhé.');
    }
    final value = jpeg == null ? FieldValue.delete() : base64Encode(jpeg);
    // Ghi cả bản công khai avatars/{uid} để người cùng sổ chung thấy ảnh.
    final batch = _db.batch()
      ..set(_userDoc(uid), {'avatar': value}, SetOptions(merge: true));
    if (jpeg == null) {
      batch.delete(_avatarDoc(uid));
    } else {
      batch.set(_avatarDoc(uid), {
        'avatar': value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit().timeout(_backupTimeout);
    AvatarCache.put(uid, jpeg);
  }

  /// Đổi mật khẩu. Firebase yêu cầu đăng nhập lại gần đây, nên xác thực lại
  /// bằng mật khẩu hiện tại trước. Sai mật khẩu cũ thì ném
  /// FirebaseAuthException (invalid-credential / wrong-password).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) throw StateError('Bạn chưa đăng nhập');
    final cred =
        EmailAuthProvider.credential(email: email, password: currentPassword);
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }

  /// Lưu gói "troll" vào hồ sơ. Không đăng nhập thì bỏ qua.
  Future<void> savePlan(String plan) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _safe(_userDoc(uid).set({'plan': plan}, SetOptions(merge: true)));
  }

  /// ID token hiện tại (một JWT). [forceRefresh] xin Firebase cấp token mới.
  Future<String?> idToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    return user.getIdToken(forceRefresh);
  }

  Future<JwtCheck> verifyCurrentToken({bool forceRefresh = false}) async {
    final token = await idToken(forceRefresh: forceRefresh);
    if (token == null) throw StateError('Bạn chưa đăng nhập');
    return verifier.verify(token, projectId: projectId);
  }

  /// Đẩy toàn bộ dữ liệu nhóm trên máy lên Firestore (ghi đè bản cũ).
  Future<Map<String, Object?>> backup(Database db) async {
    final uid = _requireUid();
    final snap = await dumpDatabase(db);
    final batch = _db.batch()
      ..set(_backupDoc(uid), {
        ...snap,
        'createdAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      })
      ..set(_userDoc(uid), {'lastBackupAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true));
    await batch.commit().timeout(_backupTimeout);
    return snap;
  }

  /// Bản sao lưu trên Firestore, null nếu chưa có.
  Future<Map<String, dynamic>?> latestBackup() async {
    final uid = _requireUid();
    final doc = await _backupDoc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(_backupTimeout);
    return doc.data();
  }

  /// Ghi đè dữ liệu trên máy bằng bản sao lưu.
  Future<void> restore(Database db, Map<String, dynamic> backup) =>
      restoreDatabase(db, backup);

  static DateTime? toDate(Object? v) => v is Timestamp ? v.toDate() : null;

  UserProfile _profile(String uid, Map<String, dynamic> data) =>
      UserProfile.fromMap(uid, data, toDate: toDate);

  /// Ghi hồ sơ mà không làm hỏng luồng đăng nhập nếu Firestore lỗi/chậm.
  Future<void> _safe(Future<void> write) async {
    try {
      await write.timeout(_profileTimeout);
    } catch (e) {
      debugPrint('Ghi Firestore lỗi: $e');
    }
  }
}
