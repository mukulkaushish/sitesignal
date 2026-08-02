import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_signal/core/theme/app_accent_color.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';
import 'package:site_signal/core/theme/app_semantic_colors.dart';

/// SiteSignal's desktop theme, translated from digii-mobile's token system.
///
/// A user-selected accent recolors interactive roles. Neutral chrome stays
/// fixed so cards, inputs, dividers, and dark mode remain calm and predictable.
abstract final class AppTheme {
  static ThemeData build(
    Brightness brightness, {
    Color seed = AppAccentColor.defaultColor,
  }) {
    final colors = _ThemeColors.forBrightness(brightness);
    final isMacOS = defaultTargetPlatform == TargetPlatform.macOS;
    final generatedScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final primary = generatedScheme.primary;
    final onPrimary = generatedScheme.onPrimary;
    final textTheme = _buildTextTheme(
      foreground: colors.onSurface,
      muted: colors.onSurfaceVariant,
    );
    final colorScheme = generatedScheme.copyWith(
      surface: colors.surface,
      onSurface: colors.onSurface,
      surfaceContainerLowest: colors.background,
      surfaceContainerLow: colors.surfaceLow,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.surfaceVariant,
      surfaceContainerHighest: colors.surfaceHighest,
      onSurfaceVariant: colors.onSurfaceVariant,
      error: colors.error,
      onError: Colors.white,
      outline: colors.outline,
      outlineVariant: colors.outline,
      shadow: colors.shadow,
    );
    final hairline = colors.outline.withValues(alpha: 0.55);
    final elevatedSurface = brightness == Brightness.dark
        ? colors.surfaceVariant
        : colors.surface;
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppDimensions.r12),
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimensions.r12),
      borderSide: BorderSide(color: colors.outline),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: <ThemeExtension<dynamic>>[
        AppSemanticColors.forBrightness(brightness),
      ],
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
      shadowColor: colors.shadow,
      dividerColor: hairline,
      disabledColor: colors.onSurface.withValues(alpha: 0.38),
      hintColor: colors.onSurfaceVariant,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: textTheme,
      primaryTextTheme: textTheme.apply(
        bodyColor: onPrimary,
        displayColor: onPrimary,
      ),
      iconTheme: IconThemeData(
        color: colors.onSurfaceVariant,
        size: AppDimensions.iconMd,
      ),
      splashFactory: isMacOS
          ? NoSplash.splashFactory
          : InkSparkle.splashFactory,
      splashColor: isMacOS
          ? Colors.transparent
          : primary.withValues(alpha: 0.12),
      highlightColor: colors.onSurface.withValues(alpha: isMacOS ? 0.08 : 0.10),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shadowColor: colors.shadow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.r12),
          side: BorderSide(color: hairline),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: isMacOS ? 0.5 : 1,
        space: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        hoverColor: colors.surfaceVariant,
        focusColor: colors.surface,
        iconColor: colors.onSurfaceVariant,
        prefixIconColor: colors.onSurfaceVariant,
        suffixIconColor: colors.onSurfaceVariant,
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurfaceVariant,
        ),
        helperStyle: textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(
          color: primary,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.s16,
          vertical: AppDimensions.s12,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.outline.withValues(alpha: 0.6)),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: primary,
            width: AppDimensions.borderThin,
          ),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: colors.error,
            width: AppDimensions.borderThin,
          ),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(
            color: colors.error,
            width: AppDimensions.borderThin,
          ),
        ),
        errorStyle: textTheme.bodySmall?.copyWith(color: colors.error),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, AppDimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.s20),
          textStyle: textTheme.labelLarge,
          shape: controlShape,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(64, AppDimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.s20),
          textStyle: textTheme.labelLarge,
          shape: controlShape,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.onSurface,
          minimumSize: const Size(64, AppDimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppDimensions.s20),
          side: BorderSide(color: colors.outline),
          textStyle: textTheme.labelLarge,
          shape: controlShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(
            AppDimensions.buttonHeight,
            AppDimensions.buttonHeight,
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.onSurface,
          iconSize: AppDimensions.iconMd,
          padding: const EdgeInsets.all(AppDimensions.s10),
          shape: const CircleBorder(),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surface,
        selectedColor: primary.withValues(alpha: 0.12),
        labelStyle: textTheme.labelMedium,
        shape: const StadiumBorder(),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.72)),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.s10,
          vertical: AppDimensions.s4,
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: primary.withValues(alpha: 0.08),
        selectedColor: primary,
        iconColor: colors.onSurfaceVariant,
        textColor: colors.onSurface,
        minTileHeight: AppDimensions.s48,
        minVerticalPadding: AppDimensions.s6,
        horizontalTitleGap: AppDimensions.s8,
        titleTextStyle: textTheme.bodyMedium?.copyWith(
          color: colors.onSurface,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: colors.onSurfaceVariant,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: primary.withValues(alpha: 0.10),
        indicatorShape: const StadiumBorder(),
        height: 64,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? primary : colors.onSurfaceVariant,
            size: AppDimensions.iconMd,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? primary : colors.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: elevatedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: colors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.r20),
          side: BorderSide(color: hairline),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: elevatedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: colors.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.r12),
          side: BorderSide(color: hairline),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: ShapeDecoration(
          color: colors.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.r8),
          ),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: colors.surface),
        waitDuration: const Duration(milliseconds: 500),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    );
  }

  static TextTheme _buildTextTheme({
    required Color foreground,
    required Color muted,
  }) {
    TextStyle style({
      required double size,
      required FontWeight weight,
      required Color color,
      required double height,
      double? letterSpacing,
    }) {
      return TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }

    return TextTheme(
      displayLarge: style(
        size: 30,
        weight: FontWeight.w700,
        color: foreground,
        height: 1.25,
      ),
      displayMedium: style(
        size: 26,
        weight: FontWeight.w700,
        color: foreground,
        height: 1.25,
      ),
      displaySmall: style(
        size: 23,
        weight: FontWeight.w700,
        color: foreground,
        height: 1.3,
      ),
      headlineLarge: style(
        size: 21,
        weight: FontWeight.w700,
        color: foreground,
        height: 1.3,
      ),
      headlineMedium: style(
        size: 19,
        weight: FontWeight.w600,
        color: foreground,
        height: 1.35,
      ),
      headlineSmall: style(
        size: 17,
        weight: FontWeight.w600,
        color: foreground,
        height: 1.4,
      ),
      titleLarge: style(
        size: 16,
        weight: FontWeight.w600,
        color: foreground,
        height: 1.4,
      ),
      titleMedium: style(
        size: 15,
        weight: FontWeight.w500,
        color: foreground,
        height: 1.45,
      ),
      titleSmall: style(
        size: 13,
        weight: FontWeight.w500,
        color: foreground,
        height: 1.4,
      ),
      bodyLarge: style(
        size: 15,
        weight: FontWeight.w400,
        color: foreground,
        height: 1.55,
      ),
      bodyMedium: style(
        size: 13,
        weight: FontWeight.w400,
        color: foreground,
        height: 1.55,
      ),
      bodySmall: style(
        size: 11,
        weight: FontWeight.w400,
        color: muted,
        height: 1.45,
      ),
      labelLarge: style(
        size: 14,
        weight: FontWeight.w600,
        color: foreground,
        height: 1.4,
      ),
      labelMedium: style(
        size: 12,
        weight: FontWeight.w500,
        color: foreground,
        height: 1.4,
        letterSpacing: 0.5,
      ),
      labelSmall: style(
        size: 10,
        weight: FontWeight.w500,
        color: muted,
        height: 1.3,
        letterSpacing: 0.5,
      ),
    );
  }
}

