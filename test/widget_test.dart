import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/app/site_signal_app.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';

import 'support/fakes.dart';

Widget _testApp(MonitorController controller) {
  return SiteSignalApp(
    controller: controller,
    applicationVersion: 'Test build',
  );
}

void main() {
  testWidgets('adds a website from the empty dashboard', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MonitorController(
      repository: MemoryMonitorRepository(paused: true),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();

    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();

    expect(find.text('Know before your users do'), findsOneWidget);

    await tester.tap(find.text('Add first website'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('monitor-url-field')),
      'example.com',
    );
    await tester.tap(find.byKey(const ValueKey('monitor-interval-15')));
    await tester.tap(find.byKey(const ValueKey('save-monitor-button')));
    await tester.pumpAndSettle();

    expect(find.text('example.com'), findsOneWidget);
    expect(controller.sites.single.baseUrl, 'https://example.com');
    expect(find.text('Base URL'), findsOneWidget);
    expect(find.text('Every 15s'), findsOneWidget);
    expect(find.byIcon(Icons.public_rounded), findsOneWidget);
    expect(controller.sites.single.intervalSeconds, 15);
  });

  testWidgets('fits every page at the minimum desktop window size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MonitorController(
      repository: MemoryMonitorRepository(
        paused: true,
        sites: <SiteMonitor>[
          SiteMonitor(
            id: 'site-1',
            name: 'Production',
            baseUrl: 'https://example.com',
            probeUrl: 'https://example.com/health',
            faviconUrl: null,
            intervalSeconds: 60,
            enabled: true,
            status: HealthStatus.up,
            createdAt: DateTime.utc(2026, 7, 30),
            history: <CheckRecord>[
              CheckRecord(
                checkedAt: DateTime.now().toUtc(),
                status: HealthStatus.up,
                responseTimeMs: 42,
                statusCode: 200,
                error: null,
                checkedUrl: 'https://example.com/health',
              ),
            ],
          ),
        ],
      ),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();

    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();
    final overviewException = tester.takeException();
    expect(
      overviewException,
      isNull,
      reason: overviewException is FlutterError
          ? overviewException.toStringDeep()
          : overviewException?.toString(),
    );

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('1 recorded status change · Today'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Automatic probes'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Automatic probes'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('aligns the wide status badge with monitor actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final site = SiteMonitor(
      id: 'site-1',
      name: 'BI',
      baseUrl: 'https://bi.example.com',
      probeUrl: 'https://bi.example.com/health',
      faviconUrl: null,
      intervalSeconds: 60,
      enabled: true,
      status: HealthStatus.up,
      createdAt: DateTime.utc(2026, 7, 30),
      history: <CheckRecord>[
        CheckRecord(
          checkedAt: DateTime.utc(2026, 8, 2, 16),
          status: HealthStatus.up,
          responseTimeMs: 40,
          statusCode: 200,
          error: null,
          checkedUrl: 'https://bi.example.com/health',
        ),
      ],
    );
    final controller = MonitorController(
      repository: MemoryMonitorRepository(sites: <SiteMonitor>[site]),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      backgroundMonitor: FakeBackgroundMonitor(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();

    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();

    final status = find.byKey(const ValueKey('monitor-status-site-1'));
    final openAction = find.byKey(const ValueKey('open-site-site-1'));
    expect(find.text('Up'), findsOneWidget);
    expect(status, findsOneWidget);
    expect(openAction, findsOneWidget);
    expect(
      tester.getCenter(status).dy,
      closeTo(tester.getCenter(openAction).dy, 0.5),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('history defaults to today and supports every date range', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    DateTime localDay(int dayOffset) =>
        DateTime(now.year, now.month, now.day + dayOffset, 12).toUtc();

    final records = <CheckRecord>[
      for (final dayOffset in <int>[0, -1, -2, -5, -10])
        CheckRecord(
          checkedAt: localDay(dayOffset),
          status: dayOffset.isEven ? HealthStatus.up : HealthStatus.down,
          responseTimeMs: 42,
          statusCode: dayOffset.isEven ? 200 : 503,
          error: dayOffset.isEven ? null : 'Server returned HTTP 503',
          checkedUrl: 'https://example.com/health',
        ),
    ];
    final controller = MonitorController(
      repository: MemoryMonitorRepository(
        paused: true,
        sites: <SiteMonitor>[
          SiteMonitor(
            id: 'site-1',
            name: 'Production',
            baseUrl: 'https://example.com',
            probeUrl: 'https://example.com/health',
            faviconUrl: null,
            intervalSeconds: 60,
            enabled: true,
            status: HealthStatus.up,
            createdAt: localDay(-30),
            history: records,
          ),
        ],
      ),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();

    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('1 recorded status change · Today'), findsOneWidget);

    Future<void> selectRange(String range, int expectedCount) async {
      await tester.tap(find.byKey(const ValueKey('history-range-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(range).last);
      await tester.pumpAndSettle();
      expect(
        find.text(
          '$expectedCount recorded status '
          'change${expectedCount == 1 ? '' : 's'} · $range',
        ),
        findsOneWidget,
      );
    }

    await selectRange('Yesterday', 1);
    await selectRange('3 days', 3);
    await selectRange('7 days', 4);
    await selectRange('All', 5);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('fits navigation pages on a phone-sized screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MonitorController(
      repository: MemoryMonitorRepository(paused: true),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();
    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('supports large system text on a phone-sized screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final controller = MonitorController(
      repository: MemoryMonitorRepository(
        paused: true,
        sites: <SiteMonitor>[
          SiteMonitor(
            id: 'site-1',
            name: 'Production status portal',
            baseUrl: 'https://example.com',
            probeUrl: 'https://example.com/readyz',
            faviconUrl: null,
            intervalSeconds: 60,
            enabled: true,
            status: HealthStatus.down,
            createdAt: DateTime.utc(2026, 8, 2),
            history: <CheckRecord>[
              CheckRecord(
                checkedAt: DateTime.now().toUtc(),
                status: HealthStatus.down,
                responseTimeMs: 84,
                statusCode: 503,
                error: 'Server returned HTTP 503',
                checkedUrl: 'https://example.com/readyz',
              ),
            ],
          ),
        ],
      ),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();
    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();

    final largeTextOverviewException = tester.takeException();
    expect(
      largeTextOverviewException,
      isNull,
      reason: largeTextOverviewException is FlutterError
          ? largeTextOverviewException.toStringDeep()
          : largeTextOverviewException?.toString(),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps the app bar below system insets on wide mobile layouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    addTearDown(tester.view.reset);

    final controller = MonitorController(
      repository: MemoryMonitorRepository(paused: true),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();
    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();

    final appBarTop = tester
        .getTopLeft(find.byKey(const ValueKey('dashboard-top-bar')))
        .dy;
    expect(appBarTop, greaterThanOrEqualTo(47));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switches and persists the selected appearance', (tester) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = MemoryMonitorRepository(paused: true);
    final controller = MonitorController(
      repository: repository,
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();

    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(controller.themePreference, AppThemePreference.dark);
    expect(repository.state.themePreference, AppThemePreference.dark);
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('selects notification sound and launch-at-startup behavior', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = MemoryMonitorRepository(paused: true);
    final bridge = FakeDesktopBridge();
    final controller = MonitorController(
      repository: repository,
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: bridge,
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();

    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Open-source licenses'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('notification-sound-control')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('notification-sound-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bright chime').last);
    await tester.pumpAndSettle();

    expect(
      controller.notificationSoundPreference,
      NotificationSoundPreference.brightChime,
    );
    expect(
      repository.state.notificationSoundPreference,
      NotificationSoundPreference.brightChime,
    );
    expect(bridge.soundPreviews, <NotificationSoundPreference>[
      NotificationSoundPreference.brightChime,
    ]);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('launch-at-startup-control')),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('launch-at-startup-control')));
    await tester.pumpAndSettle();

    expect(controller.launchAtStartupEnabled, isTrue);
    expect(bridge.launchAtStartup, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('explains a failed health check without internal probe noise', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = MonitorController(
      repository: MemoryMonitorRepository(
        paused: true,
        sites: <SiteMonitor>[
          SiteMonitor(
            id: 'site-1',
            name: 'BI',
            baseUrl: 'https://bi.example.com',
            probeUrl: null,
            faviconUrl: null,
            intervalSeconds: 60,
            enabled: true,
            status: HealthStatus.down,
            createdAt: DateTime.utc(2026, 7, 30),
            history: <CheckRecord>[
              CheckRecord(
                checkedAt: DateTime.utc(2026, 7, 30, 12),
                status: HealthStatus.down,
                responseTimeMs: 120,
                statusCode: 200,
                error:
                    'No healthy response from automatic probes (/, /health, '
                    '/healthz). Base returned Returned an HTML placeholder '
                    'titled "Loading...".',
                checkedUrl: 'https://bi.example.com',
              ),
            ],
          ),
        ],
      ),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();

    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();

    expect(find.text('Page is stuck on “Loading…”'), findsOneWidget);
    expect(
      find.textContaining('returned only a loading shell'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No healthy response from automatic probes'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('changes and persists the primary color from the modern picker', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = MemoryMonitorRepository(paused: true);
    final controller = MonitorController(
      repository: repository,
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();

    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('primary-color-control')));
    await tester.pumpAndSettle();

    expect(find.text('Curated colors'), findsOneWidget);
    expect(find.text('Custom color'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accent-color-2563EB')));
    await tester.pumpAndSettle();

    expect(controller.primaryColorValue, 0xFF2563EB);
    expect(repository.state.primaryColorValue, 0xFF2563EB);
    expect(
      Theme.of(
        tester.element(find.text('Curated colors')),
      ).colorScheme.primary.toARGB32(),
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF2563EB),
      ).primary.toARGB32(),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('accent-color-done')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
