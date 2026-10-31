/// Một dòng trong lịch sử hoạt động: thêm/sửa/xóa khoản chi, trả tiền...
/// Không có khóa ngoại tới nhóm để vẫn giữ được dòng "Đã xóa nhóm".
class Activity {
  final int? id;
  final int? groupId;
  final String groupName;

  /// Một trong các hằng của [ActivityKind].
  final String kind;
  final String message;
  final int? amount;
  final DateTime createdAt;

  const Activity({
    this.id,
    this.groupId,
    required this.groupName,
    required this.kind,
    required this.message,
    this.amount,
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'group_id': groupId,
        'group_name': groupName,
        'kind': kind,
        'message': message,
        'amount': amount,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Activity.fromMap(Map<String, Object?> m) => Activity(
        id: m['id'] as int?,
        groupId: m['group_id'] as int?,
        groupName: m['group_name'] as String,
        kind: m['kind'] as String,
        message: m['message'] as String,
        amount: m['amount'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}

class ActivityKind {
  static const expenseAdded = 'expense_added';
  static const expenseEdited = 'expense_edited';
  static const expenseDeleted = 'expense_deleted';
  static const settled = 'settled';
  static const settleUndone = 'settle_undone';
  static const memberAdded = 'member_added';
  static const memberEdited = 'member_edited';
  static const memberDeleted = 'member_deleted';
  static const groupCreated = 'group_created';
  static const groupEdited = 'group_edited';
  static const groupDeleted = 'group_deleted';
}