final class _ThemeColors {
  const _ThemeColors({
    required this.background,
    required this.surfaceLow,
    required this.surface,
    required this.onSurface,
    required this.surfaceVariant,
    required this.surfaceHighest,
    required this.onSurfaceVariant,
    required this.outline,
    required this.error,
    required this.shadow,
  });

  factory _ThemeColors.forBrightness(Brightness brightness) {
    if (brightness == Brightness.light) {
      return const _ThemeColors(
        background: Color(0xFFFAFAF9),
        surfaceLow: Color(0xFFF7F7F5),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF1C1917),
        surfaceVariant: Color(0xFFF5F5F4),
        surfaceHighest: Color(0xFFEEEDEA),
        onSurfaceVariant: Color(0xFF6B7280),
        outline: Color(0xFFE5E7EB),
        error: Color(0xFFDC2626),
        shadow: Color(0x14000000),
      );
    }
    return const _ThemeColors(
      background: Color(0xFF13161A),
      surfaceLow: Color(0xFF181B20),
      surface: Color(0xFF1E2228),
      onSurface: Color(0xFFF4F6F8),
      surfaceVariant: Color(0xFF262B33),
      surfaceHighest: Color(0xFF303640),
      onSurfaceVariant: Color(0xFFAAB1BC),
      outline: Color(0xFF3A424D),
      error: Color(0xFFFF6B6B),
      shadow: Color(0x52000000),
    );
  }

  final Color background;
  final Color surfaceLow;
  final Color surface;
  final Color onSurface;
  final Color surfaceVariant;
  final Color surfaceHighest;
  final Color onSurfaceVariant;
  final Color outline;
  final Color error;
  final Color shadow;
}
