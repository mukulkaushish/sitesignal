import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One user-selected accent drives SiteSignal's interactive color roles while
/// backgrounds, cards, typography, status colors, and dividers stay neutral.
abstract final class AppAccentColor {
  static const int defaultValue = 0xFF2563EB;
  static const Color defaultColor = Color(defaultValue);

  /// Curated colors with enough separation from SiteSignal's light and dark
  /// surfaces to remain useful as controls, icons, and selection indicators.
  static const List<AppAccentPreset> presets = <AppAccentPreset>[
    AppAccentPreset(name: 'SiteSignal blue', color: defaultColor),
    AppAccentPreset(name: 'Teal', color: Color(0xFF177E78)),
    AppAccentPreset(name: 'Cyan', color: Color(0xFF0891B2)),
    AppAccentPreset(name: 'Sky', color: Color(0xFF0284C7)),
    AppAccentPreset(name: 'Emerald', color: Color(0xFF059669)),
    AppAccentPreset(name: 'Sage', color: Color(0xFF4D7C0F)),
    AppAccentPreset(name: 'Copper', color: Color(0xFFC2410C)),
    AppAccentPreset(name: 'Purple', color: Color(0xFF9636E8)),
    AppAccentPreset(name: 'Indigo', color: Color(0xFF6366F1)),
    AppAccentPreset(name: 'Rose', color: Color(0xFFE11D48)),
    AppAccentPreset(name: 'Plum', color: Color(0xFFB832C6)),
    AppAccentPreset(name: 'Slate', color: Color(0xFF64748B)),
  ];

  static int normalizeValue(int value) => 0xFF000000 | (value & 0x00FFFFFF);

  static Color fromValue(int value) => Color(normalizeValue(value));

  static String hex(Color color) => (color.toARGB32() & 0x00FFFFFF)
      .toRadixString(16)
      .padLeft(6, '0')
      .toUpperCase();

  static Color? parseHex(String input) {
    final value = input.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      return null;
    }
    return Color(0xFF000000 | int.parse(value, radix: 16));
  }

  static AppAccentPreset? presetFor(Color color) {
    final value = color.toARGB32();
    for (final preset in presets) {
      if (preset.color.toARGB32() == value) {
        return preset;
      }
    }
    return null;
  }

  /// Accessible foreground for filled accent controls.
  static Color onColor(Color background) {
    final whiteContrast = _contrastRatio(background, _white);
    final inkContrast = _contrastRatio(background, _ink);
    return whiteContrast >= inkContrast ? _white : _ink;
  }

  /// Warn custom-color users when the raw accent is hard to see on either
  /// neutral app surface. Filled controls remain legible via [onColor].
  static bool readableOnBothSurfaces(Color color) {
    return _contrastRatio(color, _lightSurface) >= _minimumUiContrast &&
        _contrastRatio(color, _darkSurface) >= _minimumUiContrast;
  }

  static double _contrastRatio(Color first, Color second) {
    final firstLuminance = first.computeLuminance();
    final secondLuminance = second.computeLuminance();
    final lighter = math.max(firstLuminance, secondLuminance);
    final darker = math.min(firstLuminance, secondLuminance);
    return (lighter + 0.05) / (darker + 0.05);
  }

  static const double _minimumUiContrast = 3;
  static const Color _white = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF1A1A1A);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _darkSurface = Color(0xFF1E2228);
}

final class AppAccentPreset {
  const AppAccentPreset({required this.name, required this.color});

  final String name;
  final Color color;
}
