import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/background_monitor.dart';

void main() {
  SiteMonitor site({
    required String id,
    required String baseUrl,
    required bool enabled,
    required HealthStatus status,
    CheckRecord? lastCheck,
    List<CheckRecord>? history,
  }) => SiteMonitor(
    id: id,
    name: id,
    baseUrl: baseUrl,
    probeUrl: null,
    faviconUrl: null,
    intervalSeconds: 60,
    enabled: enabled,
    status: status,
    createdAt: DateTime.utc(2026, 8, 2),
    history:
        history ??
        (lastCheck == null ? const <CheckRecord>[] : <CheckRecord>[lastCheck]),
    lastCheck: lastCheck,
  );

  CheckRecord record(DateTime at, HealthStatus status) => CheckRecord(
    checkedAt: at,
    status: status,
    responseTimeMs: 20,
    statusCode: status == HealthStatus.up ? 200 : 503,
    error: status == HealthStatus.up ? null : 'Server returned HTTP 503',
    checkedUrl: 'https://example.com/readyz',
  );

  BackgroundMonitorSnapshot snapshot({
    required List<SiteMonitor> sites,
    required bool paused,
  }) => BackgroundMonitorSnapshot(
    sites: sites,
    paused: paused,
    notificationSoundPreference: NotificationSoundPreference.siteSignal,
    updatedAt: DateTime.utc(2026, 8, 2),
  );

  test('configuration owns membership and enabled state', () {
    final latest = record(DateTime.utc(2026, 8, 2, 1), HealthStatus.down);
    final configuration = snapshot(
      sites: <SiteMonitor>[
        site(
          id: 'kept',
          baseUrl: 'https://example.com',
          enabled: false,
          status: HealthStatus.unknown,
        ),
      ],
      paused: true,
    );
    final runtime = snapshot(
      sites: <SiteMonitor>[
        site(
          id: 'kept',
          baseUrl: 'https://example.com',
          enabled: true,
          status: HealthStatus.down,
          lastCheck: latest,
        ),
        site(
          id: 'removed',
          baseUrl: 'https://removed.example.com',
          enabled: true,
          status: HealthStatus.down,
          lastCheck: latest,
        ),
      ],
      paused: false,
    );

    final merged = mergeBackgroundSnapshotResults(configuration, runtime);

    expect(merged.paused, isTrue);
    expect(merged.sites, hasLength(1));
    expect(merged.sites.single.id, 'kept');
    expect(merged.sites.single.enabled, isFalse);
    expect(merged.sites.single.status, HealthStatus.down);
    expect(merged.sites.single.lastCheck?.checkedAt, latest.checkedAt);
  });

  test('changed origins reject stale runtime observations', () {
    final configuration = snapshot(
      sites: <SiteMonitor>[
        site(
          id: 'site-1',
          baseUrl: 'https://new.example.com',
          enabled: true,
          status: HealthStatus.unknown,
        ),
      ],
      paused: false,
    );
    final runtime = snapshot(
      sites: <SiteMonitor>[
        site(
          id: 'site-1',
          baseUrl: 'https://old.example.com',
          enabled: true,
          status: HealthStatus.down,
          lastCheck: record(DateTime.utc(2026, 8, 2, 1), HealthStatus.down),
        ),
      ],
      paused: false,
    );

    final merged = mergeBackgroundSnapshotResults(configuration, runtime);

    expect(merged.sites.single.baseUrl, 'https://new.example.com');
    expect(merged.sites.single.status, HealthStatus.unknown);
    expect(merged.sites.single.lastCheck, isNull);
  });

  test('new runtime results preserve foreground transition history', () {
    final foregroundUp = record(DateTime.utc(2026, 8, 2, 1), HealthStatus.up);
    final runtimeDown = record(DateTime.utc(2026, 8, 2, 2), HealthStatus.down);
    final configuration = snapshot(
      sites: <SiteMonitor>[
        site(
          id: 'site-1',
          baseUrl: 'https://example.com',
          enabled: true,
          status: HealthStatus.up,
          lastCheck: foregroundUp,
        ),
      ],
      paused: false,
    );
    final runtime = snapshot(
      sites: <SiteMonitor>[
        site(
          id: 'site-1',
          baseUrl: 'https://example.com',
          enabled: true,
          status: HealthStatus.down,
          lastCheck: runtimeDown,
        ),
      ],
      paused: false,
    );

    final merged = mergeBackgroundSnapshotResults(configuration, runtime);

    expect(
      merged.sites.single.history.map((item) => item.status),
      <HealthStatus>[HealthStatus.down, HealthStatus.up],
    );
  });

  test('a worker cannot restore history cleared by the main isolate', () {
    final clearedAt = record(DateTime.utc(2026, 8, 2, 1), HealthStatus.up);
    final repeatedUp = record(DateTime.utc(2026, 8, 2, 2), HealthStatus.up);
    final oldDown = record(DateTime.utc(2026, 8, 2), HealthStatus.down);
    final configuration = snapshot(
      sites: <SiteMonitor>[
        site(
          id: 'site-1',
          baseUrl: 'https://example.com',
          enabled: true,
          status: HealthStatus.up,
          lastCheck: clearedAt,
          history: const <CheckRecord>[],
        ),
      ],
      paused: false,
    );
    final runtime = snapshot(
      sites: <SiteMonitor>[
        site(
          id: 'site-1',
          baseUrl: 'https://example.com',
          enabled: true,
          status: HealthStatus.up,
          lastCheck: repeatedUp,
          history: <CheckRecord>[oldDown],
        ),
      ],
      paused: false,
    );

    final merged = mergeBackgroundSnapshotResults(configuration, runtime);

    expect(merged.sites.single.lastCheck?.checkedAt, repeatedUp.checkedAt);
    expect(merged.sites.single.history, isEmpty);
  });
}
