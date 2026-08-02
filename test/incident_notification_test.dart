import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/core/text/string_extensions.dart';
import 'package:site_signal/features/monitoring/domain/entities/incident_notification.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';

void main() {
  final site = SiteMonitor(
    id: 'site-1',
    name: 'Example',
    baseUrl: 'https://example.com',
    probeUrl: null,
    faviconUrl: null,
    intervalSeconds: 60,
    enabled: true,
    status: HealthStatus.up,
    createdAt: DateTime.utc(2026, 8, 2),
    history: const <CheckRecord>[],
  );

  test('uses health evidence instead of a misleading HTTP 200', () {
    final notification = IncidentNotification.forTransition(
      site,
      HealthCheckResult(
        status: HealthStatus.down,
        checkedAt: DateTime.utc(2026, 8, 2),
        responseTimeMs: 12,
        statusCode: 200,
        error: 'Health endpoint reported unhealthy',
        checkedUrl: 'https://example.com/readyz',
      ),
    );

    expect(notification.title, '🔴 Example is down');
    expect(notification.body, 'Reported unhealthy');
  });

  test('keeps emoji graphemes intact while shortening a site title', () {
    final notification = IncidentNotification.forTransition(
      site.copyWith(name: 'Family 👨‍👩‍👧‍👦 status portal with a long name'),
      HealthCheckResult(
        status: HealthStatus.down,
        checkedAt: DateTime.utc(2026, 8, 2),
        responseTimeMs: null,
        statusCode: 503,
        error: 'Service unavailable',
        checkedUrl: 'https://example.com/readyz',
      ),
    );

    expect(notification.title, contains('👨‍👩‍👧‍👦'));
    expect(notification.title.graphemeLength, lessThanOrEqualTo(30));
  });

  test('does not claim checks resumed while monitoring is paused', () {
    final notification = IncidentNotification.forConnectivityTransition(
      InternetAvailability.offline,
      ConnectivityAssessment(
        availability: InternetAvailability.online,
        issue: ConnectivityIssue.none,
        transports: const <NetworkTransport>[NetworkTransport.wifi],
        checkedAt: DateTime.utc(2026, 8, 2),
      ),
      monitoringPaused: true,
    );

    expect(notification?.body, 'Monitoring remains paused');
  });
}
