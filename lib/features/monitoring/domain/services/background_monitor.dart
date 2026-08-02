import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';

enum BackgroundMonitoringMode { unavailable, continuous, opportunistic }

class BackgroundMonitoringStatus {
  const BackgroundMonitoringStatus({
    required this.mode,
    required this.isRunning,
    this.error,
  });

  const BackgroundMonitoringStatus.unavailable()
    : mode = BackgroundMonitoringMode.unavailable,
      isRunning = false,
      error = null;

  final BackgroundMonitoringMode mode;
  final bool isRunning;
  final String? error;
}

class BackgroundMonitorSnapshot {
  const BackgroundMonitorSnapshot({
    required this.sites,
    required this.paused,
    required this.notificationSoundPreference,
    required this.updatedAt,
    this.connectivity = const ConnectivityAssessment.unknown(),
  });

  final List<SiteMonitor> sites;
  final bool paused;
  final NotificationSoundPreference notificationSoundPreference;
  final DateTime updatedAt;
  final ConnectivityAssessment connectivity;

  BackgroundMonitorSnapshot copyWith({
    List<SiteMonitor>? sites,
    bool? paused,
    NotificationSoundPreference? notificationSoundPreference,
    DateTime? updatedAt,
    ConnectivityAssessment? connectivity,
  }) {
    return BackgroundMonitorSnapshot(
      sites: List<SiteMonitor>.unmodifiable(sites ?? this.sites),
      paused: paused ?? this.paused,
      notificationSoundPreference:
          notificationSoundPreference ?? this.notificationSoundPreference,
      updatedAt: updatedAt ?? this.updatedAt,
      connectivity: connectivity ?? this.connectivity,
    );
  }
}

/// Combines UI-owned configuration with only newer worker-owned observations.
///
/// Keeping this reducer pure makes the cross-isolate ownership rule explicit:
/// configuration wins for site membership and settings; runtime wins only for
/// fresher results and connectivity.
BackgroundMonitorSnapshot mergeBackgroundSnapshotResults(
  BackgroundMonitorSnapshot configuration,
  BackgroundMonitorSnapshot runtime,
) {
  final runtimeSitesByIdentity = <(String, String), SiteMonitor>{};
  for (final site in runtime.sites) {
    runtimeSitesByIdentity.putIfAbsent((site.id, site.baseUrl), () => site);
  }
  final sites = <SiteMonitor>[];
  for (final configuredSite in configuration.sites) {
    final runtimeSite =
        runtimeSitesByIdentity[(configuredSite.id, configuredSite.baseUrl)];
    if (runtimeSite == null) {
      sites.add(configuredSite);
      continue;
    }
    final configuredAt = configuredSite.latestCheck?.checkedAt.toUtc();
    final runtimeAt = runtimeSite.latestCheck?.checkedAt.toUtc();
    if (runtimeAt == null ||
        (configuredAt != null && !runtimeAt.isAfter(configuredAt))) {
      sites.add(configuredSite);
      continue;
    }
    sites.add(mergeBackgroundSiteObservation(configuredSite, runtimeSite));
  }
  final configuredConnectivityAt = configuration.connectivity.checkedAt
      ?.toUtc();
  final runtimeConnectivityAt = runtime.connectivity.checkedAt?.toUtc();
  final connectivity =
      runtimeConnectivityAt != null &&
          (configuredConnectivityAt == null ||
              runtimeConnectivityAt.isAfter(configuredConnectivityAt))
      ? runtime.connectivity
      : configuration.connectivity;
  return configuration.copyWith(
    sites: sites,
    connectivity: connectivity,
    updatedAt: DateTime.now().toUtc(),
  );
}

SiteMonitor mergeBackgroundSiteObservation(
  SiteMonitor configuration,
  SiteMonitor runtime, {
  int historyLimit = defaultMonitorHistoryLimit,
}) {
  Iterable<CheckRecord> runtimeHistory = runtime.history;
  final clearWatermark = configuration.history.isEmpty
      ? configuration.latestCheck?.checkedAt.toUtc()
      : null;
  if (clearWatermark != null) {
    runtimeHistory = runtimeHistory.where(
      (record) => record.checkedAt.toUtc().isAfter(clearWatermark),
    );
  }
  return configuration.copyWith(
    status: runtime.status,
    probeUrl: runtime.probeUrl,
    history: configuration.history.mergeTransitions(
      runtimeHistory,
      limit: historyLimit,
    ),
    lastCheck: runtime.lastCheck,
  );
}

typedef BackgroundSnapshotCallback =
    void Function(BackgroundMonitorSnapshot snapshot);

abstract interface class BackgroundMonitor {
  BackgroundMonitoringMode get mode;

  bool get ownsAutomaticChecks;

  Future<void> initialize({required BackgroundSnapshotCallback onSnapshot});

  Future<BackgroundMonitorSnapshot?> loadLatestSnapshot();

  Future<BackgroundMonitoringStatus> synchronize(
    BackgroundMonitorSnapshot snapshot,
  );

  Future<BackgroundMonitoringStatus> refreshStatus();

  void dispose();
}

class UnsupportedBackgroundMonitor implements BackgroundMonitor {
  const UnsupportedBackgroundMonitor();

  @override
  BackgroundMonitoringMode get mode => BackgroundMonitoringMode.unavailable;

  @override
  bool get ownsAutomaticChecks => false;

  @override
  Future<void> initialize({
    required BackgroundSnapshotCallback onSnapshot,
  }) async {}

  @override
  Future<BackgroundMonitorSnapshot?> loadLatestSnapshot() async => null;

  @override
  Future<BackgroundMonitoringStatus> refreshStatus() async =>
      const BackgroundMonitoringStatus.unavailable();

  @override
  Future<BackgroundMonitoringStatus> synchronize(
    BackgroundMonitorSnapshot snapshot,
  ) async => const BackgroundMonitoringStatus.unavailable();

  @override
  void dispose() {}
}
