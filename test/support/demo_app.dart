import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';

import 'fakes.dart';

Future<MonitorController> createDemoMonitorController({
  AppThemePreference themePreference = AppThemePreference.light,
  FakeDesktopBridge? desktopBridge,
  DateTime? referenceTime,
}) async {
  final controller = MonitorController(
    repository: MemoryMonitorRepository(
      sites: demoSites(referenceTime: referenceTime),
      themePreference: themePreference,
    ),
    healthChecker: ScriptedHealthChecker(),
    faviconResolver: FakeFaviconResolver(),
    desktopBridge: desktopBridge ?? FakeDesktopBridge(),
    backgroundMonitor: FakeBackgroundMonitor(),
    schedulerInterval: const Duration(days: 1),
  );
  await controller.initialize();
  return controller;
}

List<SiteMonitor> demoSites({DateTime? referenceTime}) {
  final now = (referenceTime ?? DateTime.now()).toUtc();
  final startOfToday = DateTime.utc(now.year, now.month, now.day);
  final elapsedToday = now.difference(startOfToday);
  final productionTransition = startOfToday.add(
    Duration(milliseconds: elapsedToday.inMilliseconds ~/ 3),
  );
  return <SiteMonitor>[
    SiteMonitor(
      id: 'sample-api',
      name: 'Production API',
      baseUrl: 'https://api.example.com',
      probeUrl: 'https://api.example.com/readyz',
      faviconUrl: null,
      intervalSeconds: 60,
      enabled: true,
      status: HealthStatus.up,
      createdAt: now.subtract(const Duration(days: 30)),
      history: <CheckRecord>[
        CheckRecord(
          checkedAt: productionTransition,
          status: HealthStatus.up,
          responseTimeMs: 42,
          statusCode: 200,
          error: null,
          checkedUrl: 'https://api.example.com/readyz',
        ),
        CheckRecord(
          checkedAt: now.subtract(const Duration(days: 2)),
          status: HealthStatus.up,
          responseTimeMs: 58,
          statusCode: 200,
          error: null,
          checkedUrl: 'https://api.example.com/readyz',
        ),
      ],
      lastCheck: CheckRecord(
        checkedAt: now.subtract(const Duration(minutes: 2)),
        status: HealthStatus.up,
        responseTimeMs: 42,
        statusCode: 200,
        error: null,
        checkedUrl: 'https://api.example.com/readyz',
      ),
    ),
    SiteMonitor(
      id: 'sample-store',
      name: 'Storefront',
      baseUrl: 'https://shop.example.com',
      probeUrl: 'https://shop.example.com/health',
      faviconUrl: null,
      intervalSeconds: 300,
      enabled: true,
      status: HealthStatus.down,
      createdAt: now.subtract(const Duration(days: 14)),
      history: <CheckRecord>[
        CheckRecord(
          checkedAt: startOfToday,
          status: HealthStatus.down,
          responseTimeMs: 316,
          statusCode: 503,
          error: 'Server returned HTTP 503.',
          checkedUrl: 'https://shop.example.com/health',
        ),
        CheckRecord(
          checkedAt: now.subtract(const Duration(days: 1)),
          status: HealthStatus.up,
          responseTimeMs: 81,
          statusCode: 200,
          error: null,
          checkedUrl: 'https://shop.example.com/health',
        ),
      ],
      lastCheck: CheckRecord(
        checkedAt: now.subtract(const Duration(minutes: 12)),
        status: HealthStatus.down,
        responseTimeMs: 316,
        statusCode: 503,
        error: 'Server returned HTTP 503.',
        checkedUrl: 'https://shop.example.com/health',
      ),
    ),
  ];
}
