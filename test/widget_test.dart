import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/app/site_signal_app.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/favicon_image.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';
import 'package:site_signal/features/monitoring/presentation/pages/overview_view.dart';
import 'package:site_signal/features/updates/domain/entities/app_update.dart';

import 'support/fakes.dart';

Widget _testApp(MonitorController controller) {
  return SiteSignalApp(
    controller: controller,
    applicationVersion: 'Test build',
  );
}

void main() {
  testWidgets('recommends an available stable update', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final bridge = FakeDesktopBridge();
    final controller = MonitorController(
      repository: MemoryMonitorRepository(paused: true),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: bridge,
      updateChecker: FakeUpdateChecker(
        result: const AppUpdate(
          version: '1.0.2',
          releaseUrl:
              'https://github.com/mukulkaushish/sitesignal/releases/tag/v1.0.2',
        ),
      ),
      schedulerInterval: const Duration(days: 1),
    );
    await controller.initialize();
    await controller.checkForUpdates();

    await tester.pumpWidget(_testApp(controller));
    await tester.pumpAndSettle();

    expect(
      find.text('SiteSignal 1.0.2 is available. Updating is recommended.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('view-available-update')));
    await tester.pump();
    expect(bridge.openedUrls, <String>[
      'https://github.com/mukulkaushish/sitesignal/releases/tag/v1.0.2',
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

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
    expect(
      find.byKey(
        ValueKey('site-favicon-fallback-${controller.sites.single.id}'),
      ),
      findsOneWidget,
    );
    expect(controller.sites.single.intervalSeconds, 15);
  });

  testWidgets('renders safe favicon data from memory only', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = MemoryMonitorRepository(
      paused: true,
      sites: <SiteMonitor>[_faviconSite(name: 'Status Portal')],
    );
    final controller = MonitorController(
      repository: repository,
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(result: _faviconImage()),
      desktopBridge: FakeDesktopBridge(),
      initialState: repository.state,
      schedulerInterval: const Duration(days: 1),
    );
    addTearDown(controller.dispose);

    await controller.initialize();
    await tester.pump();

    await tester.pumpWidget(_overviewTestApp(controller));
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(const ValueKey('site-favicon-image-site-favicon')),
    );
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).imageProvider, isA<MemoryImage>());
    expect(image.image, isNot(isA<NetworkImage>()));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await controller.shutdown();
  });

  testWidgets('legacy and malformed favicons use initials without networking', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = MemoryMonitorRepository(
      paused: true,
      sites: <SiteMonitor>[
        _faviconSite(
          id: 'legacy-favicon',
          name: 'Remote Site',
          faviconUrl: 'https://example.com/favicon.ico',
        ),
        _faviconSite(
          id: 'malformed-favicon',
          name: 'Broken Data',
          faviconUrl: 'data:image/png;base64,not-valid-base64',
        ),
      ],
    );
    final controller = MonitorController(
      repository: repository,
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      initialState: repository.state,
      schedulerInterval: const Duration(days: 1),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(_overviewTestApp(controller));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('site-favicon-fallback-legacy-favicon')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('site-favicon-fallback-malformed-favicon')),
      findsOneWidget,
    );
    expect(find.text('RS'), findsOneWidget);
    expect(find.text('BD'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
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

Widget _overviewTestApp(MonitorController controller) {
  return MaterialApp(
    home: Scaffold(
      body: OverviewView(
        controller: controller,
        summary: controller.fleetSummary,
        onAddSite: () {},
      ),
    ),
  );
}

SiteMonitor _faviconSite({
  String id = 'site-favicon',
  required String name,
  String? faviconUrl,
}) {
  return SiteMonitor(
    id: id,
    name: name,
    baseUrl: 'https://$id.example.com',
    probeUrl: null,
    faviconUrl: faviconUrl,
    intervalSeconds: 60,
    enabled: true,
    status: HealthStatus.unknown,
    createdAt: DateTime.utc(2026, 8, 3),
    history: const <CheckRecord>[],
  );
}

FaviconImage _faviconImage() => FaviconImage.fromPngBytes(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8A'
    'AQUBAScY42YAAAAASUVORK5CYII=',
  ),
);
