import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/health_result_reducer.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 2);

  SiteMonitor site({
    HealthStatus status = HealthStatus.unknown,
    List<CheckRecord> history = const <CheckRecord>[],
  }) => SiteMonitor(
    id: 'site-1',
    name: 'Example',
    baseUrl: 'https://example.com',
    probeUrl: null,
    faviconUrl: null,
    intervalSeconds: 60,
    enabled: true,
    status: status,
    createdAt: createdAt,
    history: history,
  );

  HealthCheckResult result(HealthStatus status, DateTime checkedAt) =>
      HealthCheckResult(
        status: status,
        checkedAt: checkedAt,
        responseTimeMs: 24,
        statusCode: status == HealthStatus.up ? 200 : 503,
        error: status == HealthStatus.up ? null : 'Server returned HTTP 503',
        checkedUrl: 'https://example.com/readyz',
      );

  test('records a baseline without reporting an incident transition', () {
    final applied = applyHealthResult(
      site(),
      result(HealthStatus.up, createdAt.add(const Duration(minutes: 1))),
    );

    expect(applied.isTransition, isFalse);
    expect(applied.site.status, HealthStatus.up);
    expect(applied.site.history, hasLength(1));
    expect(applied.site.probeUrl, 'https://example.com/readyz');
  });

  test('retains only transitions while refreshing the latest observation', () {
    final first = result(
      HealthStatus.up,
      createdAt.add(const Duration(minutes: 1)),
    ).toRecord();
    final applied = applyHealthResult(
      site(status: HealthStatus.up, history: <CheckRecord>[first]),
      result(HealthStatus.up, createdAt.add(const Duration(minutes: 2))),
    );

    expect(applied.isTransition, isFalse);
    expect(applied.site.history, hasLength(1));
    expect(
      applied.site.lastCheck?.checkedAt,
      createdAt.add(const Duration(minutes: 2)),
    );
  });

  test('establishes a new baseline after history was cleared', () {
    final applied = applyHealthResult(
      site(status: HealthStatus.up),
      result(HealthStatus.up, createdAt.add(const Duration(minutes: 2))),
    );

    expect(applied.isTransition, isFalse);
    expect(applied.site.history, hasLength(1));
    expect(applied.site.history.single.status, HealthStatus.up);
  });

  test('reports status changes and respects the history limit', () {
    final existing = result(
      HealthStatus.up,
      createdAt.add(const Duration(minutes: 1)),
    ).toRecord();
    final applied = applyHealthResult(
      site(status: HealthStatus.up, history: <CheckRecord>[existing]),
      result(HealthStatus.down, createdAt.add(const Duration(minutes: 2))),
      historyLimit: 1,
    );

    expect(applied.isTransition, isTrue);
    expect(applied.site.history, hasLength(1));
    expect(applied.site.history.single.status, HealthStatus.down);
    expect(applied.site.probeUrl, isNull);
  });
}
