import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:site_signal/core/async/async_pool.dart';
import 'package:site_signal/core/async/serial_task_queue.dart';
import 'package:site_signal/core/theme/app_accent_color.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/incident_notification.dart';
import 'package:site_signal/features/monitoring/domain/entities/incident_notification_key.dart';
import 'package:site_signal/features/monitoring/domain/entities/monitor_fleet_summary.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/repositories/monitor_repository.dart';
import 'package:site_signal/features/monitoring/domain/services/background_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/desktop_bridge.dart';
import 'package:site_signal/features/monitoring/domain/services/favicon_resolver.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/health_result_reducer.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';
import 'package:site_signal/features/monitoring/domain/services/monitoring_policy.dart';

class MonitorController extends ChangeNotifier {
  MonitorController({
    required this.repository,
    required this.healthChecker,
    required this.faviconResolver,
    required this.desktopBridge,
    this.backgroundMonitor = const UnsupportedBackgroundMonitor(),
    this.internetConnectivityChecker = const AssumedOnlineConnectivityChecker(),
    this.historyLimit = defaultMonitorHistoryLimit,
    this.schedulerInterval = const Duration(seconds: 1),
    this.connectivityDebounce = const Duration(milliseconds: 750),
    PersistedMonitorState? initialState,
  }) : _sites = List<SiteMonitor>.unmodifiable(
         initialState?.sites ?? const <SiteMonitor>[],
       ),
       _paused = initialState?.paused ?? false,
       _themePreference =
           initialState?.themePreference ?? AppThemePreference.system,
       _primaryColorValue = AppAccentColor.normalizeValue(
         initialState?.primaryColorValue ?? AppAccentColor.defaultValue,
       ),
       _notificationSoundPreference =
           initialState?.notificationSoundPreference ??
           NotificationSoundPreference.siteSignal,
       _hasInitialState = initialState != null;

  final MonitorRepository repository;
  final HealthChecker healthChecker;
  final FaviconResolver faviconResolver;
  final DesktopBridge desktopBridge;
  final BackgroundMonitor backgroundMonitor;
  final InternetConnectivityChecker internetConnectivityChecker;
  final int historyLimit;
  final Duration schedulerInterval;
  final Duration connectivityDebounce;

  final Set<String> _checkingIds = <String>{};
  final Set<Future<void>> _activeChecks = <Future<void>>{};
  final Set<String> _resolvingFaviconIds = <String>{};
  List<SiteMonitor> _sites;
  Timer? _scheduler;
  Timer? _connectivityDebounce;
  StreamSubscription<void>? _connectivitySubscription;
  Future<void>? _initialization;
  Future<void>? _resumeOperation;
  final SerialTaskQueue _saveQueue = SerialTaskQueue();
  final SerialTaskQueue _backgroundSyncQueue = SerialTaskQueue();
  final SerialTaskQueue _menuUpdateQueue = SerialTaskQueue();
  DateTime? _lastSchedulerTick;
  int _wakeEpoch = 0;
  int _configurationEpoch = 0;
  bool _initialized = false;
  bool _paused;
  AppThemePreference _themePreference;
  int _primaryColorValue;
  NotificationSoundPreference _notificationSoundPreference;
  final bool _hasInitialState;
  bool _disposed = false;
  bool _requestingNotificationPermission = false;
  bool _sendingTestNotification = false;
  bool _launchAtStartupSupported = false;
  bool _launchAtStartupEnabled = false;
  bool _updatingLaunchAtStartup = false;
  String? _errorMessage;
  NotificationPermission _notificationPermission =
      NotificationPermission.unsupported;
  BackgroundMonitoringStatus _backgroundMonitoringStatus =
      const BackgroundMonitoringStatus.unavailable();
  ConnectivityAssessment _connectivityAssessment =
      const ConnectivityAssessment.unknown();
  Future<void>? _connectivityCheck;
  Future<void>? _shutdownOperation;
  bool _runningDueBatch = false;

  List<SiteMonitor> get sites => _sites;
  bool get initialized => _initialized;
  bool get paused => _paused;
  AppThemePreference get themePreference => _themePreference;
  int get primaryColorValue => _primaryColorValue;
  NotificationSoundPreference get notificationSoundPreference =>
      _notificationSoundPreference;
  String? get errorMessage => _errorMessage;
  NotificationPermission get notificationPermission => _notificationPermission;
  BackgroundMonitoringStatus get backgroundMonitoringStatus =>
      _backgroundMonitoringStatus;
  ConnectivityAssessment get connectivityAssessment => _connectivityAssessment;
  bool get isOffline =>
      _connectivityAssessment.availability == InternetAvailability.offline;
  bool get isRequestingNotificationPermission =>
      _requestingNotificationPermission;
  bool get isSendingTestNotification => _sendingTestNotification;
  bool get launchAtStartupSupported => _launchAtStartupSupported;
  bool get launchAtStartupEnabled => _launchAtStartupEnabled;
  bool get isUpdatingLaunchAtStartup => _updatingLaunchAtStartup;
  MonitorFleetSummary get fleetSummary => _sites.fleetSummary;
  bool get isCheckingAny => _checkingIds.isNotEmpty;

