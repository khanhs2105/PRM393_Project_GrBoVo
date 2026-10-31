/// Một nhóm chia tiền: đi ăn, phòng trọ, du lịch...
class Group {
  final int? id;
  final String name;

  /// meal | room | trip | other
  final String type;
  final DateTime createdAt;

  const Group({
    this.id,
    required this.name,
    this.type = 'meal',
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'type': type,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Group.fromMap(Map<String, Object?> m) => Group(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: m['type'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  Group copyWith({int? id, String? name, String? type}) => Group(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        createdAt: createdAt,
      );
}
