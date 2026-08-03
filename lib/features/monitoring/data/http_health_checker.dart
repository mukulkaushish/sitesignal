import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:site_signal/core/async/async_pool.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';

class HttpHealthChecker implements HealthChecker {
  HttpHealthChecker({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  static const int _maximumInspectedBodyBytes = 64 * 1024;

  /// A bounded, same-origin discovery set covering common framework and
  /// orchestration conventions. The base origin is always checked first.
  static const List<String> automaticProbePaths = <String>[
    '/health',
    '/healthz',
    '/livez',
    '/readyz',
    '/health/live',
    '/health/ready',
    '/api/health',
    '/actuator/health',
    '/q/health',
    '/-/healthy',
    '/-/ready',
    '/status',
  ];

  @override
  Future<HealthCheckResult> check(Uri baseUri, {Uri? preferredProbe}) async {
    final origin = _origin(baseUri);
    final preferred =
        preferredProbe != null && _sameOrigin(origin, preferredProbe)
        ? preferredProbe.removeFragment()
        : null;
    final attempted = <String>{};
    HealthCheckResult? originResult;

    Future<HealthCheckResult> run(Uri uri, {required bool allowHtml}) {
      attempted.add(uri.toString());
      return _checkSingle(uri, allowHtml: allowHtml);
    }

    if (preferred != null) {
      final preferredResult = await run(
        preferred,
        allowHtml: preferred.toString() == origin.toString(),
      );
      if (preferredResult.status == HealthStatus.up) {
        return preferredResult;
      }
      if (preferred.toString() == origin.toString()) {
        originResult = preferredResult;
      }
    }

    final baseResult = originResult ?? await run(origin, allowHtml: true);
    if (baseResult.status == HealthStatus.up) {
      return baseResult;
    }

    // A path cannot repair DNS, TLS, or host connectivity. Avoid issuing a
    // burst of equivalent requests when the origin itself was unreachable.
    if (baseResult.statusCode == null) {
      return baseResult;
    }

    final candidates = automaticProbePaths
        .map(origin.resolve)
        .where((uri) => attempted.add(uri.toString()))
        .toList(growable: false);
    // Probe in tiny batches. This bounds fan-out and avoids waiting for every
    // convention once one endpoint has proved that the service is ready.
    for (var offset = 0; offset < candidates.length; offset += 2) {
      final end = offset + 2 < candidates.length
          ? offset + 2
          : candidates.length;
      final results = await mapConcurrent<Uri, HealthCheckResult>(
        candidates.sublist(offset, end),
        (uri) => _checkSingle(uri, allowHtml: false),
        maxConcurrent: 2,
      );
      for (final result in results) {
        if (result.status == HealthStatus.up) {
          return result;
        }
      }
    }

    final failure = _failureWithProbeContext(baseResult);
    return HealthCheckResult(
      status: HealthStatus.down,
      checkedAt: DateTime.now().toUtc(),
      responseTimeMs: baseResult.responseTimeMs,
      statusCode: baseResult.statusCode,
      error: failure.summary,
      failureDetail: failure.detail,
      checkedUrl: baseResult.checkedUrl,
    );
  }

  Future<HealthCheckResult> _checkSingle(
    Uri uri, {
    required bool allowHtml,
  }) async {
    final stopwatch = Stopwatch()..start();
    var currentUri = uri;
    var redirectCount = 0;

    try {
      late http.StreamedResponse response;
      while (true) {
        final request = http.Request('GET', currentUri)
          ..followRedirects = false
          ..headers.addAll(const <String, String>{
            'Accept':
                'application/health+json, application/json, '
                'text/plain;q=0.9, */*;q=0.1',
            'Cache-Control': 'no-cache',
            'User-Agent': 'SiteSignal website-health-monitor',
          });

        response = await _client
            .send(request)
            .timeout(_remainingTimeout(stopwatch));
        final location = response.headers['location'];
        if (!_isRedirect(response.statusCode) ||
            location == null ||
            redirectCount >= 5) {
          break;
        }

        Uri redirectUri;
        try {
          redirectUri = currentUri.resolve(location).removeFragment();
        } on FormatException {
          break;
        }
        if (!_isHttpUri(redirectUri) ||
            !_sameOrigin(_origin(uri), redirectUri)) {
          await response.stream
              .timeout(_remainingTimeout(stopwatch))
              .drain<void>();
          stopwatch.stop();
          return HealthCheckResult(
            status: HealthStatus.down,
            checkedAt: DateTime.now().toUtc(),
            responseTimeMs: stopwatch.elapsedMilliseconds,
            statusCode: response.statusCode,
            error: 'Redirect left the monitored site',
            failureDetail:
                'SiteSignal did not follow a health-check redirect to a '
                'different origin.',
            checkedUrl: uri.toString(),
          );
        }

        await response.stream
            .timeout(_remainingTimeout(stopwatch))
            .drain<void>();
        currentUri = redirectUri;
        redirectCount += 1;
      }

      final bodyBytes = <int>[];
      await for (final chunk in response.stream.timeout(
        _remainingTimeout(stopwatch),
      )) {
        final remaining = _maximumInspectedBodyBytes - bodyBytes.length;
        if (remaining <= 0) {
          break;
        }
        bodyBytes.addAll(
          chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
        );
        if (bodyBytes.length >= _maximumInspectedBodyBytes) {
          break;
        }
      }
      stopwatch.stop();

      final hasHealthyStatus =
          response.statusCode >= 200 && response.statusCode < 300;
      final contentIssue = hasHealthyStatus
          ? _contentIssue(
              statusCode: response.statusCode,
              contentType: response.headers['content-type'],
              bodyBytes: bodyBytes,
              allowHtml: allowHtml,
            )
          : null;
      final isHealthy = hasHealthyStatus && contentIssue == null;
      final failure = isHealthy
          ? null
          : contentIssue ?? _httpFailure(response.statusCode);
      return HealthCheckResult(
        status: isHealthy ? HealthStatus.up : HealthStatus.down,
        checkedAt: DateTime.now().toUtc(),
        responseTimeMs: stopwatch.elapsedMilliseconds,
        statusCode: response.statusCode,
        error: failure?.summary,
        failureDetail: failure?.detail,
        checkedUrl: uri.toString(),
      );
    } on TimeoutException {
      stopwatch.stop();
      return HealthCheckResult(
        status: HealthStatus.down,
        checkedAt: DateTime.now().toUtc(),
        responseTimeMs: stopwatch.elapsedMilliseconds,
        statusCode: null,
        error: 'Request timed out',
        failureDetail: 'No response arrived within ${_durationLabel(timeout)}.',
        checkedUrl: uri.toString(),
      );
    } on Object catch (error) {
      stopwatch.stop();
      final failure = _networkFailure(error, uri);
      return HealthCheckResult(
        status: HealthStatus.down,
        checkedAt: DateTime.now().toUtc(),
        responseTimeMs: stopwatch.elapsedMilliseconds,
        statusCode: null,
        error: failure.summary,
        failureDetail: failure.detail,
        checkedUrl: uri.toString(),
      );
    }
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  _HealthFailure _failureWithProbeContext(HealthCheckResult baseResult) {
    final baseDetail =
        baseResult.failureDetail ??
        'The base URL did not return a healthy response.';
    return _HealthFailure(
      baseResult.error ?? 'No healthy endpoint responded',
      '$baseDetail SiteSignal also checked ${automaticProbePaths.length} common '
      'health endpoints; none returned a healthy response.',
    );
  }

  _HealthFailure _httpFailure(int statusCode) {
    if (statusCode >= 500) {
      return _HealthFailure(
        'Server returned HTTP $statusCode',
        'The server reported an error instead of a successful response.',
      );
    }
    if (statusCode >= 400) {
      return _HealthFailure(
        'Endpoint returned HTTP $statusCode',
        'The server is reachable, but this URL did not return a successful '
            'response.',
      );
    }
    if (statusCode >= 300) {
      return _HealthFailure(
        'Redirect ended with HTTP $statusCode',
        'The request did not finish at a successful destination.',
      );
    }
    return _HealthFailure(
      'Endpoint returned HTTP $statusCode',
      'The response was outside the successful HTTP 2xx range.',
    );
  }

  _HealthFailure _networkFailure(Object error, Uri uri) {
    final description = _compactError(error);
    final normalized = description.toLowerCase();

    if (error is HandshakeException) {
      return const _HealthFailure(
        'Secure connection failed',
        'The server’s TLS certificate or secure handshake could not be '
            'verified.',
      );
    }
    if (error is SocketException) {
      if (normalized.contains('failed host lookup') ||
          normalized.contains('name or service not known') ||
          normalized.contains('nodename nor servname')) {
        return _HealthFailure(
          'Domain name could not be resolved',
          'DNS could not find ${uri.host}. Check the address and network '
              'connection.',
        );
      }
      if (normalized.contains('connection refused')) {
        return _HealthFailure(
          'Connection was refused',
          '${uri.host} is reachable, but it is not accepting this connection.',
        );
      }
      return _HealthFailure(
        'Could not reach the server',
        'SiteSignal could not open a connection to ${uri.host}.',
      );
    }
    if (error is http.ClientException) {
      return _HealthFailure(
        'Request could not be completed',
        description.isEmpty
            ? 'The HTTP request ended before a response was received.'
            : description,
      );
    }
    return _HealthFailure(
      'Health check could not be completed',
      description.isEmpty
          ? 'The check ended unexpectedly before a response was received.'
          : description,
    );
  }

  String _compactError(Object error) {
    final description = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (description.length <= 180) {
      return description;
    }
    return '${description.substring(0, 177)}…';
  }

  String _durationLabel(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds} milliseconds';
    }
    if (duration.inMilliseconds % 1000 == 0) {
      final seconds = duration.inSeconds;
      return '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
    }
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} seconds';
  }

