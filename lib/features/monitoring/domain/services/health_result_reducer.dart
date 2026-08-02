import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';

/// The deterministic result of applying one fresh health check to one site.
class AppliedHealthResult {
  const AppliedHealthResult({required this.site, required this.isTransition});

  final SiteMonitor site;
  final bool isTransition;
}

/// Applies health state identically in the UI and the background isolate.
///
/// [lastCheck] retains every latest observation while [SiteMonitor.history]
/// records only the baseline and later status transitions.
AppliedHealthResult applyHealthResult(
  SiteMonitor current,
  HealthCheckResult result, {
  int historyLimit = defaultMonitorHistoryLimit,
}) {
  if (historyLimit < 1) {
    throw ArgumentError.value(
      historyLimit,
      'historyLimit',
      'Must be positive.',
    );
  }
  final record = result.toRecord();
  final statusChanged = current.status != result.status;
  final shouldRecord = current.history.isEmpty || statusChanged;
  final history = shouldRecord
      ? <CheckRecord>[
          record,
          ...current.history,
        ].take(historyLimit).toList(growable: false)
      : current.history;
  return AppliedHealthResult(
    site: current.copyWith(
      status: result.status,
      history: history,
      lastCheck: record,
      probeUrl: result.status == HealthStatus.up ? result.checkedUrl : null,
    ),
    isTransition: current.status != HealthStatus.unknown && statusChanged,
  );
}
