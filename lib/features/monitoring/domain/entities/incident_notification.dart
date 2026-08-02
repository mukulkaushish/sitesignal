import 'package:site_signal/core/text/string_extensions.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';

class IncidentNotification {
  const IncidentNotification({required this.title, required this.body});

  final String title;
  final String body;

  factory IncidentNotification.forTransition(
    SiteMonitor site,
    HealthCheckResult result,
  ) {
    if (result.status == HealthStatus.up) {
      return IncidentNotification(
        title: _title('🟢', site, 'is back'),
        body: _recoveryBody(result),
      );
    }
    return IncidentNotification(
      title: _title('🔴', site, 'is down'),
      body: _failureBody(result),
    );
  }

  static IncidentNotification? forConnectivityTransition(
    InternetAvailability previous,
    ConnectivityAssessment current, {
    required bool monitoringPaused,
  }) {
    if (previous == current.availability) {
      return null;
    }
    if (current.availability == InternetAvailability.offline) {
      return IncidentNotification(
        title: current.issue == ConnectivityIssue.noNetwork
            ? '📡 No network'
            : '📡 No internet',
        body: monitoringPaused
            ? 'Sites unchanged · Monitoring paused'
            : 'Checks paused · Sites unchanged',
      );
    }
    if (previous == InternetAvailability.offline &&
        current.availability == InternetAvailability.online) {
      return IncidentNotification(
        title: '🟢 Internet restored',
        body: monitoringPaused ? 'Monitoring remains paused' : 'Checks resumed',
      );
    }
    return null;
  }

  static String _title(String emoji, SiteMonitor site, String state) {
    const limit = 30;
    final normalizedName = site.name.normalizedWhitespace;
    final name = normalizedName.isEmpty ? site.host : normalizedName;
    final suffix = ' $state';
    final availableNameLength =
        limit - emoji.graphemeLength - 1 - suffix.graphemeLength;
    final displayName = name.ellipsized(availableNameLength);
    return '$emoji $displayName$suffix';
  }

  static String _failureBody(HealthCheckResult result) {
    final rawSummary = result.error?.trim();
    var summary = rawSummary == null || rawSummary.isEmpty
        ? 'No response'
        : rawSummary.replaceFirst(RegExp(r'[.\s]+$'), '');
    final status = result.statusCode;
    if (status != null && (status < 200 || status >= 300)) {
      return 'HTTP $status';
    }
    summary = switch (summary) {
      'Request timed out' => 'Timed out',
      'Domain name could not be resolved' => 'DNS failed',
      'Secure connection failed' => 'TLS failed',
      'Could not reach the server' => 'Unreachable',
      'Connection was refused' => 'Connection refused',
      'Request could not be completed' => 'Request failed',
      'Page is stuck on “Loading…”' => 'Stuck on “Loading…”',
      'Health endpoint returned a web page' => 'Unexpected web page',
      'Health endpoint reported unhealthy' => 'Reported unhealthy',
      'Infrastructure error page returned' => 'Infrastructure error',
      _ => summary,
    };
    final evidence = <String>[summary];
    return _compact(evidence.join(' · '));
  }

  static String _recoveryBody(HealthCheckResult result) {
    final evidence = <String>[
      if (result.statusCode != null) 'HTTP ${result.statusCode}',
      if (result.responseTimeMs != null) '${result.responseTimeMs} ms',
    ];
    return evidence.isEmpty ? 'Online' : evidence.join(' · ');
  }

  static String _compact(String message) {
    return message.ellipsized(40, minimumWordBreak: 28);
  }
}
