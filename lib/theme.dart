import 'package:flutter/material.dart';

/// Giao diện "Clean Minimal" (kiểu shadcn/ui): trắng đen, viền mảnh,
/// không đổ bóng, chữ số to. Màu chỉ dùng để báo nợ (đỏ) và được nợ (xanh).
/// Font Be Vietnam Pro, icon Lucide (xem widgets/app_icons.dart).
class AppTheme {
  /// Màu thương hiệu (logo), chỉ dùng làm điểm nhấn nhỏ.
  static const seed = Color(0xFFFF4D6D);
  static const seedEnd = Color(0xFFFF8F3F);
  static const owed = Color(0xFF16A34A); // được nợ
  static const owe = Color(0xFFDC2626); // đang nợ

  static const font = 'BeVietnamPro';

  // Bảng màu xám "zinc".
  static const ink = Color(0xFF09090B);
  static const zinc50 = Color(0xFFFAFAFA);
  static const zinc100 = Color(0xFFF4F4F5);
  static const zinc200 = Color(0xFFE4E4E7);
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc800 = Color(0xFF27272A);
  static const zinc900 = Color(0xFF18181B);

  /// Gradient logo, dùng cho các điểm nhấn thương hiệu.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [seed, seedEnd],
  );

  static List<BoxShadow> brandShadow({double alpha = 0.35}) => [
        BoxShadow(
          color: seed.withValues(alpha: alpha),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  /// Bóng rất nhẹ, dùng cho tab đang chọn.
  static const softShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final light = brightness == Brightness.light;
    final bg = light ? zinc50 : ink;
    final card = light ? Colors.white : zinc900;
    final border = light ? zinc200 : zinc800;
    final fg = light ? ink : zinc50;
    final muted = light ? zinc500 : zinc400;
    final subtle = light ? zinc100 : zinc800;

    final scheme = ColorScheme.fromSeed(
      seedColor: ink,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    ).copyWith(
      primary: fg,
      onPrimary: bg,
      primaryContainer: subtle,
      onPrimaryContainer: fg,
      secondary: fg,
      onSecondary: bg,
      secondaryContainer: subtle,
      onSecondaryContainer: fg,
      tertiary: seed,
      surface: card,
      onSurface: fg,
      onSurfaceVariant: muted,
      surfaceContainerLowest: card,
      surfaceContainerLow: card,
      surfaceContainer: subtle,
      surfaceContainerHigh: subtle,
      surfaceContainerHighest: subtle,
      outline: light ? zinc400 : zinc500,
      outlineVariant: border,
      error: owe,
    );

    final radius = BorderRadius.circular(16);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: border),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: font,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: border,
      textTheme: base.textTheme.apply(bodyColor: fg, displayColor: fg),
      iconTheme: IconThemeData(color: fg, size: 22),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: fg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: fg, size: 22),
        actionsIconTheme: IconThemeData(color: fg, size: 22),
        titleTextStyle: TextStyle(
          fontFamily: font,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: fg,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
            borderSide: BorderSide(color: fg, width: 1.5)),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted),
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: fg,
          foregroundColor: bg,
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
              fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: fg,
          textStyle: const TextStyle(
              fontFamily: font, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: fg,
        foregroundColor: bg,
        elevation: 2,
        highlightElevation: 4,
        extendedTextStyle: const TextStyle(
            fontFamily: font, fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: subtle,
        elevation: 0,
        height: 66,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: font,
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected) ? fg : muted,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 22,
              color: states.contains(WidgetState.selected) ? fg : muted,
            )),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: subtle,
        side: BorderSide(color: border),
        labelStyle: TextStyle(fontFamily: font, color: fg, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: muted,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: light ? ink : zinc50,
        contentTextStyle: TextStyle(fontFamily: font, color: bg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(
            fontFamily: font, fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
            fontFamily: font, fontSize: 13, fontWeight: FontWeight.w500),
        indicator: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(10),
          boxShadow: softShadow,
        ),
        labelColor: fg,
        unselectedLabelColor: muted,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: fg),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? bg : (light ? zinc400 : zinc500)),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? fg : subtle),
      ),
    );
  }
}
