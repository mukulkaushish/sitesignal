import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:site_signal/core/async/async_pool.dart';
import 'package:site_signal/features/monitoring/data/background_monitor_snapshot_codec.dart';
import 'package:site_signal/features/monitoring/data/desktop_app_bridge.dart';
import 'package:site_signal/features/monitoring/data/http_health_checker.dart';
import 'package:site_signal/features/monitoring/data/http_internet_connectivity_checker.dart';
import 'package:site_signal/features/monitoring/domain/entities/incident_notification.dart';
import 'package:site_signal/features/monitoring/domain/entities/incident_notification_key.dart';
import 'package:site_signal/features/monitoring/domain/entities/monitor_fleet_summary.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/background_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/health_result_reducer.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';
import 'package:site_signal/features/monitoring/domain/services/monitoring_policy.dart';

const _serviceNotificationId = 7419;

abstract final class _BackgroundSnapshotProtocol {
  static const legacyStorageKey = 'monitor-snapshot-v1';
  static const configStorageKey =
      'monitor-config-v${BackgroundMonitorSnapshotCodec.schemaVersion}';
  static const runtimeStorageKey =
      'monitor-runtime-v${BackgroundMonitorSnapshotCodec.schemaVersion}';
  static const messageType =
      'monitor-snapshot-v${BackgroundMonitorSnapshotCodec.schemaVersion}';
}

final class _BackgroundSnapshotStore {
  const _BackgroundSnapshotStore();

  Future<BackgroundMonitorSnapshot?> loadRuntimeOrLegacy() async {
    return await _read(_BackgroundSnapshotProtocol.runtimeStorageKey) ??
        await _read(_BackgroundSnapshotProtocol.legacyStorageKey);
  }

  Future<BackgroundMonitorSnapshot?> loadMerged() async {
    final snapshots = await Future.wait(<Future<BackgroundMonitorSnapshot?>>[
      _read(_BackgroundSnapshotProtocol.configStorageKey),
      _read(_BackgroundSnapshotProtocol.runtimeStorageKey),
    ]);
    final config = snapshots[0];
    final runtime = snapshots[1];
    if (config != null && runtime != null) {
      return mergeBackgroundSnapshotResults(config, runtime);
    }
    return config ??
        runtime ??
        await _read(_BackgroundSnapshotProtocol.legacyStorageKey);
  }

  Future<void> saveConfig(BackgroundMonitorSnapshot snapshot) async {
    await _write(_BackgroundSnapshotProtocol.configStorageKey, snapshot);
  }

  Future<String> saveRuntime(BackgroundMonitorSnapshot snapshot) {
    return _write(_BackgroundSnapshotProtocol.runtimeStorageKey, snapshot);
  }

  Future<BackgroundMonitorSnapshot?> _read(String key) async {
    return BackgroundMonitorSnapshotCodec.decode(
      await FlutterForegroundTask.getData<String>(key: key),
    );
  }

  Future<String> _write(String key, BackgroundMonitorSnapshot snapshot) async {
    final encoded = BackgroundMonitorSnapshotCodec.encode(snapshot);
    final saved = await FlutterForegroundTask.saveData(
      key: key,
      value: encoded,
    );
    if (!saved) {
      throw StateError('Could not store the background monitor snapshot.');
    }
    return encoded;
  }
}

@pragma('vm:entry-point')
void startSiteSignalBackgroundTask() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_SiteSignalTaskHandler());
}

class MobileBackgroundMonitor implements BackgroundMonitor {
  MobileBackgroundMonitor();

  final _BackgroundSnapshotStore _snapshotStore =
      const _BackgroundSnapshotStore();
  BackgroundSnapshotCallback? _onSnapshot;
  bool _initialized = false;
  bool _running = false;

  @override
  BackgroundMonitoringMode get mode => Platform.isAndroid
      ? BackgroundMonitoringMode.continuous
      : Platform.isIOS
      ? BackgroundMonitoringMode.opportunistic
      : BackgroundMonitoringMode.unavailable;

  @override
  bool get ownsAutomaticChecks => _running;

