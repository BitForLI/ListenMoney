import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seedColor = Color(0xFF686868);

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
    );
    final colorScheme = generatedScheme.copyWith(
      primary: isLight ? const Color(0xFF303134) : const Color(0xFFF1F1F1),
      onPrimary: isLight ? Colors.white : const Color(0xFF202124),
      secondary: isLight ? const Color(0xFF626468) : const Color(0xFFC8C9CC),
      onSecondary: isLight ? Colors.white : const Color(0xFF202124),
      surface: isLight ? const Color(0xFFF7F7F8) : const Color(0xFF232428),
      onSurface: isLight ? const Color(0xFF202124) : const Color(0xFFF4F4F5),
      onSurfaceVariant: isLight
          ? const Color(0xFF5F6368)
          : const Color(0xFFC5C6C9),
      outline: isLight ? const Color(0xFF77797D) : const Color(0xFF9B9DA1),
      outlineVariant: isLight
          ? const Color(0xFFB8BABE)
          : const Color(0xFF414246),
    );
    final pageBackground = isLight
        ? const Color(0xFFD8DDE2)
        : const Color(0xFF1C1D21);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: pageBackground,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: pageBackground,
        foregroundColor: colorScheme.onSurface,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        indicatorColor: Colors.white.withValues(alpha: 0.13),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.18),
            width: 0.7,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 27,
            color: states.contains(WidgetState.selected)
                ? colorScheme.onSurface
                : colorScheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: Colors.transparent,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        thickness: 0.6,
        space: 1,
      ),
    );
  }
}
