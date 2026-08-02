import 'package:flutter/material.dart';

@immutable
final class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.error,
  });

  factory AppSemanticColors.forBrightness(Brightness brightness) {
    return brightness == Brightness.dark
        ? const AppSemanticColors(
            success: Color(0xFF34D399),
            warning: Color(0xFFFBBF24),
            error: Color(0xFFF87171),
          )
        : const AppSemanticColors(
            success: Color(0xFF047857),
            warning: Color(0xFF92400E),
            error: Color(0xFFB91C1C),
          );
  }

  final Color success;
  final Color warning;
  final Color error;

  @override
  AppSemanticColors copyWith({Color? success, Color? warning, Color? error}) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  @override
  AppSemanticColors lerp(
    covariant ThemeExtension<AppSemanticColors>? other,
    double t,
  ) {
    if (other is! AppSemanticColors) {
      return this;
    }
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      error: Color.lerp(error, other.error, t) ?? error,
    );
  }
}

extension AppSemanticTheme on BuildContext {
  AppSemanticColors get semanticColors {
    final theme = Theme.of(this);
    return theme.extension<AppSemanticColors>() ??
        AppSemanticColors.forBrightness(theme.brightness);
  }
}
