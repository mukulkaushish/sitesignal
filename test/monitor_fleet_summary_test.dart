import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/domain/entities/monitor_fleet_summary.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';

void main() {
  test('summarizes enabled fleet state in one pass', () {
    final summary = <SiteMonitor>[
      _site('healthy', HealthStatus.up),
      _site('down', HealthStatus.down),
      _site('checking', HealthStatus.unknown),
      _site('disabled', HealthStatus.down, enabled: false),
    ].fleetSummary;

    expect(summary.totalCount, 4);
    expect(summary.enabledCount, 3);
    expect(summary.healthyCount, 1);
    expect(summary.downCount, 1);
    expect(summary.unknownCount, 1);
    expect(summary.state, MonitorFleetState.down);
  });

  test('coarse state prioritizes down, checking, healthy, then empty', () {
    expect(
      <SiteMonitor>[].fleetSummary.state,
      MonitorFleetState.noEnabledSites,
    );
    expect(
      <SiteMonitor>[
        _site('disabled', HealthStatus.down, enabled: false),
      ].fleetSummary.state,
      MonitorFleetState.noEnabledSites,
    );
    expect(
      <SiteMonitor>[_site('checking', HealthStatus.unknown)].fleetSummary.state,
      MonitorFleetState.checking,
    );
    expect(
      <SiteMonitor>[_site('healthy', HealthStatus.up)].fleetSummary.state,
      MonitorFleetState.healthy,
    );
  });
}

SiteMonitor _site(String id, HealthStatus status, {bool enabled = true}) {
  return SiteMonitor(
    id: id,
    name: id,
    baseUrl: 'https://$id.example.com',
    probeUrl: null,
    faviconUrl: null,
    intervalSeconds: 60,
    enabled: enabled,
    status: status,
    createdAt: DateTime.utc(2026),
    history: const <CheckRecord>[],
  );
}
