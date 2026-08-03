import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_signal/features/monitoring/data/http_health_checker.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';

void main() {
  test('treats successful 2xx responses as healthy', () async {
    final checker = HttpHealthChecker(
      client: MockClient((_) async => http.Response('', 204)),
    );

    final result = await checker.check(Uri.parse('https://example.com'));

    expect(result.status, HealthStatus.up);
    expect(result.statusCode, 204);
    expect(result.error, isNull);
    expect(result.checkedUrl, 'https://example.com');
  });

  test('does not accept a terminal redirect as healthy', () async {
    final checker = HttpHealthChecker(
      client: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: const <String, String>{'location': '/missing-target'},
        ),
      ),
    );

    final result = await checker.check(Uri.parse('https://example.com'));

    expect(result.status, HealthStatus.down);
    expect(result.statusCode, 302);
  });

  test('treats 4xx and 5xx responses as down', () async {
    final checker = HttpHealthChecker(
      client: MockClient((_) async => http.Response('Unavailable', 503)),
    );

    final result = await checker.check(Uri.parse('https://example.com'));

    expect(result.status, HealthStatus.down);
    expect(result.statusCode, 503);
    expect(result.error, 'Server returned HTTP 503');
    expect(result.failureDetail, contains('7 common health endpoints'));
    expect(result.failureDetail, isNot(contains('/healthz')));
  });

  test('turns request timeouts into a down result', () async {
    final checker = HttpHealthChecker(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return http.Response('', 200);
      }),
      timeout: const Duration(milliseconds: 5),
    );

    final result = await checker.check(Uri.parse('https://example.com'));

    expect(result.status, HealthStatus.down);
    expect(result.error, 'Request timed out');
    expect(result.failureDetail, contains('5 milliseconds'));
  });

  test('discovers a conventional same-origin health endpoint', () async {
    final requested = <String>[];
    final checker = HttpHealthChecker(
      client: MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response('', request.url.path == '/health' ? 200 : 404);
      }),
    );

    final result = await checker.check(Uri.parse('https://example.com'));

    expect(result.status, HealthStatus.up);
    expect(result.checkedUrl, 'https://example.com/health');
    expect(requested, contains('https://example.com/healthz'));
    expect(requested, isNot(contains('https://example.com/actuator/health')));
    expect(
      requested.every(
        (value) => Uri.parse(value).origin == 'https://example.com',
      ),
      isTrue,
    );
  });

  test('discovers the common livez health endpoint', () async {
    final requested = <String>[];
    final checker = HttpHealthChecker(
      client: MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response('', request.url.path == '/livez' ? 200 : 404);
      }),
    );

    final result = await checker.check(Uri.parse('https://example.com'));

    expect(result.status, HealthStatus.up);
    expect(result.checkedUrl, 'https://example.com/livez');
    expect(requested, contains('https://example.com/livez'));
  });

  test('falls back from a failed remembered probe to the base URL', () async {
    final checker = HttpHealthChecker(
      client: MockClient((request) async {
        return http.Response('', request.url.path.isEmpty ? 200 : 503);
      }),
    );

    final result = await checker.check(
      Uri.parse('https://example.com'),
      preferredProbe: Uri.parse('https://example.com/health'),
    );

    expect(result.status, HealthStatus.up);
    expect(result.checkedUrl, 'https://example.com');
  });

  test('rejects a Loading placeholder reused for every probe path', () async {
    final requested = <String>[];
    final checker = HttpHealthChecker(
      client: MockClient((request) async {
        requested.add(request.url.toString());
        return http.Response(
          '<!doctype html><html><head><title>Loading...</title></head>'
          '<body><div id="main"></div><script src="/app.js"></script></body>'
          '</html>',
          200,
          headers: const <String, String>{'content-type': 'text/html'},
        );
      }),
    );

    final result = await checker.check(Uri.parse('https://bi.example.com'));

    expect(result.status, HealthStatus.down);
    expect(result.error, 'Page is stuck on “Loading…”');
    expect(result.failureDetail, contains('answered with HTTP 200'));
    expect(result.failureDetail, contains('7 common health endpoints'));
    expect(result.failureDetail, isNot(contains('/healthz')));
    expect(requested, contains('https://bi.example.com/health'));
  });

  test('accepts a rendered HTML page with a meaningful title', () async {
    final checker = HttpHealthChecker(
      client: MockClient(
        (_) async => http.Response(
          '<!doctype html><html><head><title>Customer portal</title></head>'
          '<body>Sign in</body></html>',
          200,
          headers: const <String, String>{'content-type': 'text/html'},
        ),
      ),
    );

    final result = await checker.check(Uri.parse('https://example.com'));

    expect(result.status, HealthStatus.up);
    expect(result.error, isNull);
  });

  test('does not mistake a SPA fallback for a health endpoint', () async {
    final checker = HttpHealthChecker(
      client: MockClient((request) async {
        if (request.url.path.isEmpty) {
          return http.Response('Unavailable', 503);
        }
        return http.Response(
          '<!doctype html><html><head><title>Customer portal</title></head>'
          '<body>Sign in</body></html>',
          200,
          headers: const <String, String>{'content-type': 'text/html'},
        );
      }),
    );

    final result = await checker.check(Uri.parse('https://example.com'));

    expect(result.status, HealthStatus.down);
    expect(result.error, 'Server returned HTTP 503');
    expect(result.checkedUrl, 'https://example.com');
  });

  test('honors an unhealthy machine-readable payload with HTTP 200', () async {
    final checker = HttpHealthChecker(
      client: MockClient(
        (_) async => http.Response(
          '{"status":"OUT_OF_SERVICE"}',
          200,
          headers: const <String, String>{'content-type': 'application/json'},
        ),
      ),
    );

    final result = await checker.check(Uri.parse('https://example.com'));

    expect(result.status, HealthStatus.down);
    expect(result.statusCode, 200);
    expect(result.error, 'Health endpoint reported unhealthy');
    expect(result.failureDetail, contains('OUT_OF_SERVICE'));
  });
}
