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

  const UserProfile({
    required this.uid,
    required this.displayName,
    required this.email,
    this.plan,
    this.createdAt,
    this.lastLoginAt,
    this.loginCount = 0,
    this.lastBackupAt,
  });

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
      );
}
