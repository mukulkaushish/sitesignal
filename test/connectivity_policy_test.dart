import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';

void main() {
  test('offline assessments expire sooner than online assessments', () {
    expect(
      ConnectivityPolicy.freshnessFor(InternetAvailability.offline),
      ConnectivityPolicy.offlineRecheckInterval,
    );
    expect(
      ConnectivityPolicy.freshnessFor(InternetAvailability.online),
      ConnectivityPolicy.onlineFreshness,
    );
    expect(
      ConnectivityPolicy.freshnessFor(InternetAvailability.unknown),
      ConnectivityPolicy.onlineFreshness,
    );
  });

  test('only transport-like failures require connectivity confirmation', () {
    expect(
      _result(status: HealthStatus.down).requiresConnectivityConfirmation,
      isTrue,
    );
    expect(
      _result(
        status: HealthStatus.down,
        statusCode: 503,
      ).requiresConnectivityConfirmation,
      isFalse,
    );
    expect(
      _result(
        status: HealthStatus.up,
        statusCode: 200,
      ).requiresConnectivityConfirmation,
      isFalse,
    );
  });
}

HealthCheckResult _result({required HealthStatus status, int? statusCode}) {
  return HealthCheckResult(
    status: status,
    checkedAt: DateTime.utc(2026, 8, 2),
    responseTimeMs: 10,
    statusCode: statusCode,
    error: null,
    checkedUrl: 'https://example.com',
  );
}
