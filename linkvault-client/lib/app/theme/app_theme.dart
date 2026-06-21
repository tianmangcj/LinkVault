import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const _brand = Color(0xFF136F63);
  static const _secondary = Color(0xFF325A82);
  static const _tertiary = Color(0xFF8D6318);
  static const _lightBackground = Color(0xFFF4F7FA);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightSurfaceSoft = Color(0xFFEAF0F5);
  static const _lightLine = Color(0xFFD8E2EA);
  static const _lightInk = Color(0xFF17212A);
  static const _lightMuted = Color(0xFF637280);
  static const _darkBackground = Color(0xFF0E1317);
  static const _darkSurface = Color(0xFF151B20);
  static const _darkSurfaceSoft = Color(0xFF1D252B);
  static const _darkLine = Color(0xFF2C3940);
  static const _darkInk = Color(0xFFE6EEF2);
  static const _darkMuted = Color(0xFF9BA9B2);
  static List<String> get _fontFallback {
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => const [
        'Microsoft YaHei',
        'Segoe UI',
        'Arial',
      ],
      TargetPlatform.macOS || TargetPlatform.iOS => const [
        'PingFang SC',
        'Hiragino Sans GB',
        'Helvetica Neue',
        'Arial',
      ],
      TargetPlatform.android => const [
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Roboto',
        'Droid Sans Fallback',
      ],
      TargetPlatform.linux => const [
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Ubuntu',
        'Cantarell',
        'DejaVu Sans',
        'Arial',
      ],
      TargetPlatform.fuchsia => const [
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Roboto',
      ],
    };
  }

  static List<String> get platformFontFallback => _fontFallback;

  static TextStyle withPlatformFont(TextStyle style) {
    return style.copyWith(fontFamilyFallback: platformFontFallback);
  }

  static TextStyle _textStyle({
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      fontFamilyFallback: _fontFallback,
    );
  }

  static TextStyle? _withFont(TextStyle? style) {
    return style?.copyWith(fontFamilyFallback: _fontFallback);
  }

  static TextTheme _withFontTextTheme(TextTheme theme) {
    return theme.copyWith(
      displayLarge: _withFont(theme.displayLarge),
      displayMedium: _withFont(theme.displayMedium),
      displaySmall: _withFont(theme.displaySmall),
      headlineLarge: _withFont(theme.headlineLarge),
      headlineMedium: _withFont(theme.headlineMedium),
      headlineSmall: _withFont(theme.headlineSmall),
      titleLarge: _withFont(theme.titleLarge),
      titleMedium: _withFont(theme.titleMedium),
      titleSmall: _withFont(theme.titleSmall),
      bodyLarge: _withFont(theme.bodyLarge),
      bodyMedium: _withFont(theme.bodyMedium),
      bodySmall: _withFont(theme.bodySmall),
      labelLarge: _withFont(theme.labelLarge),
      labelMedium: _withFont(theme.labelMedium),
      labelSmall: _withFont(theme.labelSmall),
    );
  }

  static ThemeData light() {
    return _build(
      brightness: Brightness.light,
      background: _lightBackground,
      surface: _lightSurface,
      surfaceSoft: _lightSurfaceSoft,
      line: _lightLine,
      ink: _lightInk,
      muted: _lightMuted,
    );
  }

  static ThemeData dark() {
    return _build(
      brightness: Brightness.dark,
      background: _darkBackground,
      surface: _darkSurface,
      surfaceSoft: _darkSurfaceSoft,
      line: _darkLine,
      ink: _darkInk,
      muted: _darkMuted,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceSoft,
    required Color line,
    required Color ink,
    required Color muted,
  }) {
    final isDark = brightness == Brightness.dark;
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final scaledTextTheme = _withFontTextTheme(
      _scaleTextTheme(base.textTheme, 1.06),
    );
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: _brand,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFF64D8CB) : _brand,
          onPrimary: isDark ? const Color(0xFF003733) : Colors.white,
          primaryContainer: isDark
              ? const Color(0xFF004F49)
              : const Color(0xFFCDEDEA),
          onPrimaryContainer: isDark
              ? const Color(0xFFB7FFF5)
              : const Color(0xFF00201D),
          secondary: isDark ? const Color(0xFFA5C9F3) : _secondary,
          onSecondary: isDark ? const Color(0xFF08304F) : Colors.white,
          secondaryContainer: isDark
              ? const Color(0xFF174867)
              : const Color(0xFFD1E5FF),
          onSecondaryContainer: isDark
              ? const Color(0xFFD1E5FF)
              : const Color(0xFF001D34),
          tertiary: isDark ? const Color(0xFFFFC96F) : _tertiary,
          onTertiary: isDark ? const Color(0xFF4A2D00) : Colors.white,
          tertiaryContainer: isDark
              ? const Color(0xFF684300)
              : const Color(0xFFFFDEA6),
          onTertiaryContainer: isDark
              ? const Color(0xFFFFDEA6)
              : const Color(0xFF2B1700),
          error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
          onError: isDark ? const Color(0xFF690005) : Colors.white,
          surface: surface,
          onSurface: ink,
          surfaceContainerLowest: isDark
              ? const Color(0xFF0C1012)
              : Colors.white,
          surfaceContainerLow: isDark
              ? const Color(0xFF141A1D)
              : const Color(0xFFFDFEFF),
          surfaceContainer: isDark
              ? const Color(0xFF1A2125)
              : const Color(0xFFF0F4F7),
          surfaceContainerHigh: isDark ? const Color(0xFF20292D) : surfaceSoft,
          surfaceContainerHighest: surfaceSoft,
          outline: line,
          outlineVariant: line,
          onSurfaceVariant: muted,
          shadow: Colors.black,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamilyFallback: _fontFallback,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.standard,
      textTheme: scaledTextTheme.copyWith(
        headlineMedium: scaledTextTheme.headlineMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w800,
          height: 1.16,
          letterSpacing: 0,
        ),
        headlineSmall: scaledTextTheme.headlineSmall?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
          height: 1.2,
          letterSpacing: 0,
        ),
        titleLarge: scaledTextTheme.titleLarge?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
          height: 1.22,
          letterSpacing: 0,
        ),
        titleMedium: scaledTextTheme.titleMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
          height: 1.28,
          letterSpacing: 0,
        ),
        titleSmall: scaledTextTheme.titleSmall?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
          height: 1.32,
          letterSpacing: 0,
        ),
        bodyLarge: scaledTextTheme.bodyLarge?.copyWith(
          color: ink,
          height: 1.45,
          letterSpacing: 0,
        ),
        bodyMedium: scaledTextTheme.bodyMedium?.copyWith(
          color: muted,
          height: 1.45,
          letterSpacing: 0,
        ),
        bodySmall: scaledTextTheme.bodySmall?.copyWith(
          color: muted,
          height: 1.35,
          letterSpacing: 0,
        ),
        labelLarge: scaledTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        labelMedium: scaledTextTheme.labelMedium?.copyWith(
          color: muted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      primaryTextTheme: _withFontTextTheme(base.primaryTextTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        foregroundColor: ink,
        toolbarHeight: 64,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: line),
        ),
        titleTextStyle: scaledTextTheme.bodyLarge?.copyWith(
          color: ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
        contentTextStyle: scaledTextTheme.bodyLarge?.copyWith(
          color: ink,
          fontSize: 18,
          height: 1.45,
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        prefixIconColor: muted,
        suffixIconColor: muted,
        labelStyle: _textStyle(color: muted, fontWeight: FontWeight.w500),
        hintStyle: _textStyle(color: muted),
        floatingLabelStyle: _textStyle(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: _textStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: surface,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: _textStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          minimumSize: const Size(48, 44),
          textStyle: _textStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: surfaceSoft,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: line),
        ),
      ),
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(16),
        contentTextStyle: scaledTextTheme.bodyMedium?.copyWith(color: ink),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.surfaceContainerHigh,
        contentTextStyle: scaledTextTheme.bodyMedium?.copyWith(color: ink),
        actionTextColor: colorScheme.primary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: line),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceSoft,
        selectedColor: colorScheme.primaryContainer,
        labelStyle: _textStyle(color: ink, fontWeight: FontWeight.w600),
        secondaryLabelStyle: _textStyle(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 46)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: line)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        height: 70,
        elevation: 0,
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? colorScheme.primary : muted,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return _textStyle(
            color: selected ? ink : muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        elevation: 0,
        indicatorColor: colorScheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme: IconThemeData(color: muted),
        selectedLabelTextStyle: _textStyle(
          color: ink,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        unselectedLabelTextStyle: _textStyle(
          color: muted,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: line),
        ),
      ),
    );
  }
}

TextTheme _scaleTextTheme(TextTheme theme, double factor) {
  TextStyle? scale(TextStyle? style) {
    if (style == null) {
      return null;
    }
    final fontSize = style.fontSize;
    return fontSize == null
        ? style
        : style.copyWith(fontSize: fontSize * factor);
  }

  return theme.copyWith(
    displayLarge: scale(theme.displayLarge),
    displayMedium: scale(theme.displayMedium),
    displaySmall: scale(theme.displaySmall),
    headlineLarge: scale(theme.headlineLarge),
    headlineMedium: scale(theme.headlineMedium),
    headlineSmall: scale(theme.headlineSmall),
    titleLarge: scale(theme.titleLarge),
    titleMedium: scale(theme.titleMedium),
    titleSmall: scale(theme.titleSmall),
    bodyLarge: scale(theme.bodyLarge),
    bodyMedium: scale(theme.bodyMedium),
    bodySmall: scale(theme.bodySmall),
    labelLarge: scale(theme.labelLarge),
    labelMedium: scale(theme.labelMedium),
    labelSmall: scale(theme.labelSmall),
  );
}