  bool isChecking(String id) => _checkingIds.contains(id);

  Future<void> initialize() {
    if (_initialized || _disposed) {
      return Future<void>.value();
    }
    final existing = _initialization;
    if (existing != null) {
      return existing;
    }
    late final Future<void> operation;
    operation = _initialize()
        .onError((Object error, StackTrace stackTrace) {
          if (!_disposed) {
            _errorMessage = 'SiteSignal could not finish starting: $error';
            _initialized = true;
            _startScheduler();
            _listenForConnectivityChanges();
            _notifyAndSyncMenu();
          }
        })
        .whenComplete(() {
          if (identical(_initialization, operation)) {
            _initialization = null;
          }
        });
    _initialization = operation;
    return operation;
  }

  Future<void> _initialize() async {
    try {
      await desktopBridge.initialize(
        onCheckAll: checkAll,
        onTogglePaused: () => setPaused(!_paused),
        onQuitRequested: shutdown,
      );
    } on Object catch (error) {
      if (!_disposed) {
        _errorMessage = 'Could not initialize platform integration: $error';
      }
    }
    if (_disposed) {
      return;
    }

    if (!_hasInitialState) {
      try {
        final state = await repository.load();
        if (_disposed) {
          return;
        }
        _sites = List<SiteMonitor>.unmodifiable(state.sites);
        _paused = state.paused;
        _themePreference = state.themePreference;
        _primaryColorValue = AppAccentColor.normalizeValue(
          state.primaryColorValue,
        );
        _notificationSoundPreference = state.notificationSoundPreference;
      } on Object catch (error) {
        if (!_disposed) {
          _errorMessage = 'Could not load saved monitors: $error';
        }
      }
    }
    if (_disposed) {
      return;
    }

    try {
      await backgroundMonitor.initialize(
        onSnapshot: (snapshot) =>
            unawaited(_applyBackgroundSnapshot(snapshot, persist: true)),
      );
      final latestBackground = await backgroundMonitor.loadLatestSnapshot();
      if (latestBackground != null) {
        await _applyBackgroundSnapshot(latestBackground, persist: false);
      }
    } on Object catch (error) {
      if (!_disposed) {
        _backgroundMonitoringStatus = BackgroundMonitoringStatus(
          mode: backgroundMonitor.mode,
          isRunning: false,
          error: error.toString(),
        );
      }
    }
    if (_disposed) {
      return;
    }

    try {
      _notificationPermission = await desktopBridge.notificationPermission();
      if (_disposed) {
        return;
      }
      if (_notificationPermission == NotificationPermission.notDetermined) {
        unawaited(requestNotifications());
      }
    } on Object catch (error) {
      if (!_disposed) {
        _notificationPermission = NotificationPermission.unsupported;
        _errorMessage ??= 'Could not read notification settings: $error';
      }
    }
    if (_disposed) {
      return;
    }
    try {
      final launchAtStartup = await desktopBridge.launchAtStartupEnabled();
      if (_disposed) {
        return;
      }
      _launchAtStartupSupported = launchAtStartup != null;
      _launchAtStartupEnabled = launchAtStartup ?? false;
    } on Object {
      if (!_disposed) {
        _launchAtStartupSupported = false;
        _launchAtStartupEnabled = false;
      }
    }
    if (_disposed) {
      return;
    }
    _initialized = true;
    _startScheduler();
    _listenForConnectivityChanges();
    _notifyAndSyncMenu();

    await _synchronizeBackgroundMonitoring();
    if (_disposed) {
      return;
    }

    if (!_paused &&
        _sites.any((site) => site.enabled) &&
        !backgroundMonitor.ownsAutomaticChecks) {
      unawaited(checkAll());
    }
    unawaited(_resolveMissingFavicons());
  }

  Future<void> handleAppResumed() {
    if (!_initialized || _disposed) {
      return Future<void>.value();
    }
    final existing = _resumeOperation;
    if (existing != null) {
      return existing;
    }
    late final Future<void> operation;
    operation = _handleAppResumed().whenComplete(() {
      if (identical(_resumeOperation, operation)) {
        _resumeOperation = null;
      }
    });
    _resumeOperation = operation;
    return operation;
  }

