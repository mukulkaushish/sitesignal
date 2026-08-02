import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';

enum MonitorFleetState { noEnabledSites, checking, healthy, down }

/// A single domain projection used by every fleet-level app surface.
final class MonitorFleetSummary {
  const MonitorFleetSummary({
    required this.totalCount,
    required this.enabledCount,
    required this.healthyCount,
    required this.downCount,
    required this.unknownCount,
  });

  factory MonitorFleetSummary.from(Iterable<SiteMonitor> sites) {
    var totalCount = 0;
    var enabledCount = 0;
    var healthyCount = 0;
    var downCount = 0;
    var unknownCount = 0;
    for (final site in sites) {
      totalCount += 1;
      if (!site.enabled) {
        continue;
      }
      enabledCount += 1;
      switch (site.status) {
        case HealthStatus.up:
          healthyCount += 1;
        case HealthStatus.down:
          downCount += 1;
        case HealthStatus.unknown:
          unknownCount += 1;
      }
    }
    return MonitorFleetSummary(
      totalCount: totalCount,
      enabledCount: enabledCount,
      healthyCount: healthyCount,
      downCount: downCount,
      unknownCount: unknownCount,
    );
  }

  final int totalCount;
  final int enabledCount;
  final int healthyCount;
  final int downCount;
  final int unknownCount;

  MonitorFleetState get state {
    if (downCount > 0) {
      return MonitorFleetState.down;
    }
    if (enabledCount == 0) {
      return MonitorFleetState.noEnabledSites;
    }
    if (unknownCount > 0) {
      return MonitorFleetState.checking;
    }
    return MonitorFleetState.healthy;
  }
}

extension SiteMonitorFleetSummary on Iterable<SiteMonitor> {
  MonitorFleetSummary get fleetSummary => MonitorFleetSummary.from(this);
}
