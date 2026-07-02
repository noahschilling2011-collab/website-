import 'package:flutter/material.dart';
import 'tokens.dart';

/// Material 3 theme pair with iOS-style page transitions on Apple platforms.
abstract final class NexusTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: NexusTokens.primary,
      brightness: brightness,
      surface: isDark ? NexusTokens.surfaceDark : NexusTokens.surfaceLight,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surface,
        scrolledUnderElevation: 0.5,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: isDark ? NexusTokens.cardDark : NexusTokens.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NexusTokens.radiusM)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NexusTokens.radiusM)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? NexusTokens.cardDark : NexusTokens.cardLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NexusTokens.radiusM),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NexusTokens.s4,
          vertical: NexusTokens.s3,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? NexusTokens.cardDark : NexusTokens.cardLight,
        indicatorColor: scheme.primaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NexusTokens.radiusS)),
      ),
    );
  }
}
