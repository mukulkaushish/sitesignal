import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';

void main() {
  group('SiteMonitor URL handling', () {
    test('adds HTTPS and normalizes a base origin', () {
      expect(
        SiteMonitor.normalizeBaseUrl(' example.com/ '),
        'https://example.com',
      );
    });

    test('accepts HTTP and HTTPS base URLs', () {
      expect(SiteMonitor.validateBaseUrl('example.com'), isNull);
      expect(SiteMonitor.validateBaseUrl('http://localhost:8080'), isNull);
    });

    test('rejects paths, unsupported schemes, and credentials', () {
      expect(SiteMonitor.validateBaseUrl('example.com/health'), isNotNull);
      expect(SiteMonitor.validateBaseUrl('ftp://example.com'), isNotNull);
      expect(
        SiteMonitor.validateBaseUrl('https://user:secret@example.com'),
        isNotNull,
      );
    });
  });

  test('computes uptime from status transition history', () {
    final site = SiteMonitor(
      id: 'site-1',
      name: 'Example',
      baseUrl: 'https://example.com',
      probeUrl: 'https://example.com/health',
      faviconUrl: 'https://example.com/favicon.ico',
      intervalSeconds: 60,
      enabled: true,
      status: HealthStatus.down,
      createdAt: DateTime.utc(2026, 1, 1),
      history: <CheckRecord>[
        CheckRecord(
          checkedAt: DateTime.utc(2026, 1, 1, 0, 2),
          status: HealthStatus.down,
          responseTimeMs: 110,
          statusCode: 503,
          error: 'HTTP 503',
          checkedUrl: 'https://example.com/health',
        ),
        CheckRecord(
          checkedAt: DateTime.utc(2026, 1, 1, 0, 1),
          status: HealthStatus.up,
          responseTimeMs: 42,
          statusCode: 200,
          error: null,
          checkedUrl: 'https://example.com/health',
        ),
      ],
    );

    expect(site.status, HealthStatus.down);
    expect(site.history, hasLength(2));
    expect(site.history.first.statusCode, 503);
    expect(site.probeUrl, 'https://example.com/health');
    expect(site.uptimePercentAt(DateTime.utc(2026, 1, 1, 0, 3)), 50);
  });
}
