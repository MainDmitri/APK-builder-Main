import 'package:flutter/material.dart';

/// Brand colors of AppBuilder.
abstract final class AppColors {
  static const violet = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF06B6D4);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFF43F5E);

  static const gradient = LinearGradient(
    colors: [violet, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Pure black (AMOLED) dark theme and a light variant.
abstract final class AppTheme {
  static const _black = ColorScheme(
    brightness: Brightness.dark,
    primary: AppColors.violet,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF2E1065),
    onPrimaryContainer: Color(0xFFEDE9FE),
    secondary: Color(0xFF22D3EE),
    onSecondary: Colors.black,
    secondaryContainer: Color(0xFF083344),
    onSecondaryContainer: Color(0xFFCFFAFE),
    tertiary: Color(0xFFF472B6),
    onTertiary: Colors.black,
    error: AppColors.danger,
    onError: Colors.white,
    errorContainer: Color(0xFF3B0716),
    onErrorContainer: Color(0xFFFFE4E6),
    surface: Colors.black,
    onSurface: Color(0xFFF4F4F5),
    onSurfaceVariant: Color(0xFFA1A1AA),
    outline: Color(0xFF3F3F46),
    outlineVariant: Color(0xFF232329),
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: Color(0xFF09090B),
    surfaceContainer: Color(0xFF0E0E13),
    surfaceContainerHigh: Color(0xFF16161D),
    surfaceContainerHighest: Color(0xFF1F1F27),
    inverseSurface: Color(0xFFF4F4F5),
    onInverseSurface: Colors.black,
    inversePrimary: Color(0xFF6D28D9),
    shadow: Colors.black,
    scrim: Colors.black,
  );

  static ThemeData dark() => _build(_black);

  static ThemeData light() => _build(ColorScheme.fromSeed(seedColor: AppColors.violet));

  static ThemeData _build(ColorScheme scheme) {
    final radius = BorderRadius.circular(16);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.error)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primary.withValues(alpha: 0.25),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primary.withValues(alpha: 0.25),
          selectedForegroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.25),
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primary.withValues(alpha: 0.25),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
