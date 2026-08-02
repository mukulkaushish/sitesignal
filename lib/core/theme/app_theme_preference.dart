import 'package:flutter/material.dart';

enum AppThemePreference {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const AppThemePreference(this.themeMode);

  final ThemeMode themeMode;

  static AppThemePreference fromName(String? value) {
    return AppThemePreference.values.firstWhere(
      (preference) => preference.name == value,
      orElse: () => AppThemePreference.system,
    );
  }
}
