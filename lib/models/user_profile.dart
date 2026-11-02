import 'dart:convert';
import 'dart:typed_data';

/// Hồ sơ người dùng lưu ở Firestore: users/{uid}.
class UserProfile {
  final String uid;
  final String displayName;
  final String email;

  /// Tên enum của gói "troll" (conNo, chuNo, doiNoThue).
  final String? plan;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final int loginCount;
  final DateTime? lastBackupAt;

  /// Số điện thoại (không bắt buộc).
  final String? phone;

  /// Ảnh đại diện JPEG nhỏ (256px) mã hóa base64, lưu ngay trong document
  /// Firestore để không cần Firebase Storage (gói Spark miễn phí).
  final String? avatarBase64;

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    this.plan,
    this.createdAt,
    this.lastLoginAt,
    this.loginCount = 0,
    this.lastBackupAt,
    this.phone,
    this.avatarBase64,
  });

  /// Byte ảnh đại diện, null nếu chưa có hoặc dữ liệu hỏng.
  Uint8List? get avatarBytes {
    final b = avatarBase64;
    if (b == null || b.isEmpty) return null;
    try {
      return base64Decode(b);
    } catch (_) {
      return null;
    }
  }

  /// [toDate] đổi Timestamp của Firestore sang DateTime (để model này không
  /// phụ thuộc cloud_firestore và test được).
  factory UserProfile.fromMap(
    String uid,
    Map<String, dynamic> m, {
    required DateTime? Function(Object?) toDate,
  }) =>
      UserProfile(
        uid: uid,
        displayName: (m['displayName'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        plan: m['plan'] as String?,
        createdAt: toDate(m['createdAt']),
        lastLoginAt: toDate(m['lastLoginAt']),
        loginCount: (m['loginCount'] as num?)?.toInt() ?? 0,
        lastBackupAt: toDate(m['lastBackupAt']),
        phone: m['phone'] as String?,
        avatarBase64: m['avatar'] as String?,
      );
}
