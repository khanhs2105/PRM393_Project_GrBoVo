/// Thành viên trong một nhóm. Thông tin ngân hàng dùng để tạo QR nhận tiền.
class Member {
  final int? id;
  final int groupId;
  final String name;

  /// Mã BIN ngân hàng theo NAPAS, ví dụ "970436" (Vietcombank).
  final String? bankBin;
  final String? accountNo;
  final String? accountName;

  const Member({
    this.id,
    required this.groupId,
    required this.name,
    this.bankBin,
    this.accountNo,
    this.accountName,
  });

  /// Đủ thông tin để tạo QR nhận tiền chưa.
  bool get hasBank =>
      (bankBin?.isNotEmpty ?? false) && (accountNo?.isNotEmpty ?? false);

  Map<String, Object?> toMap() => {
        'id': id,
        'group_id': groupId,
        'name': name,
        'bank_bin': bankBin,
        'account_no': accountNo,
        'account_name': accountName,
      };

  factory Member.fromMap(Map<String, Object?> m) => Member(
        id: m['id'] as int?,
        groupId: m['group_id'] as int,
        name: m['name'] as String,
        bankBin: m['bank_bin'] as String?,
        accountNo: m['account_no'] as String?,
        accountName: m['account_name'] as String?,
      );

  Member copyWith({
    int? id,
    int? groupId,
    String? name,
    String? bankBin,
    String? accountNo,
    String? accountName,
  }) =>
      Member(
        id: id ?? this.id,
        groupId: groupId ?? this.groupId,
        name: name ?? this.name,
        bankBin: bankBin ?? this.bankBin,
        accountNo: accountNo ?? this.accountNo,
        accountName: accountName ?? this.accountName,
      );
}
