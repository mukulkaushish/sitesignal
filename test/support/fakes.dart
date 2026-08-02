import 'dart:async';

import 'package:site_signal/core/theme/app_accent_color.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/repositories/monitor_repository.dart';
import 'package:site_signal/features/monitoring/domain/services/background_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/desktop_bridge.dart';
import 'package:site_signal/features/monitoring/domain/services/favicon_resolver.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';

class MemoryMonitorRepository implements MonitorRepository {
  MemoryMonitorRepository({
    List<SiteMonitor> sites = const <SiteMonitor>[],
    bool paused = false,
    AppThemePreference themePreference = AppThemePreference.system,
    int primaryColorValue = AppAccentColor.defaultValue,
    NotificationSoundPreference notificationSoundPreference =
        NotificationSoundPreference.siteSignal,
  }) : state = PersistedMonitorState(
         sites: sites,
         paused: paused,
         themePreference: themePreference,
         primaryColorValue: primaryColorValue,
         notificationSoundPreference: notificationSoundPreference,
       );

  PersistedMonitorState state;
  int fullSaveCount = 0;
  int preferenceSaveCount = 0;

  @override
  Future<PersistedMonitorState> load() async => state;

  @override
  Future<void> save(PersistedMonitorState state) async {
    fullSaveCount += 1;
    this.state = state;
  }

  @override
  Future<void> savePreferences(PersistedMonitorPreferences preferences) async {
    preferenceSaveCount += 1;
    state = state.withPreferences(preferences);
  }

  @override
  Future<void> close() async {}
}

class ScriptedHealthChecker implements HealthChecker {
  ScriptedHealthChecker({List<HealthCheckResult>? results})
    : _results = List<HealthCheckResult>.of(results ?? <HealthCheckResult>[]);

  final List<HealthCheckResult> _results;
  bool closed = false;
  int checkCount = 0;

  @override
  Future<HealthCheckResult> check(Uri baseUri, {Uri? preferredProbe}) async {
    checkCount += 1;
    if (_results.isNotEmpty) {
      return _results.removeAt(0);
    }
    return HealthCheckResult(
      status: HealthStatus.up,
      checkedAt: DateTime.now().toUtc(),
      responseTimeMs: 12,
      statusCode: 200,
      error: null,
      checkedUrl: preferredProbe?.toString() ?? baseUri.toString(),
    );
  }

  @override
  void close() {
    closed = true;
  }
}

class FakeInternetConnectivityChecker implements InternetConnectivityChecker {
  FakeInternetConnectivityChecker({
    List<ConnectivityAssessment>? assessments,
    this.changes = const Stream<void>.empty(),
  }) : _assessments = List<ConnectivityAssessment>.of(
         assessments ?? <ConnectivityAssessment>[_onlineAssessment()],
       );

  final List<ConnectivityAssessment> _assessments;
  int assessmentCount = 0;
  bool closed = false;

  @override
  final Stream<void> changes;

  @override
  Future<ConnectivityAssessment> assess() async {
    assessmentCount += 1;
    if (_assessments.length > 1) {
      return _assessments.removeAt(0);
    }
    return _assessments.single;
  }

  @override
  void close() {
    closed = true;
  }
}

ConnectivityAssessment _onlineAssessment() => ConnectivityAssessment(
  availability: InternetAvailability.online,
  issue: ConnectivityIssue.none,
  transports: const <NetworkTransport>[NetworkTransport.wifi],
  checkedAt: DateTime.now().toUtc(),
);

class FakeFaviconResolver implements FaviconResolver {
  FakeFaviconResolver({this.result});

  final Uri? result;
  final List<Uri> requestedOrigins = <Uri>[];
  bool closed = false;

  @override
  Future<Uri?> resolve(Uri baseUri) async {
    requestedOrigins.add(baseUri);
    return result;
  }

  @override
  void close() {
    closed = true;
  }
}

class FakeDesktopBridge implements DesktopBridge {
  Future<void> Function()? onCheckAll;
  Future<void> Function()? onTogglePaused;
  Future<void> Function()? onQuitRequested;
  final List<NotificationMessage> notifications = <NotificationMessage>[];
  final List<NotificationSoundPreference> soundPreviews =
      <NotificationSoundPreference>[];
  final List<MenuUpdate> menuUpdates = <MenuUpdate>[];
  final List<String> openedUrls = <String>[];
  NotificationPermission permission = NotificationPermission.authorized;
  Completer<NotificationPermission>? permissionRequestCompleter;
  Completer<void>? notificationDeliveryCompleter;
  int permissionCheckCount = 0;
  int permissionRequestCount = 0;
  bool launchAtStartupSupported = true;
  bool launchAtStartup = false;
  int launchAtStartupUpdateCount = 0;
  bool systemNotificationSoundPreviewSupported = true;
  bool disposed = false;

