import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';

class HealthCheckResult {
  const HealthCheckResult({
    required this.status,
    required this.checkedAt,
    required this.responseTimeMs,
    required this.statusCode,
    required this.error,
    required this.checkedUrl,
    this.failureDetail,
  });

  final HealthStatus status;
  final DateTime checkedAt;
  final int? responseTimeMs;
  final int? statusCode;

  /// Short, user-facing failure summary suitable for cards and notifications.
  final String? error;

  /// Plain-language context explaining why an apparently successful response
  /// can still be unhealthy. Kept separately so UI does not expose raw probe
  /// diagnostics as its primary message.
  final String? failureDetail;
  final String checkedUrl;

  factory HealthCheckResult.internalFailure({required String checkedUrl}) {
    return HealthCheckResult(
      status: HealthStatus.down,
      checkedAt: DateTime.now().toUtc(),
      responseTimeMs: null,
      statusCode: null,
      error: 'Health check could not run',
      failureDetail: 'SiteSignal could not complete this check.',
      checkedUrl: checkedUrl,
    );
  }

  CheckRecord toRecord() => CheckRecord(
    checkedAt: checkedAt,
    status: status,
    responseTimeMs: responseTimeMs,
    statusCode: statusCode,
    error: error,
    failureDetail: failureDetail,
    checkedUrl: checkedUrl,
  );
}

extension HealthCheckResultConnectivity on HealthCheckResult {
  /// Transport failures need an independent device-connectivity check before
  /// they can be accepted as evidence that a website is down.
  bool get requiresConnectivityConfirmation =>
      status == HealthStatus.down && statusCode == null;
}

abstract interface class HealthChecker {
  Future<HealthCheckResult> check(Uri baseUri, {Uri? preferredProbe});

  void close();
}