  @override
  Future<void> initialize({
    required BackgroundSnapshotCallback onSnapshot,
  }) async {
    if (_initialized || mode == BackgroundMonitoringMode.unavailable) {
      return;
    }
    _onSnapshot = onSnapshot;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.addTaskDataCallback(_handleTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'sitesignal_monitoring_service_v1',
        channelName: 'SiteSignal background monitoring',
        channelDescription:
            'Persistent status while automatic website monitoring is active',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        onlyAlertOnce: true,
        showBadge: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Monitor intervals have a 15-second floor, so a faster permanent tick
        // only burns battery without making any configured check more timely.
        eventAction: ForegroundTaskEventAction.repeat(
          MonitoringPolicy.minimumInterval.inMilliseconds,
        ),
        autoRunOnBoot: Platform.isAndroid,
        autoRunOnMyPackageReplaced: Platform.isAndroid,
        allowWakeLock: Platform.isAndroid,
        allowWifiLock: false,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
    _running = await FlutterForegroundTask.isRunningService;
    _initialized = true;
  }

  @override
  Future<BackgroundMonitorSnapshot?> loadLatestSnapshot() =>
      _snapshotStore.loadRuntimeOrLegacy();

  @override
  Future<BackgroundMonitoringStatus> synchronize(
    BackgroundMonitorSnapshot snapshot,
  ) async {
    if (mode == BackgroundMonitoringMode.unavailable) {
      return const BackgroundMonitoringStatus.unavailable();
    }
    try {
      final latest = await loadLatestSnapshot();
      final synchronized = latest == null
          ? snapshot
          : mergeBackgroundSnapshotResults(snapshot, latest);
      // Configuration has one writer: the main isolate. The worker writes a
      // separate runtime key, removing the previous full-snapshot overwrite
      // race between pause/site edits and background results.
      await _snapshotStore.saveConfig(synchronized);
      final shouldRun =
          !snapshot.paused && snapshot.sites.any((site) => site.enabled);
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (shouldRun && !isRunning) {
        final result = await FlutterForegroundTask.startService(
          serviceId: _serviceNotificationId,
          serviceTypes: Platform.isAndroid
              ? const <ForegroundServiceTypes>[
                  ForegroundServiceTypes.specialUse,
                ]
              : null,
          notificationTitle: 'SiteSignal monitoring',
          notificationText: _serviceSummary(synchronized),
          callback: startSiteSignalBackgroundTask,
        );
        if (result is ServiceRequestFailure) {
          _running = false;
          return BackgroundMonitoringStatus(
            mode: mode,
            isRunning: false,
            error: result.error.toString(),
          );
        }
        _running = true;
      } else if (!shouldRun && isRunning) {
        final result = await FlutterForegroundTask.stopService();
        if (result is ServiceRequestFailure) {
          _running = true;
          return BackgroundMonitoringStatus(
            mode: mode,
            isRunning: true,
            error: result.error.toString(),
          );
        }
        _running = false;
      } else {
        _running = isRunning;
        if (_running) {
          FlutterForegroundTask.sendDataToTask('snapshot-updated');
          final update = await FlutterForegroundTask.updateService(
            notificationTitle: 'SiteSignal monitoring',
            notificationText: _serviceSummary(synchronized),
          );
          if (update is ServiceRequestFailure) {
            return BackgroundMonitoringStatus(
              mode: mode,
              isRunning: true,
              error: update.error.toString(),
            );
          }
        }
      }
      return BackgroundMonitoringStatus(mode: mode, isRunning: _running);
    } on Object catch (error) {
      try {
        _running = await FlutterForegroundTask.isRunningService;
      } on Object {
        // Retain the last known ownership state when the plugin cannot answer.
      }
      return BackgroundMonitoringStatus(
        mode: mode,
        isRunning: _running,
        error: error.toString(),
      );
    }
  }

  @override
  Future<BackgroundMonitoringStatus> refreshStatus() async {
    if (mode == BackgroundMonitoringMode.unavailable) {
      return const BackgroundMonitoringStatus.unavailable();
    }
    try {
      _running = await FlutterForegroundTask.isRunningService;
      return BackgroundMonitoringStatus(mode: mode, isRunning: _running);
    } on Object catch (error) {
      return BackgroundMonitoringStatus(
        mode: mode,
        isRunning: _running,
        error: error.toString(),
      );
    }
  }

  void _handleTaskData(Object data) {
    if (data is! Map ||
        data['type'] != _BackgroundSnapshotProtocol.messageType) {
      return;
    }
    final snapshot = BackgroundMonitorSnapshotCodec.decode(
      data['snapshot'] as String?,
    );
    if (snapshot != null) {
      _onSnapshot?.call(snapshot);
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_handleTaskData);
    _onSnapshot = null;
  }
}

class _SiteSignalTaskHandler extends TaskHandler {
  final _BackgroundSnapshotStore _snapshotStore =
      const _BackgroundSnapshotStore();
  final HttpHealthChecker _healthChecker = HttpHealthChecker();
  final HttpInternetConnectivityChecker _connectivityChecker =
      HttpInternetConnectivityChecker();
  final DesktopAppBridge _bridge = DesktopAppBridge();
  bool _checking = false;
  bool _rerunRequested = false;
  StreamSubscription<void>? _connectivitySubscription;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await _bridge.initialize(
        onCheckAll: _runNow,
        onTogglePaused: _runNow,
        onQuitRequested: () => Future<void>.value(),
      );
    } on Object {
      // Monitoring remains useful if the notification plugin is temporarily
      // unavailable; a later service restart can initialize it again.
    }
    _connectivitySubscription ??= _connectivityChecker.changes.listen(
      (_) => unawaited(_runNow(forceConnectivity: true)),
      onError: (Object error, StackTrace stackTrace) {
        // The 15-second service event remains the fallback signal.
      },
    );
    await _runChecks(timestamp.toUtc());
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_runChecks(timestamp.toUtc()));
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'snapshot-updated') {
      unawaited(_runNow());
    }
  }

  Future<void> _runNow({bool forceConnectivity = false}) =>
      _runChecks(DateTime.now().toUtc(), forceConnectivity: forceConnectivity);

  Future<void> _runChecks(
    DateTime now, {
    bool forceConnectivity = false,
  }) async {
    if (_checking) {
      _rerunRequested = true;
      return;
    }
    _checking = true;
    try {
      final initial = await _loadSnapshot();
      if (initial == null || initial.paused) {
        return;
      }
      final dueSites = _dueSites(initial, now);
      final connectivityCheckedAt = initial.connectivity.checkedAt?.toUtc();
      final offlineRetryDue =
          initial.connectivity.availability == InternetAvailability.offline &&
          (connectivityCheckedAt == null ||
              now.difference(connectivityCheckedAt) >=
                  ConnectivityPolicy.offlineRecheckInterval);
      if (dueSites.isEmpty && !offlineRetryDue && !forceConnectivity) {
        return;
      }

      final assessment = await _connectivityChecker.assess();
      final latest = await _loadSnapshot() ?? initial;
      if (latest.paused) {
        return;
      }
      var working = latest.copyWith(
        connectivity: assessment,
        updatedAt: DateTime.now().toUtc(),
      );
      // Persist the new device state before alerting. If the notification API
      // or task isolate is interrupted, the next run still knows this
      // transition was handled and will not replay its sound.
      await _storeAndBroadcast(working);
      await _notifyConnectivityTransition(latest, working);
      if (assessment.availability == InternetAvailability.offline) {
        return;
      }

      final currentDueSites = _dueSites(working, DateTime.now().toUtc());
      if (currentDueSites.isEmpty) {
        return;
      }

      final outcomes =
          await mapConcurrent<SiteMonitor, _BackgroundCheckOutcome>(
            currentDueSites,
            (site) async {
              try {
                final result = await _healthChecker.check(
                  Uri.parse(site.baseUrl),
                  preferredProbe: Uri.tryParse(site.probeUrl ?? ''),
                );
                return _BackgroundCheckOutcome(site: site, result: result);
              } on Object {
                return _BackgroundCheckOutcome(
                  site: site,
                  result: HealthCheckResult.internalFailure(
                    checkedUrl: site.probeUrl ?? site.baseUrl,
                  ),
                );
              }
            },
            maxConcurrent: MonitoringPolicy.maximumConcurrentSiteChecks,
          );

      if (outcomes.any(
        (outcome) => outcome.result.requiresConnectivityConfirmation,
      )) {
        final afterChecks = await _connectivityChecker.assess();
        final beforeConnectivityUpdate = working;
        working = working.copyWith(
          connectivity: afterChecks,
          updatedAt: DateTime.now().toUtc(),
        );
        await _storeAndBroadcast(working);
        await _notifyConnectivityTransition(beforeConnectivityUpdate, working);
      }

      final freshest = await _loadSnapshot() ?? working;
      if (freshest.paused) {
        return;
      }
      working = freshest.copyWith(
        connectivity: working.connectivity,
        updatedAt: DateTime.now().toUtc(),
      );
      final sites = List<SiteMonitor>.of(working.sites);
      final transitions = <(_BackgroundCheckOutcome, SiteMonitor)>[];
      for (final outcome in outcomes) {
        if (working.connectivity.availability == InternetAvailability.offline &&
            outcome.result.requiresConnectivityConfirmation) {
          continue;
        }
        final index = sites.indexWhere((site) => site.id == outcome.site.id);
        if (index == -1 ||
            !sites[index].enabled ||
            sites[index].baseUrl != outcome.site.baseUrl) {
          continue;
        }
        final current = sites[index];
        final currentCheck = current.latestCheck?.checkedAt.toUtc();
        if (currentCheck != null &&
            !outcome.result.checkedAt.toUtc().isAfter(currentCheck)) {
          continue;
        }
        final applied = applyHealthResult(current, outcome.result);
        sites[index] = applied.site;
        if (applied.isTransition) {
          transitions.add((outcome, applied.site));
        }
      }
      final updatedSnapshot = working.copyWith(
        sites: sites,
        updatedAt: DateTime.now().toUtc(),
      );
      await _storeAndBroadcast(updatedSnapshot);
      for (final transition in transitions) {
        final outcome = transition.$1;
        final site = transition.$2;
        final notification = IncidentNotification.forTransition(
          site,
          outcome.result,
        );
        try {
          await _bridge.showNotification(
            notificationKey: IncidentNotificationKey.site(site.id),
            title: notification.title,
            body: notification.body,
            soundPreference: updatedSnapshot.notificationSoundPreference,
          );
        } on Object {
          // The check result is already persisted; notification delivery can
          // recover independently without replaying the status transition.
        }
      }
    } on Object {
      // A transient plugin, storage, or network failure must not terminate the
      // long-lived task isolate. The next scheduled event retries cleanly.
    } finally {
      _checking = false;
      if (_rerunRequested) {
        _rerunRequested = false;
        unawaited(_runNow());
      }
    }
  }

  List<SiteMonitor> _dueSites(
    BackgroundMonitorSnapshot snapshot,
    DateTime now,
  ) {
    return snapshot.sites
        .where((site) => MonitoringPolicy.isDue(site, now))
        .toList(growable: false);
  }

  Future<void> _notifyConnectivityTransition(
    BackgroundMonitorSnapshot previous,
    BackgroundMonitorSnapshot current,
  ) async {
    final notification = IncidentNotification.forConnectivityTransition(
      previous.connectivity.availability,
      current.connectivity,
      monitoringPaused: current.paused,
    );
    if (notification == null) {
      return;
    }
    try {
      await _bridge.showNotification(
        notificationKey: IncidentNotificationKey.connectivity,
        title: notification.title,
        body: notification.body,
        soundPreference: current.notificationSoundPreference,
      );
    } on Object {
      // State is already persisted, preventing repeated transition sounds.
    }
  }

  Future<void> _storeAndBroadcast(BackgroundMonitorSnapshot snapshot) async {
    final encoded = await _snapshotStore.saveRuntime(snapshot);
    try {
      await _bridge.updateMenu(sites: snapshot.sites, paused: snapshot.paused);
    } on Object {
      // Result storage is authoritative; tray/badge updates are best effort.
    }
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: 'SiteSignal monitoring',
        notificationText: _serviceSummary(snapshot),
      );
    } on Object {
      // The next task event refreshes a stale persistent service summary.
    }
    FlutterForegroundTask.sendDataToMain(<String, Object>{
      'type': _BackgroundSnapshotProtocol.messageType,
      'snapshot': encoded,
    });
  }

  Future<BackgroundMonitorSnapshot?> _loadSnapshot() =>
      _snapshotStore.loadMerged();

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _healthChecker.close();
    _connectivityChecker.close();
    _bridge.dispose();
  }
}

class _BackgroundCheckOutcome {
  const _BackgroundCheckOutcome({required this.site, required this.result});

  final SiteMonitor site;
  final HealthCheckResult result;
}

String _serviceSummary(BackgroundMonitorSnapshot snapshot) {
  if (snapshot.connectivity.availability == InternetAvailability.offline) {
    return 'Offline · checks paused';
  }
  final summary = snapshot.sites.fleetSummary;
  final siteCount =
      '${summary.enabledCount} site${summary.enabledCount == 1 ? '' : 's'}';
  return switch (summary.state) {
    MonitorFleetState.noEnabledSites => 'No enabled sites',
    MonitorFleetState.down => '$siteCount · ${summary.downCount} down',
    MonitorFleetState.checking => '$siteCount · checking',
    MonitorFleetState.healthy => '$siteCount · all online',
  };
}
