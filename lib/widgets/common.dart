import 'package:flutter/material.dart';

const groupTypes = {
  'meal': ('Đi ăn', Icons.restaurant_rounded),
  'room': ('Phòng trọ', Icons.home_rounded),
  'trip': ('Du lịch', Icons.flight_takeoff_rounded),
  'other': ('Khác', Icons.groups_rounded),
};

String groupTypeLabel(String type) => (groupTypes[type] ?? groupTypes['other']!).$1;
IconData groupTypeIcon(String type) => (groupTypes[type] ?? groupTypes['other']!).$2;

const groupTypeColors = {
  'meal': Color(0xFFFF8A3D),
  'room': Color(0xFF5C6BC0),
  'trip': Color(0xFF29B6F6),
  'other': Color(0xFF78909C),
};

Color groupTypeColor(String type) =>
    groupTypeColors[type] ?? groupTypeColors['other']!;

/// 05/11/2026
String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// 05/11 20:30
String formatDateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Đồng ý'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
      ],
    ),
  );
  return result ?? false;
}

class MemberAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const MemberAvatar(this.name, {super.key, this.radius = 18});

  static const _colors = [
    Colors.teal, Colors.indigo, Colors.orange, Colors.pink,
    Colors.purple, Colors.blue, Colors.brown, Colors.green,
  ];

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final color = _colors[name.hashCode.abs() % _colors.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.shade100,
      foregroundColor: color.shade900,
      child: Text(letter, style: TextStyle(fontSize: radius * 0.9)),
    );
  }
}

/// Màu cho số dư: xanh là được nợ, đỏ là đang nợ.
Color balanceColor(BuildContext context, int v) => v > 0
    ? Colors.green.shade700
    : v < 0
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
