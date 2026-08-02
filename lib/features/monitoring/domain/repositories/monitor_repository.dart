import 'package:site_signal/core/theme/app_accent_color.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';

class PersistedMonitorState {
  const PersistedMonitorState({
    required this.sites,
    required this.paused,
    this.themePreference = AppThemePreference.system,
    this.primaryColorValue = AppAccentColor.defaultValue,
    this.notificationSoundPreference = NotificationSoundPreference.siteSignal,
  });

  final List<SiteMonitor> sites;
  final bool paused;
  final AppThemePreference themePreference;
  final int primaryColorValue;
  final NotificationSoundPreference notificationSoundPreference;
}

class PersistedMonitorPreferences {
  const PersistedMonitorPreferences({
    required this.paused,
    required this.themePreference,
    required this.primaryColorValue,
    required this.notificationSoundPreference,
  });

  final bool paused;
  final AppThemePreference themePreference;
  final int primaryColorValue;
  final NotificationSoundPreference notificationSoundPreference;
}

extension PersistedMonitorPreferencesView on PersistedMonitorState {
  PersistedMonitorPreferences get preferences => PersistedMonitorPreferences(
    paused: paused,
    themePreference: themePreference,
    primaryColorValue: primaryColorValue,
    notificationSoundPreference: notificationSoundPreference,
  );

  PersistedMonitorState withPreferences(PersistedMonitorPreferences value) {
    return PersistedMonitorState(
      sites: sites,
      paused: value.paused,
      themePreference: value.themePreference,
      primaryColorValue: value.primaryColorValue,
      notificationSoundPreference: value.notificationSoundPreference,
    );
  }
}

abstract interface class MonitorRepository {
  Future<PersistedMonitorState> load();

  Future<void> save(PersistedMonitorState state);

  Future<void> savePreferences(PersistedMonitorPreferences preferences);

  Future<void> close();
}
