import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/monitoring_policy.dart';

void main() {
  test('normalizes persisted and user-provided intervals', () {
    expect(
      MonitoringPolicy.normalizeIntervalSeconds(1),
      MonitoringPolicy.minimumIntervalSeconds,
    );
    expect(MonitoringPolicy.normalizeIntervalSeconds(300), 300);
    expect(
      MonitoringPolicy.normalizeIntervalSeconds(999999),
      MonitoringPolicy.maximumIntervalSeconds,
    );
  });

  test('due policy is shared for first, elapsed, and clock-skewed checks', () {
    final now = DateTime.utc(2026, 8, 2, 12);

    expect(MonitoringPolicy.isDue(_site(), now), isTrue);
    expect(
      MonitoringPolicy.isDue(
        _site(checkedAt: now.subtract(const Duration(seconds: 59))),
        now,
      ),
      isFalse,
    );
    expect(
      MonitoringPolicy.isDue(
        _site(checkedAt: now.subtract(const Duration(seconds: 60))),
        now,
      ),
      isTrue,
    );
    expect(
      MonitoringPolicy.isDue(
        _site(checkedAt: now.add(const Duration(minutes: 1))),
        now,
      ),
      isTrue,
    );
    expect(MonitoringPolicy.isDue(_site(enabled: false), now), isFalse);
  });
}

SiteMonitor _site({bool enabled = true, DateTime? checkedAt}) {
  final lastCheck = checkedAt == null
      ? null
      : CheckRecord(
          checkedAt: checkedAt,
          status: HealthStatus.up,
          responseTimeMs: 20,
          statusCode: 200,
          error: null,
          checkedUrl: 'https://example.com',
        );
  return SiteMonitor(
    id: 'site',
    name: 'Example',
    baseUrl: 'https://example.com',
    probeUrl: null,
    faviconUrl: null,
    intervalSeconds: MonitoringPolicy.defaultIntervalSeconds,
    enabled: enabled,
    status: checkedAt == null ? HealthStatus.unknown : HealthStatus.up,
    createdAt: DateTime.utc(2026),
    history: const <CheckRecord>[],
    lastCheck: lastCheck,
  );
}
