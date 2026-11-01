import 'package:flutter/material.dart';

import '../logic/categories.dart';
import '../logic/money.dart';
import '../theme.dart';
import 'common.dart';
import 'app_icons.dart';

/// Icon và màu cho từng loại khoản chi.
const categoryStyle = <ExpenseCategory, (IconData, Color)>{
  ExpenseCategory.food: (AppIcons.utensils, Color(0xFFFF8A3D)),
  ExpenseCategory.drink: (AppIcons.coffee, Color(0xFF8D6E63)),
  ExpenseCategory.rent: (AppIcons.house, Color(0xFF5C6BC0)),
  ExpenseCategory.utilities: (AppIcons.zap, Color(0xFFFFB300)),
  ExpenseCategory.transport: (AppIcons.car, Color(0xFF29B6F6)),
  ExpenseCategory.shopping: (AppIcons.shoppingBag, Color(0xFFEC407A)),
  ExpenseCategory.fun: (AppIcons.partyPopper, Color(0xFFAB47BC)),
  ExpenseCategory.other: (AppIcons.receipt, Color(0xFF78909C)),
};

/// Khối nổi bật nền đen (nền xám đậm ở chế độ tối), chữ bên trong màu trắng.
/// Dùng cho phần đầu màn chi tiết nhóm và màn thanh toán.
class GradientPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const GradientPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: Theme.of(context).brightness == Brightness.light
            ? AppTheme.ink
            : AppTheme.zinc800,
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: IconTheme.merge(
          data: const IconThemeData(color: Colors.white),
          child: child,
        ),
      ),
    );
  }
}

/// Ô số liệu nhỏ nền trắng mờ, đặt bên trong [GradientPanel].
class GlassStat extends StatelessWidget {
  final String label;
  final String value;
  const GlassStat({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85), fontSize: 12)),
        ]),
      ),
    );
  }
}

/// "Chào buổi sáng", "Chào buổi chiều"... theo giờ hiện tại.
String greeting([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  if (h < 11) return 'Chào buổi sáng 👋';
  if (h < 14) return 'Chào buổi trưa 👋';
  if (h < 18) return 'Chào buổi chiều 👋';
  return 'Chào buổi tối 👋';
}

/// Ô vuông bo góc có icon, nền nhạt cùng màu.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconTile(this.icon, this.color, {super.key, this.size = 44});

  /// Đoán danh mục từ nội dung.
  factory IconTile.category(String title, {double size = 44}) =>
      IconTile.forCategory(categorize(title), size: size);

  factory IconTile.forCategory(ExpenseCategory c, {double size = 44}) {
    final (icon, color) = categoryStyle[c]!;
    return IconTile(icon, color, size: size);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Các avatar chồng lên nhau, tối đa [max] cái rồi "+n".
class AvatarStack extends StatelessWidget {
  final List<String> names;
  final int max;
  final double radius;
  const AvatarStack(this.names, {super.key, this.max = 4, this.radius = 14});

  @override
  Widget build(BuildContext context) {
    final shown = names.take(max).toList();
    final extra = names.length - shown.length;
    final step = radius * 1.4;
    final count = shown.length + (extra > 0 ? 1 : 0);
    final bg = Theme.of(context).colorScheme.surfaceContainerLowest;
    return SizedBox(
      height: radius * 2 + 4,
      width: count == 0 ? 0.0 : step * (count - 1) + radius * 2 + 4,
      child: Stack(children: [
        for (var i = 0; i < count; i++)
          Positioned(
            left: step * i,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: i < shown.length
                  ? MemberAvatar(shown[i], radius: radius)
                  : CircleAvatar(
                      radius: radius,
                      child: Text('+$extra',
                          style: TextStyle(fontSize: radius * 0.75)),
                    ),
            ),
          ),
      ]),
    );
  }
}

/// Viên thuốc màu cho trạng thái: "Đã xong", "Còn 2 khoản"...
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill(this.text, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Màn trống: icon lớn, tiêu đề, mô tả, nút hành động.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: scheme.primary),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

/// Tiêu đề nhỏ phía trên một nhóm nội dung.
class SectionHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionHeader(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// Số tiền có màu theo dấu: dương xanh, âm đỏ.
class SignedAmount extends StatelessWidget {
  final int amount;
  final double fontSize;
  const SignedAmount(this.amount, {super.key, this.fontSize = 15});

  @override
  Widget build(BuildContext context) {
    final color = amount > 0
        ? AppTheme.owed
        : amount < 0
            ? AppTheme.owe
            : Theme.of(context).colorScheme.onSurfaceVariant;
    return Text(
      '${amount > 0 ? '+' : ''}${formatVnd(amount)}',
      style: TextStyle(
          color: color, fontSize: fontSize, fontWeight: FontWeight.w700),
    );
  }
}

/// "Hôm nay", "Hôm qua", hoặc "Thứ Bảy, 31/10".
String dayLabel(DateTime d, {DateTime? now}) {
  now ??= DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  const weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ Nhật'];
  final date = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  return '${weekdays[d.weekday - 1]}, $date${d.year == now.year ? '' : '/${d.year}'}';
}