  Future<void> _handleAppResumed() async {
    _wakeEpoch += 1;
    _lastSchedulerTick = DateTime.now().toUtc();
    if (!_requestingNotificationPermission) {
      try {
        final permission = await desktopBridge.notificationPermission();
        if (permission != _notificationPermission) {
          _notificationPermission = permission;
          _notifySafely();
        }
      } on Object {
        // A permission refresh should not prevent overdue checks from resuming.
      }
    }
    if (_disposed) {
      return;
    }
    if (_launchAtStartupSupported && !_updatingLaunchAtStartup) {
      try {
        final enabled = await desktopBridge.launchAtStartupEnabled();
        if (enabled != null && enabled != _launchAtStartupEnabled) {
          _launchAtStartupEnabled = enabled;
          _notifySafely();
        }
      } on Object {
        // The last known state remains useful if the OS query is unavailable.
      }
    }
    if (_disposed) {
      return;
    }
    try {
      final latestBackground = await backgroundMonitor.loadLatestSnapshot();
      if (latestBackground != null) {
        await _applyBackgroundSnapshot(latestBackground, persist: true);
      }
      _backgroundMonitoringStatus = await backgroundMonitor.refreshStatus();
      if (!_backgroundMonitoringStatus.isRunning &&
          !_paused &&
          _sites.any((site) => site.enabled)) {
        await _synchronizeBackgroundMonitoring();
      }
    } on Object catch (error) {
      if (_disposed) {
        return;
      }
      _backgroundMonitoringStatus = BackgroundMonitoringStatus(
        mode: backgroundMonitor.mode,
        isRunning: false,
        error: error.toString(),
      );
    }
    if (!_paused &&
        _sites.any((site) => site.enabled) &&
        !backgroundMonitor.ownsAutomaticChecks) {
      unawaited(recheckConnectivity());
    }
    _checkDueSites();
  }

  Future<SiteMonitor> addSite({
    required String name,
    required String baseUrl,
    required int intervalSeconds,
  }) async {
    final normalizedUrl = _validatedUniqueUrl(baseUrl);

    final uri = Uri.parse(normalizedUrl);
    final trimmedName = name.trim();
    final site = SiteMonitor(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_sites.length}',
      name: trimmedName.isEmpty ? uri.host : trimmedName,
      baseUrl: normalizedUrl,
      probeUrl: null,
      faviconUrl: null,
      intervalSeconds: MonitoringPolicy.normalizeIntervalSeconds(
        intervalSeconds,
      ),
      enabled: true,
      status: HealthStatus.unknown,
      createdAt: DateTime.now().toUtc(),
      history: const <CheckRecord>[],
      lastCheck: null,
    );

