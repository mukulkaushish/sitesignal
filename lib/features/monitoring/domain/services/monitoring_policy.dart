import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';

/// Shared limits and due-check policy for foreground and background runtimes.
abstract final class MonitoringPolicy {
  static const int defaultIntervalSeconds = 60;
  static const int minimumIntervalSeconds = 15;
  static const int maximumIntervalSeconds = 86400;
  static const int maximumConcurrentSiteChecks = 4;
  static const Duration minimumInterval = Duration(
    seconds: minimumIntervalSeconds,
  );

  static int normalizeIntervalSeconds(int value) {
    return value.clamp(minimumIntervalSeconds, maximumIntervalSeconds);
  }

  static bool isDue(SiteMonitor site, DateTime now) {
    if (!site.enabled) {
      return false;
    }
    final checkedAt = site.latestCheck?.checkedAt.toUtc();
    final currentTime = now.toUtc();
    return checkedAt == null ||
        currentTime.isBefore(checkedAt) ||
        currentTime.difference(checkedAt).inSeconds >= site.intervalSeconds;
  }
}
