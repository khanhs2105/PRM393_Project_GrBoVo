/// Một lần trả tiền đã thực hiện: [fromId] đã chuyển cho [toId].
class Settlement {
  final int? id;
  final int groupId;
  final int fromId;
  final int toId;
  final int amount;
  final DateTime paidAt;
  final String? note;

  const Settlement({
    this.id,
    required this.groupId,
    required this.fromId,
    required this.toId,
    required this.amount,
    required this.paidAt,
    this.note,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'group_id': groupId,
        'from_id': fromId,
        'to_id': toId,
        'amount': amount,
        'paid_at': paidAt.millisecondsSinceEpoch,
        'note': note,
      };

  factory Settlement.fromMap(Map<String, Object?> m) => Settlement(
        id: m['id'] as int?,
        groupId: m['group_id'] as int,
        fromId: m['from_id'] as int,
        toId: m['to_id'] as int,
        amount: m['amount'] as int,
        paidAt: DateTime.fromMillisecondsSinceEpoch(m['paid_at'] as int),
        note: m['note'] as String?,
      );
}

/// Một lượt chuyển tiền được gợi ý (chưa trả).
class Transfer {
  final int fromId;
  final int toId;
  final int amount;

  const Transfer(this.fromId, this.toId, this.amount);

  @override
  bool operator ==(Object other) =>
      other is Transfer &&
      other.fromId == fromId &&
      other.toId == toId &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(fromId, toId, amount);

  @override
  String toString() => 'Transfer($fromId -> $toId: $amount)';
}