    _sites = List<SiteMonitor>.unmodifiable(<SiteMonitor>[site, ..._sites]);
    _configurationEpoch += 1;
    _errorMessage = null;
    _notifyAndSyncMenu();
    await _persist();
    unawaited(checkSite(site.id));
    unawaited(_resolveFavicon(site.id));
    return site;
  }

  Future<void> updateSite({
    required String id,
    required String name,
    required String baseUrl,
    required int intervalSeconds,
  }) async {
    final index = _sites.indexWhere((site) => site.id == id);
    if (index == -1) {
      return;
    }

    final normalizedUrl = _validatedUniqueUrl(baseUrl, excludingId: id);

    final original = _sites[index];
    final urlChanged = original.baseUrl != normalizedUrl;
    final updated = original.copyWith(
      name: name.trim().isEmpty ? Uri.parse(normalizedUrl).host : name.trim(),
      baseUrl: normalizedUrl,
      clearProbeUrl: urlChanged,
      clearFaviconUrl: urlChanged,
      intervalSeconds: MonitoringPolicy.normalizeIntervalSeconds(
        intervalSeconds,
      ),
      status: urlChanged ? HealthStatus.unknown : original.status,
      history: urlChanged ? const <CheckRecord>[] : original.history,
      clearLastCheck: urlChanged,
    );

    _replaceAt(index, updated);
    _configurationEpoch += 1;
    _notifyAndSyncMenu();
    await _persist();
    if (urlChanged) {
      unawaited(_resolveFavicon(id));
      if (updated.enabled) {
        unawaited(checkSite(id));
      }
    }
  }

  Future<void> removeSite(String id) async {
    _sites = List<SiteMonitor>.unmodifiable(
      _sites.where((site) => site.id != id),
    );
    _configurationEpoch += 1;
    _checkingIds.remove(id);
    _notifyAndSyncMenu();
    await _persist();
  }

  Future<void> setSiteEnabled(String id, bool enabled) async {
    final index = _sites.indexWhere((site) => site.id == id);
    if (index == -1) {
      return;
    }

    _replaceAt(index, _sites[index].copyWith(enabled: enabled));
    _configurationEpoch += 1;
    _notifyAndSyncMenu();
    await _persist();
    if (enabled && !_paused) {
      unawaited(checkSite(id));
    }
    if (enabled && _sites[index].faviconUrl == null) {
      unawaited(_resolveFavicon(id));
    }
  }

  Future<void> setPaused(bool paused) async {
    if (_paused == paused) {
      return;
    }
    _paused = paused;
    _configurationEpoch += 1;
    _notifyAndSyncMenu();
    await _persistPreferences(synchronizeBackground: true);
    if (!paused) {
      unawaited(checkAll());
    }
  }

  Future<void> setThemePreference(AppThemePreference preference) async {
    if (_themePreference == preference) {
      return;
    }
    _themePreference = preference;
    _notifySafely();
    await _persistPreferences(synchronizeBackground: false);
  }

  Future<void> setPrimaryColorValue(int value) async {
    final normalized = AppAccentColor.normalizeValue(value);
    if (_primaryColorValue == normalized) {
      return;
    }
    _primaryColorValue = normalized;
    _notifySafely();
    await _persistPreferences(synchronizeBackground: false);
  }

  Future<void> setNotificationSoundPreference(
    NotificationSoundPreference preference,
  ) async {
    if (_notificationSoundPreference == preference) {
      return;
    }
    _notificationSoundPreference = preference;
    _notifySafely();
    await _persistPreferences(synchronizeBackground: true);
  }

  Future<void> selectNotificationSoundPreference(
    NotificationSoundPreference preference,
  ) async {
    if (_disposed) {
      return;
    }
    final preview = _notificationSoundPreviewError(preference);
    await setNotificationSoundPreference(preference);
    if (_disposed) {
      return;
    }
    final previewError = await preview;
    if (previewError != null &&
        !_disposed &&
        _notificationSoundPreference == preference) {
      _errorMessage = 'Could not preview the notification sound: $previewError';
      _notifySafely();
    }
  }

  Future<Object?> _notificationSoundPreviewError(
    NotificationSoundPreference preference,
  ) async {
    try {
      await desktopBridge.playNotificationSoundPreview(preference);
      return null;
    } on Object catch (error) {
      return error;
    }
  }

  Future<void> setLaunchAtStartupEnabled(bool enabled) async {
    if (!_launchAtStartupSupported ||
        _updatingLaunchAtStartup ||
        _launchAtStartupEnabled == enabled) {
      return;
    }
    _updatingLaunchAtStartup = true;
    _notifySafely();
    try {
      final actual = await desktopBridge.setLaunchAtStartupEnabled(enabled);
      _launchAtStartupEnabled = actual;
      _errorMessage = actual == enabled
          ? null
          : 'Your system did not allow SiteSignal to change its startup setting.';
    } on Object catch (error) {
      _errorMessage = 'Could not update launch at startup: $error';
    } finally {
      _updatingLaunchAtStartup = false;
      _notifySafely();
    }
  }

  Future<void> checkAll() async {
    final enabledSites = _sites.where((site) => site.enabled).toList();
    if (enabledSites.isEmpty || !await _ensureInternetForChecks()) {
      return;
    }
    await mapConcurrent<SiteMonitor, void>(
      enabledSites,
      (site) => _checkSite(site.id, verifyConnectivity: false),
      maxConcurrent: MonitoringPolicy.maximumConcurrentSiteChecks,
    );
  }

  Future<void> checkSite(String id) => _checkSite(id, verifyConnectivity: true);

  Future<void> _checkSite(String id, {required bool verifyConnectivity}) {
    late final Future<void> operation;
    operation = _runSiteCheck(
      id,
      verifyConnectivity: verifyConnectivity,
    ).whenComplete(() => _activeChecks.remove(operation));
    _activeChecks.add(operation);
    return operation;
  }

  Future<void> _runSiteCheck(
    String id, {
    required bool verifyConnectivity,
  }) async {
    if (_disposed || _checkingIds.contains(id)) {
      return;
    }

    final startingIndex = _sites.indexWhere((site) => site.id == id);
    if (startingIndex == -1) {
      return;
    }

    // Reserve this site before the first await. Two taps, a scheduler tick, and
    // a tray action can otherwise all pass the guard and launch duplicate work.
    final startingSite = _sites[startingIndex];
    final startedPaused = _paused;
    final startingConfigurationEpoch = _configurationEpoch;
    _checkingIds.add(id);
    _notifySafely();
    var recheckAfterCompletion = false;
    try {
      if (verifyConnectivity && !await _ensureInternetForChecks()) {
        return;
      }
      if (_disposed) {
        return;
      }

      if (startingConfigurationEpoch != _configurationEpoch) {
        recheckAfterCompletion = _staleConfigurationRecheckNeeded(id);
        return;
      }

      var currentIndex = _sites.indexWhere((site) => site.id == id);
      if (currentIndex == -1) {
        return;
      }
      final original = _sites[currentIndex];
      if (original.baseUrl != startingSite.baseUrl ||
          original.enabled != startingSite.enabled ||
          _paused != startedPaused) {
        recheckAfterCompletion = original.enabled && !_paused;
        return;
      }

      final startedWakeEpoch = _wakeEpoch;
      HealthCheckResult result;
      try {
        result = await healthChecker.check(
          Uri.parse(original.baseUrl),
          preferredProbe: Uri.tryParse(original.probeUrl ?? ''),
        );
      } on Object {
        result = HealthCheckResult.internalFailure(
          checkedUrl: original.probeUrl ?? original.baseUrl,
        );
      }

      if (startedWakeEpoch != _wakeEpoch) {
        recheckAfterCompletion = true;
        return;
      }

      if (startingConfigurationEpoch != _configurationEpoch) {
        recheckAfterCompletion = _staleConfigurationRecheckNeeded(id);
        return;
      }

      if (result.requiresConnectivityConfirmation &&
          !await _ensureInternetForChecks(force: true, allowOnFailure: false)) {
        return;
      }

      currentIndex = _sites.indexWhere((site) => site.id == id);
      if (currentIndex == -1 || _disposed) {
        return;
      }

      final current = _sites[currentIndex];
      if (current.baseUrl != original.baseUrl ||
          current.enabled != original.enabled ||
          _paused != startedPaused) {
        recheckAfterCompletion = current.enabled && !_paused;
        return;
      }
      final currentCheckedAt = current.latestCheck?.checkedAt.toUtc();
      if (currentCheckedAt != null &&
          !result.checkedAt.toUtc().isAfter(currentCheckedAt)) {
        return;
      }

      final applied = applyHealthResult(
        current,
        result,
        historyLimit: historyLimit,
      );
      final updated = applied.site;
      _replaceAt(currentIndex, updated);
      _errorMessage = null;
      _notifyAndSyncMenu();
      await _persist();

      if (applied.isTransition) {
        try {
          await _notifyTransition(updated, result);
        } on Object catch (error) {
          _errorMessage = 'Could not send a notification: $error';
          _notifySafely();
        }
      }
    } finally {
      _checkingIds.remove(id);
      _notifySafely();
      if (recheckAfterCompletion && !_disposed) {
        final currentIndex = _sites.indexWhere((site) => site.id == id);
        if (currentIndex != -1 && _sites[currentIndex].enabled && !_paused) {
          scheduleMicrotask(
            () => unawaited(_checkSite(id, verifyConnectivity: true)),
          );
        }
      }
    }
  }

  bool _staleConfigurationRecheckNeeded(String id) {
    final latest = _sites.where((site) => site.id == id).firstOrNull;
    return latest?.enabled == true && !_paused;
  }

  Future<void> clearHistory() async {
    if (_disposed) {
      return;
    }
    final previousSites = _sites;
    _sites = List<SiteMonitor>.unmodifiable(
      _sites.map((site) => site.copyWith(history: const <CheckRecord>[])),
    );
    _notifySafely();
    try {
      await _persist(propagateError: true);
    } on Object catch (error) {
      if (_disposed) {
        return;
      }
      _sites = previousSites;
      _errorMessage = 'Could not clear history: $error';
      _notifySafely();
    }
  }

  Future<void> _resolveFavicon(String id) async {
    if (_disposed || _resolvingFaviconIds.contains(id)) {
      return;
    }
    final originalIndex = _sites.indexWhere((site) => site.id == id);
    if (originalIndex == -1 || _sites[originalIndex].faviconUrl != null) {
      return;
    }

    final original = _sites[originalIndex];
    _resolvingFaviconIds.add(id);
    Uri? favicon;
    try {
      favicon = await faviconResolver.resolve(Uri.parse(original.baseUrl));
    } on Object {
      favicon = null;
    } finally {
      _resolvingFaviconIds.remove(id);
    }
    if (_disposed) {
      return;
    }

    final currentIndex = _sites.indexWhere((site) => site.id == id);
    if (currentIndex == -1 || _sites[currentIndex].faviconUrl != null) {
      return;
    }
    if (_sites[currentIndex].baseUrl != original.baseUrl) {
      scheduleMicrotask(() => unawaited(_resolveFavicon(id)));
      return;
    }
    if (favicon == null) {
      return;
    }
    _replaceAt(
      currentIndex,
      _sites[currentIndex].copyWith(faviconUrl: favicon.toString()),
    );
    _notifyAndSyncMenu();
    await _persist();
  }

  Future<void> _resolveMissingFavicons() async {
    final ids = _sites
        .where((site) => site.faviconUrl == null)
        .map((site) => site.id)
        .toList(growable: false);
    await mapConcurrent<String, void>(ids, _resolveFavicon, maxConcurrent: 3);
  }

  Future<void> invalidateFavicon(String id, String failedUrl) async {
    if (_disposed) {
      return;
    }
    final index = _sites.indexWhere((site) => site.id == id);
    if (index == -1 || _sites[index].faviconUrl != failedUrl) {
      return;
    }
    _replaceAt(index, _sites[index].copyWith(clearFaviconUrl: true));
    _notifyAndSyncMenu();
    await _persist();
  }

  Future<void> requestNotifications() async {
    if (_requestingNotificationPermission || _disposed) {
      return;
    }
    _requestingNotificationPermission = true;
    _notifySafely();
    try {
      _notificationPermission = await desktopBridge
          .requestNotificationPermission();
      _errorMessage = null;
    } on Object catch (error) {
      _errorMessage = 'Could not update notification permission: $error';
    } finally {
      _requestingNotificationPermission = false;
    }
    _notifySafely();
  }

  Future<void> sendTestNotification() async {
    if (_disposed || _sendingTestNotification) {
      return;
    }
    _sendingTestNotification = true;
    _notifySafely();
    final soundPreference = _notificationSoundPreference;
    final usesInAppPreview =
        soundPreference.profile.fileName != null ||
        (soundPreference == NotificationSoundPreference.system &&
            desktopBridge.supportsSystemNotificationSoundPreview);
    try {
      await desktopBridge.showNotification(
        notificationKey: IncidentNotificationKey.test,
        title: '🔔 Test alert',
        body: 'Sound and notifications are ready',
        soundPreference: soundPreference,
        suppressSound: usesInAppPreview,
      );
      if (usesInAppPreview &&
          !_disposed &&
          _notificationSoundPreference == soundPreference) {
        await desktopBridge.playNotificationSoundPreview(soundPreference);
      }
      _errorMessage = null;
    } on Object catch (error) {
      _errorMessage = 'Could not send a test notification: $error';
    } finally {
      _sendingTestNotification = false;
    }
    _notifySafely();
  }

  Future<void> openSite(SiteMonitor site) async {
    try {
      await desktopBridge.openUrl(site.baseUrl);
    } on Object catch (error) {
      _errorMessage = 'Could not open ${site.baseUrl}: $error';
      _notifySafely();
    }
  }

  Future<void> openNotificationSettings() async {
    try {
      final opened = await desktopBridge.openNotificationSettings();
      if (!opened) {
        _errorMessage =
            'Open your system settings and choose SiteSignal notifications.';
      }
    } on Object catch (error) {
      _errorMessage = 'Could not open notification settings: $error';
    }
    _notifySafely();
  }

  void dismissError() {
    _errorMessage = null;
    _notifySafely();
  }

  void _checkDueSites() {
    if (_paused ||
        _disposed ||
        backgroundMonitor.ownsAutomaticChecks ||
        _runningDueBatch) {
      return;
    }

    final now = DateTime.now().toUtc();
    final dueIds = _sites
        .where(
          (site) =>
              !_checkingIds.contains(site.id) &&
              MonitoringPolicy.isDue(site, now),
        )
        .map((site) => site.id)
        .toList(growable: false);
    if (dueIds.isEmpty) {
      return;
    }
    _runningDueBatch = true;
    unawaited(_runDueBatch(dueIds));
  }

  void _handleSchedulerTick() {
    final now = DateTime.now().toUtc();
    final previous = _lastSchedulerTick;
    _lastSchedulerTick = now;
    final expectedGap = schedulerInterval * 3;
    final sleepThreshold = expectedGap > const Duration(seconds: 5)
        ? expectedGap
        : const Duration(seconds: 5);
    if (previous != null &&
        (now.isBefore(previous) || now.difference(previous) > sleepThreshold)) {
      _wakeEpoch += 1;
    }
    _checkDueSites();
  }

  void _startScheduler() {
    if (_disposed || _scheduler != null) {
      return;
    }
    _lastSchedulerTick = DateTime.now().toUtc();
    _scheduler = Timer.periodic(
      schedulerInterval,
      (_) => _handleSchedulerTick(),
    );
  }

  void _listenForConnectivityChanges() {
    if (_disposed || _connectivitySubscription != null) {
      return;
    }
    _connectivitySubscription = internetConnectivityChecker.changes.listen(
      (_) {
        if (_disposed ||
            _paused ||
            backgroundMonitor.ownsAutomaticChecks ||
            !_sites.any((site) => site.enabled)) {
          return;
        }
        _connectivityDebounce?.cancel();
        _connectivityDebounce = Timer(connectivityDebounce, () {
          if (!_disposed) {
            unawaited(_ensureInternetForChecks(force: true));
          }
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        // Due checks and resume remain authoritative if the advisory stream
        // is unavailable on a platform or during a plugin restart.
      },
    );
  }

  Future<void> _runDueBatch(List<String> dueIds) async {
    try {
      if (!await _ensureInternetForChecks()) {
        return;
      }
      if (_disposed || _paused || backgroundMonitor.ownsAutomaticChecks) {
        return;
      }
      final eligibleIds = dueIds.where((id) {
        final site = _sites.where((site) => site.id == id).firstOrNull;
        return site?.enabled == true;
      });
      await mapConcurrent<String, void>(
        eligibleIds,
        (id) => _checkSite(id, verifyConnectivity: false),
        maxConcurrent: MonitoringPolicy.maximumConcurrentSiteChecks,
      );
    } finally {
      _runningDueBatch = false;
    }
  }

  Future<void> recheckConnectivity() async {
    await _ensureInternetForChecks(force: true);
  }

  Future<bool> _ensureInternetForChecks({
    bool force = false,
    bool allowOnFailure = true,
  }) async {
    if (_disposed) {
      return false;
    }
    final now = DateTime.now().toUtc();
    final checkedAt = _connectivityAssessment.checkedAt?.toUtc();
    if (!force && checkedAt != null) {
      final maxAge = ConnectivityPolicy.freshnessFor(
        _connectivityAssessment.availability,
      );
      if (!now.isBefore(checkedAt) && now.difference(checkedAt) < maxAge) {
        return !isOffline;
      }
    }

    final existing = _connectivityCheck;
    if (existing != null) {
      try {
        await existing;
        return !isOffline;
      } on Object {
        return allowOnFailure;
      }
    }
    final operation = _assessAndApplyConnectivity();
    _connectivityCheck = operation;
    try {
      await operation;
      // Return the accepted controller state, not a possibly stale assessment
      // that lost a timestamp race with the background worker.
      return !isOffline;
    } on Object {
      // An unavailable reachability service must not manufacture a site or
      // device outage. The guarded website request remains the final fallback.
      return allowOnFailure;
    } finally {
      if (identical(_connectivityCheck, operation)) {
        _connectivityCheck = null;
      }
    }
  }

  Future<void> _assessAndApplyConnectivity() async {
    final assessment = await _assessConnectivityAfterWake();
    await _applyConnectivityAssessment(assessment, notify: true);
  }

  Future<ConnectivityAssessment> _assessConnectivityAfterWake() async {
    var wakeEpoch = _wakeEpoch;
    var assessment = await internetConnectivityChecker.assess();
    if (wakeEpoch != _wakeEpoch) {
      wakeEpoch = _wakeEpoch;
      assessment = await internetConnectivityChecker.assess();
      if (wakeEpoch != _wakeEpoch) {
        assessment = await internetConnectivityChecker.assess();
      }
    }
    return assessment;
  }

  Future<void> _applyConnectivityAssessment(
    ConnectivityAssessment assessment, {
    required bool notify,
  }) async {
    if (_disposed) {
      return;
    }
    final currentCheckedAt = _connectivityAssessment.checkedAt?.toUtc();
    final incomingCheckedAt = assessment.checkedAt?.toUtc();
    if (currentCheckedAt != null &&
        incomingCheckedAt != null &&
        !incomingCheckedAt.isAfter(currentCheckedAt)) {
      return;
    }
    final previous = _connectivityAssessment.availability;
    _connectivityAssessment = assessment;
    _notifySafely();
    if (!_initialized || !notify || previous == assessment.availability) {
      return;
    }
    final notification = IncidentNotification.forConnectivityTransition(
      previous,
      assessment,
      monitoringPaused: _paused,
    );
    try {
      if (notification != null) {
        await desktopBridge.showNotification(
          notificationKey: IncidentNotificationKey.connectivity,
          title: notification.title,
          body: notification.body,
          soundPreference: _notificationSoundPreference,
        );
      }
    } on Object catch (error) {
      _errorMessage = 'Could not send a connectivity alert: $error';
      _notifySafely();
    }
    // A delivery failure must not prevent the background worker from learning
    // the new device-connectivity state.
    unawaited(_synchronizeBackgroundMonitoring());
  }

  Future<void> _notifyTransition(SiteMonitor site, HealthCheckResult result) {
    final notification = IncidentNotification.forTransition(site, result);
    return desktopBridge.showNotification(
      notificationKey: IncidentNotificationKey.site(site.id),
      title: notification.title,
      body: notification.body,
      soundPreference: _notificationSoundPreference,
    );
  }

  Future<void> _persist({bool propagateError = false}) {
    final persistedState = PersistedMonitorState(
      sites: List<SiteMonitor>.unmodifiable(_sites),
      paused: _paused,
      themePreference: _themePreference,
      primaryColorValue: _primaryColorValue,
      notificationSoundPreference: _notificationSoundPreference,
    );
    return _queuePersistence(() async {
      await repository.save(persistedState);
      await _synchronizeBackgroundMonitoring();
    }, propagateError: propagateError);
  }

  Future<void> _persistPreferences({required bool synchronizeBackground}) {
    final preferences = PersistedMonitorPreferences(
      paused: _paused,
      themePreference: _themePreference,
      primaryColorValue: _primaryColorValue,
      notificationSoundPreference: _notificationSoundPreference,
    );
    return _queuePersistence(() async {
      await repository.savePreferences(preferences);
      if (synchronizeBackground) {
        await _synchronizeBackgroundMonitoring();
      }
    });
  }

  Future<void> _queuePersistence(
    Future<void> Function() persist, {
    bool propagateError = false,
  }) {
    return _saveQueue.schedule(
      persist,
      propagateError: propagateError,
      onError: (error, stackTrace) {
        if (!_disposed) {
          _errorMessage = 'Could not save monitor data: $error';
          _notifySafely();
        }
      },
    );
  }

  BackgroundMonitorSnapshot _backgroundSnapshot() {
    return BackgroundMonitorSnapshot(
      sites: List<SiteMonitor>.unmodifiable(_sites),
      paused: _paused,
      notificationSoundPreference: _notificationSoundPreference,
      updatedAt: DateTime.now().toUtc(),
      connectivity: _connectivityAssessment,
    );
  }

  Future<void> _synchronizeBackgroundMonitoring() async {
    final snapshot = _backgroundSnapshot();
    return _backgroundSyncQueue.schedule(() async {
      try {
        final status = await backgroundMonitor.synchronize(snapshot);
        if (_disposed) {
          return;
        }
        final changed =
            status.mode != _backgroundMonitoringStatus.mode ||
            status.isRunning != _backgroundMonitoringStatus.isRunning ||
            status.error != _backgroundMonitoringStatus.error;
        _backgroundMonitoringStatus = status;
        if (changed) {
          _notifySafely();
        }
      } on Object catch (error) {
        if (_disposed) {
          return;
        }
        _backgroundMonitoringStatus = BackgroundMonitoringStatus(
          mode: backgroundMonitor.mode,
          isRunning: false,
          error: error.toString(),
        );
        _notifySafely();
      }
    });
  }

  Future<void> _applyBackgroundSnapshot(
    BackgroundMonitorSnapshot snapshot, {
    required bool persist,
  }) async {
    if (_disposed) {
      return;
    }
    var changed = false;
    var siteChanged = false;
    final merged = List<SiteMonitor>.of(_sites);
    for (var index = 0; index < merged.length; index++) {
      final current = merged[index];
      final backgroundIndex = snapshot.sites.indexWhere(
        (site) => site.id == current.id && site.baseUrl == current.baseUrl,
      );
      if (backgroundIndex == -1) {
        continue;
      }
      final background = snapshot.sites[backgroundIndex];
      final currentCheckedAt = current.latestCheck?.checkedAt.toUtc();
      final backgroundCheckedAt = background.latestCheck?.checkedAt.toUtc();
      if (backgroundCheckedAt == null ||
          (currentCheckedAt != null &&
              !backgroundCheckedAt.isAfter(currentCheckedAt))) {
        continue;
      }
      merged[index] = mergeBackgroundSiteObservation(
        current,
        background,
        historyLimit: historyLimit,
      );
      changed = true;
      siteChanged = true;
    }
    final backgroundConnectivityAt = snapshot.connectivity.checkedAt?.toUtc();
    final currentConnectivityAt = _connectivityAssessment.checkedAt?.toUtc();
    if (backgroundConnectivityAt != null &&
        (currentConnectivityAt == null ||
            backgroundConnectivityAt.isAfter(currentConnectivityAt))) {
      _connectivityAssessment = snapshot.connectivity;
      changed = true;
    }
    if (!changed) {
      return;
    }
    _sites = List<SiteMonitor>.unmodifiable(merged);
    _notifyAndSyncMenu();
    if (persist && _initialized && siteChanged) {
      await _persist();
    }
  }

  String _validatedUniqueUrl(String baseUrl, {String? excludingId}) {
    final validationError = SiteMonitor.validateBaseUrl(baseUrl);
    if (validationError != null) {
      throw ArgumentError(validationError);
    }
    final normalizedUrl = SiteMonitor.normalizeBaseUrl(baseUrl);
    final isDuplicate = _sites.any(
      (site) =>
          site.id != excludingId &&
          site.baseUrl.toLowerCase() == normalizedUrl.toLowerCase(),
    );
    if (isDuplicate) {
      throw ArgumentError('That base URL is already being monitored.');
    }
    return normalizedUrl;
  }

  void _replaceAt(int index, SiteMonitor site) {
    final updated = List<SiteMonitor>.of(_sites);
    updated[index] = site;
    _sites = List<SiteMonitor>.unmodifiable(updated);
  }

  void _notifyAndSyncMenu() {
    _notifySafely();
    final sites = List<SiteMonitor>.unmodifiable(_sites);
    final paused = _paused;
    unawaited(
      _menuUpdateQueue.schedule(
        () => desktopBridge.updateMenu(sites: sites, paused: paused),
        onError: (error, stackTrace) {
          if (!_disposed) {
            _errorMessage = 'Could not update platform status: $error';
            _notifySafely();
          }
        },
      ),
    );
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> shutdown() {
    final existing = _shutdownOperation;
    if (existing != null) {
      return existing;
    }
    _disposed = true;
    _scheduler?.cancel();
    _connectivityDebounce?.cancel();
    final connectivityCancellation =
        _connectivitySubscription?.cancel() ?? Future<void>.value();
    _connectivitySubscription = null;
    final initialization = _initialization;
    final resumeOperation = _resumeOperation;
    final connectivityCheck = _connectivityCheck;
    final activeChecks = List<Future<void>>.of(_activeChecks);
    final operation = (initialization ?? Future<void>.value())
        .onError((_, _) {})
        .then((_) => connectivityCancellation)
        .then((_) async {
          if (resumeOperation != null) {
            try {
              await resumeOperation;
            } on Object {
              // Resume failures have already been reduced to retained state.
            }
          }
        })
        .then((_) async {
          await Future.wait(
            activeChecks.map((check) => check.onError((_, _) {})),
          );
        })
        .then((_) => _saveQueue.drain())
        .then((_) => _backgroundSyncQueue.drain())
        .then((_) => _menuUpdateQueue.drain())
        .then((_) async {
          if (connectivityCheck != null) {
            try {
              await connectivityCheck;
            } on Object {
              // A pending reachability attempt is already treated as unknown.
            }
          }
        })
        .whenComplete(() async {
          healthChecker.close();
          faviconResolver.close();
          desktopBridge.dispose();
          backgroundMonitor.dispose();
          internetConnectivityChecker.close();
          await repository.close();
        });
    _shutdownOperation = operation;
    return operation;
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