  Duration _remainingTimeout(Stopwatch stopwatch) {
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Health check exceeded its timeout.');
    }
    return remaining;
  }

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  bool _isHttpUri(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  _HealthFailure? _contentIssue({
    required int statusCode,
    required String? contentType,
    required List<int> bodyBytes,
    required bool allowHtml,
  }) {
    if (bodyBytes.isEmpty) {
      return null;
    }

    final body = utf8.decode(bodyBytes, allowMalformed: true);
    final normalizedContentType = contentType?.toLowerCase() ?? '';
    final normalizedStart = body.trimLeft().toLowerCase();
    final machineReadableIssue = _machineReadableHealthIssue(
      body,
      normalizedContentType,
      statusCode,
    );
    if (machineReadableIssue != null) {
      return machineReadableIssue;
    }
    final looksLikeHtml =
        normalizedContentType.contains('text/html') ||
        normalizedContentType.contains('application/xhtml+xml') ||
        normalizedStart.startsWith('<!doctype html') ||
        normalizedStart.startsWith('<html');
    if (!looksLikeHtml) {
      return null;
    }

    final normalizedBody = body.toLowerCase();
    final titleMatch = RegExp(
      r'<title[^>]*>\s*([^<]*)</title>',
      caseSensitive: false,
    ).firstMatch(body);
    final title = titleMatch?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
    final normalizedTitle = title?.toLowerCase();

    if (normalizedTitle == 'loading' ||
        normalizedTitle == 'loading...' ||
        normalizedTitle == 'loading…') {
      return _HealthFailure(
        'Page is stuck on “Loading…”',
        'The server answered with HTTP $statusCode, but the HTML contained '
            'only a loading shell, so SiteSignal treats it as unavailable.',
      );
    }

    const unhealthyTitleFragments = <String>[
      'bad gateway',
      'service unavailable',
      'gateway timeout',
      'internal server error',
      'application error',
      'just a moment',
    ];
    if (normalizedTitle != null &&
        unhealthyTitleFragments.any(normalizedTitle.contains)) {
      final titleText = title ?? 'Error page';
      final displayTitle = titleText.length <= 80
          ? titleText
          : '${titleText.substring(0, 77)}…';
      return _HealthFailure(
        'Page returned “$displayTitle”',
        'The server answered with HTTP $statusCode, but the body is an error '
            'or interstitial page rather than the website.',
      );
    }

    const unhealthyBodyMarkers = <String>[
      'no healthy upstream',
      'cf-error-details',
      'cloudflare error',
      'default backend - 404',
    ];
    if (unhealthyBodyMarkers.any(normalizedBody.contains)) {
      return _HealthFailure(
        'Infrastructure error page returned',
        'The server answered with HTTP $statusCode, but the response body '
            'contains an upstream or hosting error.',
      );
    }

    if (!allowHtml) {
      return _HealthFailure(
        'Health endpoint returned a web page',
        'The server answered with HTTP $statusCode, but this discovered health '
            'path returned HTML instead of a machine-readable health response.',
      );
    }

    return null;
  }

  _HealthFailure? _machineReadableHealthIssue(
    String body,
    String contentType,
    int statusCode,
  ) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    String? unhealthyValue;
    if (contentType.contains('json') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          final map = Map<String, Object?>.from(decoded);
          for (final key in const <String>['status', 'state']) {
            final value = map[key];
            if (value is String && _isUnhealthyWord(value)) {
              unhealthyValue = value;
              break;
            }
          }
          for (final key in const <String>['healthy', 'ok']) {
            if (map[key] == false) {
              unhealthyValue ??= '$key=false';
            }
          }
        }
      } on Object {
        // Invalid JSON is not enough evidence to override a successful status.
      }
    } else if (contentType.contains('text/plain') &&
        trimmed.length <= 32 &&
        _isUnhealthyWord(trimmed)) {
      unhealthyValue = trimmed;
    }
    if (unhealthyValue == null) {
      return null;
    }
    final evidence = unhealthyValue.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _HealthFailure(
      'Health endpoint reported unhealthy',
      'The server answered with HTTP $statusCode, but its health payload '
          'reported “$evidence”.',
    );
  }

  bool _isUnhealthyWord(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('-', '_');
    return const <String>{
      'down',
      'unhealthy',
      'failing',
      'failed',
      'error',
      'unavailable',
      'out_of_service',
      'not_ready',
    }.contains(normalized);
  }

  Uri _origin(Uri uri) => SiteMonitor.normalizeOrigin(uri);

  bool _sameOrigin(Uri first, Uri second) {
    return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
        first.host.toLowerCase() == second.host.toLowerCase() &&
        first.port == second.port;
  }
}

class _HealthFailure {
  const _HealthFailure(this.summary, this.detail);

  final String summary;
  final String detail;
}
