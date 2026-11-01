import 'package:flutter/material.dart';

/// Giao diện "Coral Pop": màu hồng cam theo logo Chipin, nền sáng ấm,
/// thẻ trắng bo góc lớn có bóng mềm, thẻ tổng dạng gradient.
class AppTheme {
  static const seed = Color(0xFFFF4D6D);
  static const seedEnd = Color(0xFFFF8F3F);
  static const owed = Color(0xFF16946A); // được nợ
  static const owe = Color(0xFFD7354F); // đang nợ

  /// Gradient thương hiệu (giống logo), dùng cho thẻ tổng và nút nổi bật.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [seed, seedEnd],
  );

  /// Bóng đổ màu hồng nhạt dưới các khối gradient.
  static List<BoxShadow> brandShadow({double alpha = 0.35}) => [
        BoxShadow(
          color: seed.withValues(alpha: alpha),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final light = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      // Giữ màu primary sát màu logo thay vì bị làm nhạt.
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final radius = BorderRadius.circular(20);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          light ? const Color(0xFFFFF7F5) : const Color(0xFF1A1416),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: light ? 3 : 0,
        margin: EdgeInsets.zero,
        color: light ? Colors.white : const Color(0xFF261E21),
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0xFF78283C).withValues(alpha: 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: light
              ? BorderSide.none
              : BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: light
            ? Colors.white
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: light ? 0.6 : 0.3)),
        ),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        highlightElevation: 6,
        extendedTextStyle:
            const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        indicator: BoxDecoration(
          gradient: brandGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: brandShadow(alpha: 0.25),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: scheme.onSurfaceVariant,
      ),
    );
  }
}
