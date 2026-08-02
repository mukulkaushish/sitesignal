import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';

enum NotificationPermission {
  unsupported,
  notDetermined,
  denied,
  authorized,
  provisional,
}

abstract interface class DesktopBridge {
  Future<void> initialize({
    required Future<void> Function() onCheckAll,
    required Future<void> Function() onTogglePaused,
    required Future<void> Function() onQuitRequested,
  });

  Future<void> updateMenu({
    required List<SiteMonitor> sites,
    required bool paused,
  });

  Future<NotificationPermission> notificationPermission();

  Future<NotificationPermission> requestNotificationPermission();

  Future<bool?> launchAtStartupEnabled();

  Future<bool> setLaunchAtStartupEnabled(bool enabled);

  bool get supportsSystemNotificationSoundPreview;

  Future<void> playNotificationSoundPreview(
    NotificationSoundPreference soundPreference,
  );

  Future<void> showNotification({
    required String notificationKey,
    required String title,
    required String body,
    required NotificationSoundPreference soundPreference,
    bool suppressSound = false,
  });

  Future<void> openUrl(String url);

  Future<bool> openNotificationSettings();

  void dispose();
}
