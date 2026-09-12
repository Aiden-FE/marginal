import 'package:flutter/material.dart';

import '../features/reader/reader_theme.dart';

/// Marginal 视觉语言 —— 移植 v1 mobile.css 的暖纸书卷气质。
abstract final class MarginalColors {
  static const bg = Color(0xFFF5F1E8);
  static const surface = Color(0xFFFFFDF8);
  static const surface2 = Color(0xFFEDE8DD);
  static const ink = Color(0xFF28251F);
  static const muted = Color(0xFF7A746A);
  static const line = Color(0x1C332D23);
  static const accent = Color(0xFFAD7835);
  static const accentSoft = Color(0xFFEAD8BD);
  static const danger = Color(0xFFAD4E43);
  static const ok = Color(0xFF567A51);
  static const nightBg = Color(0xFF171816);
  static const nightSurface = Color(0xFF1F201D);
  static const nightInk = Color(0xFFD1C9B9);

  static ReaderPalette palette(ReaderTheme theme, Brightness brightness) =>
      switch (theme) {
        ReaderTheme.paper => ReaderPalette(
          background: bg,
          foreground: ink,
          chrome: const Color(0xE0F5F1E8),
          accent: accent,
        ),
        ReaderTheme.eyecare => const ReaderPalette(
          background: Color(0xFFCFE3D2),
          foreground: Color(0xFF2F3D33),
          chrome: Color(0xE01F2C22),
          accent: Color(0xFFAD7835),
        ),
        ReaderTheme.dark => ReaderPalette(
          background: nightBg,
          foreground: nightInk,
          chrome: const Color(0xE621221F),
          accent: const Color(0xFFD9A13C),
        ),
      };
}

class ReaderPalette {
  const ReaderPalette({
    required this.background,
    required this.foreground,
    required this.chrome,
    required this.accent,
  });
  final Color background, foreground, chrome, accent;
}

class MarginalTheme {
  static const serif = TextStyle(
    fontFamily: 'Songti SC',
    fontFamilyFallback: ['STSong', 'Noto Serif SC', 'serif'],
  );

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: MarginalColors.accent,
      brightness: brightness,
      surface: isDark ? MarginalColors.nightSurface : MarginalColors.surface,
      surfaceContainerHighest: isDark
          ? MarginalColors.nightSurface
          : MarginalColors.surface2,
    );
    final base = ThemeData.from(colorScheme: colorScheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: isDark
          ? MarginalColors.nightBg
          : MarginalColors.bg,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? MarginalColors.nightSurface
            : MarginalColors.surface,
        foregroundColor: isDark ? MarginalColors.nightInk : MarginalColors.ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: serif.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: isDark ? MarginalColors.nightInk : MarginalColors.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? MarginalColors.nightSurface : MarginalColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: isDark ? Colors.white10 : MarginalColors.line,
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MarginalColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: MarginalColors.accent,
          minimumSize: const Size.fromHeight(44),
          side: BorderSide(
            color: isDark ? Colors.white24 : MarginalColors.line,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? MarginalColors.nightSurface
            : MarginalColors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 13,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white24 : MarginalColors.line,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? Colors.white24 : MarginalColors.line,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: MarginalColors.accent,
            width: 1.4,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? Colors.white12 : MarginalColors.line,
        thickness: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