  @override
  bool get supportsSystemNotificationSoundPreview =>
      systemNotificationSoundPreviewSupported;

  @override
  Future<void> initialize({
    required Future<void> Function() onCheckAll,
    required Future<void> Function() onTogglePaused,
    required Future<void> Function() onQuitRequested,
  }) async {
    this.onCheckAll = onCheckAll;
    this.onTogglePaused = onTogglePaused;
    this.onQuitRequested = onQuitRequested;
  }

  @override
  Future<NotificationPermission> notificationPermission() async {
    permissionCheckCount += 1;
    return permission;
  }

  @override
  Future<bool?> launchAtStartupEnabled() async {
    return launchAtStartupSupported ? launchAtStartup : null;
  }

  @override
  Future<void> openUrl(String url) async {
    openedUrls.add(url);
  }

  @override
  Future<bool> openNotificationSettings() async => true;

  @override
  Future<NotificationPermission> requestNotificationPermission() async {
    permissionRequestCount += 1;
    final pending = permissionRequestCompleter;
    permission = pending == null
        ? NotificationPermission.authorized
        : await pending.future;
    return permission;
  }

  @override
  Future<void> playNotificationSoundPreview(
    NotificationSoundPreference soundPreference,
  ) async {
    soundPreviews.add(soundPreference);
  }

  @override
  Future<void> showNotification({
    required String notificationKey,
    required String title,
    required String body,
    required NotificationSoundPreference soundPreference,
    bool suppressSound = false,
  }) async {
    final pending = notificationDeliveryCompleter;
    if (pending != null) {
      await pending.future;
    }
    notifications.add(
      NotificationMessage(
        notificationKey: notificationKey,
        title: title,
        body: body,
        soundPreference: soundPreference,
        suppressSound: suppressSound,
      ),
    );
  }

  @override
  Future<bool> setLaunchAtStartupEnabled(bool enabled) async {
    launchAtStartupUpdateCount += 1;
    launchAtStartup = enabled;
    return launchAtStartup;
  }

  @override
  Future<void> updateMenu({
    required List<SiteMonitor> sites,
    required bool paused,
  }) async {
    menuUpdates.add(MenuUpdate(sites: sites, paused: paused));
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class FakeBackgroundMonitor implements BackgroundMonitor {
  FakeBackgroundMonitor({this.ownsAutomaticChecks = true});

  @override
  final bool ownsAutomaticChecks;
  BackgroundSnapshotCallback? onSnapshot;
  int synchronizationCount = 0;
  bool disposed = false;

  @override
  BackgroundMonitoringMode get mode => BackgroundMonitoringMode.continuous;

  @override
  Future<void> initialize({
    required BackgroundSnapshotCallback onSnapshot,
  }) async {
    this.onSnapshot = onSnapshot;
  }

  @override
  Future<BackgroundMonitorSnapshot?> loadLatestSnapshot() async => null;

  @override
  Future<BackgroundMonitoringStatus> refreshStatus() async =>
      BackgroundMonitoringStatus(mode: mode, isRunning: ownsAutomaticChecks);

  @override
  Future<BackgroundMonitoringStatus> synchronize(
    BackgroundMonitorSnapshot snapshot,
  ) async {
    synchronizationCount += 1;
    return BackgroundMonitoringStatus(
      mode: mode,
      isRunning: ownsAutomaticChecks,
    );
  }

  @override
  void dispose() {
    disposed = true;
  }
}

class NotificationMessage {
  const NotificationMessage({
    required this.notificationKey,
    required this.title,
    required this.body,
    required this.soundPreference,
    this.suppressSound = false,
  });

  final String notificationKey;
  final String title;
  final String body;
  final NotificationSoundPreference soundPreference;
  final bool suppressSound;
}

class MenuUpdate {
  const MenuUpdate({required this.sites, required this.paused});

  final List<SiteMonitor> sites;
  final bool paused;
}
