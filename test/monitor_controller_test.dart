import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/repositories/monitor_repository.dart';
import 'package:site_signal/features/monitoring/domain/services/desktop_bridge.dart';
import 'package:site_signal/features/monitoring/domain/services/health_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';

import 'support/fakes.dart';

void main() {
  late MemoryMonitorRepository repository;
  late ScriptedHealthChecker checker;
  late FakeFaviconResolver faviconResolver;
  late FakeDesktopBridge bridge;
  late MonitorController controller;

  setUp(() {
    repository = MemoryMonitorRepository(
      paused: true,
      sites: <SiteMonitor>[_unknownSite()],
    );
    checker = ScriptedHealthChecker(
      results: <HealthCheckResult>[
        _result(HealthStatus.up, statusCode: 200),
        _result(HealthStatus.up, statusCode: 200),
        _result(
          HealthStatus.down,
          statusCode: 503,
          error: 'Server returned HTTP 503',
          failureDetail: 'The server reported an error.',
        ),
        _result(
          HealthStatus.down,
          statusCode: 503,
          error: 'Server returned HTTP 503',
          failureDetail: 'The server reported an error.',
        ),
        _result(HealthStatus.up, statusCode: 200),
      ],
    );
    faviconResolver = FakeFaviconResolver(
      result: Uri.parse('https://example.com/favicon.ico'),
    );
    bridge = FakeDesktopBridge();
    controller = MonitorController(
      repository: repository,
      healthChecker: checker,
      faviconResolver: faviconResolver,
      desktopBridge: bridge,
      historyLimit: 2,
      schedulerInterval: const Duration(days: 1),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('notifies only on real down and recovery transitions', () async {
    await controller.initialize();

    await controller.checkSite('site-1');
    expect(controller.sites.single.status, HealthStatus.up);
    expect(bridge.notifications, isEmpty);
    expect(controller.sites.single.history, hasLength(1));

    await controller.checkSite('site-1');
    expect(controller.sites.single.status, HealthStatus.up);
    expect(controller.sites.single.history, hasLength(1));
    expect(bridge.notifications, isEmpty);

    await controller.checkSite('site-1');
    expect(controller.sites.single.status, HealthStatus.down);
    expect(bridge.notifications.single.notificationKey, 'site:site-1');
    expect(bridge.notifications.single.title, '🔴 Example is down');
    expect(bridge.notifications.single.body, 'HTTP 503');
    expect(controller.sites.single.history, hasLength(2));

    await controller.checkSite('site-1');
    expect(controller.sites.single.status, HealthStatus.down);
    expect(controller.sites.single.history, hasLength(2));
    expect(bridge.notifications, hasLength(1));

    await controller.checkSite('site-1');
    expect(controller.sites.single.status, HealthStatus.up);
    expect(bridge.notifications.last.notificationKey, 'site:site-1');
    expect(bridge.notifications.last.title, '🟢 Example is back');
    expect(bridge.notifications.last.body, 'HTTP 200 · 25 ms');
    expect(controller.sites.single.history, hasLength(2));
  });

  test('keeps notification titles concise for long website names', () async {
    final localBridge = FakeDesktopBridge();
    final localController = MonitorController(
      repository: MemoryMonitorRepository(
        paused: true,
        sites: <SiteMonitor>[
          _unknownSite(
            name: 'A very long production website name that would be clipped',
          ),
        ],
      ),
      healthChecker: ScriptedHealthChecker(
        results: <HealthCheckResult>[
          _result(HealthStatus.up, statusCode: 200),
          _result(
            HealthStatus.down,
            statusCode: 503,
            error: 'Server returned HTTP 503',
          ),
        ],
      ),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: localBridge,
      schedulerInterval: const Duration(days: 1),
    );
    addTearDown(localController.dispose);
    await localController.initialize();

    await localController.checkSite('site-1');
    await localController.checkSite('site-1');

    final title = localBridge.notifications.single.title;
    expect(title.length, lessThanOrEqualTo(30));
    expect(title, startsWith('🔴 '));
    expect(title, endsWith(' is down'));
    expect(localBridge.notifications.single.body.length, lessThanOrEqualTo(40));
  });

  test('rejects duplicate normalized URLs', () async {
    await controller.initialize();

    expect(
      () => controller.addSite(
        name: 'Duplicate',
        baseUrl: 'https://example.com',
        intervalSeconds: 60,
      ),
      throwsArgumentError,
    );
  });

  test('pause state persists and tray is refreshed', () async {
    await controller.initialize();
    await controller.setPaused(false);

    expect(repository.state.paused, isFalse);
    expect(bridge.menuUpdates.last.paused, isFalse);
  });

  test('appearance preference persists', () async {
    await controller.initialize();
    await controller.setThemePreference(AppThemePreference.dark);

    expect(controller.themePreference, AppThemePreference.dark);
    expect(repository.state.themePreference, AppThemePreference.dark);
  });

  test('primary color preference persists', () async {
    await controller.initialize();
    await controller.setPrimaryColorValue(0xFF2563EB);

    expect(controller.primaryColorValue, 0xFF2563EB);
    expect(repository.state.primaryColorValue, 0xFF2563EB);
  });

  test(
    'notification sound preference persists and is used by alerts',
    () async {
      await controller.initialize();
      await controller.setNotificationSoundPreference(
        NotificationSoundPreference.silent,
      );
      await controller.sendTestNotification();

      expect(
        controller.notificationSoundPreference,
        NotificationSoundPreference.silent,
      );
      expect(
        repository.state.notificationSoundPreference,
        NotificationSoundPreference.silent,
      );
      expect(
        bridge.notifications.single.soundPreference,
        NotificationSoundPreference.silent,
      );
    },
  );

  test('selecting a bundled notification sound previews it', () async {
    await controller.initialize();

    await controller.selectNotificationSoundPreference(
      NotificationSoundPreference.brightChime,
    );

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
  });

  test('test notification plays the selected bundled sound itself', () async {
    await controller.initialize();
    await controller.setNotificationSoundPreference(
      NotificationSoundPreference.beacon,
    );

    await controller.sendTestNotification();

    expect(bridge.notifications, hasLength(1));
    expect(
      bridge.notifications.single.soundPreference,
      NotificationSoundPreference.beacon,
    );
    expect(bridge.notifications.single.suppressSound, isTrue);
    expect(bridge.soundPreviews, <NotificationSoundPreference>[
      NotificationSoundPreference.beacon,
    ]);
  });

  test('test notification previews the platform system sound', () async {
    await controller.initialize();
    await controller.setNotificationSoundPreference(
      NotificationSoundPreference.system,
    );

    await controller.sendTestNotification();

    expect(bridge.notifications.single.suppressSound, isTrue);
    expect(bridge.soundPreviews, <NotificationSoundPreference>[
      NotificationSoundPreference.system,
    ]);
  });

  test(
    'test notification lets the OS sound when preview is unsupported',
    () async {
      bridge.systemNotificationSoundPreviewSupported = false;
      await controller.initialize();
      await controller.setNotificationSoundPreference(
        NotificationSoundPreference.system,
      );

      await controller.sendTestNotification();

      expect(bridge.notifications.single.suppressSound, isFalse);
      expect(bridge.soundPreviews, isEmpty);
    },
  );

  test('coalesces rapid test notification requests', () async {
    await controller.initialize();
    final delivery = Completer<void>();
    bridge.notificationDeliveryCompleter = delivery;

    final first = controller.sendTestNotification();
    await Future<void>.delayed(Duration.zero);
    final second = controller.sendTestNotification();
    delivery.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(bridge.notifications, hasLength(1));
    expect(controller.isSendingTestNotification, isFalse);
  });

  test(
    'device outage pauses checks and sends one connectivity alert',
    () async {
      final connectivity = FakeInternetConnectivityChecker(
        assessments: <ConnectivityAssessment>[
          ConnectivityAssessment(
            availability: InternetAvailability.offline,
            issue: ConnectivityIssue.noInternet,
            transports: const <NetworkTransport>[NetworkTransport.wifi],
            checkedAt: DateTime.now().toUtc(),
          ),
          ConnectivityAssessment(
            availability: InternetAvailability.online,
            issue: ConnectivityIssue.none,
            transports: const <NetworkTransport>[NetworkTransport.mobile],
            checkedAt: DateTime.now().toUtc().add(const Duration(seconds: 1)),
          ),
        ],
      );
      final localChecker = ScriptedHealthChecker(
        results: <HealthCheckResult>[_result(HealthStatus.up, statusCode: 200)],
      );
      final localBridge = FakeDesktopBridge();
      final localController = MonitorController(
        repository: MemoryMonitorRepository(
          paused: true,
          sites: <SiteMonitor>[_unknownSite()],
        ),
        healthChecker: localChecker,
        faviconResolver: FakeFaviconResolver(),
        desktopBridge: localBridge,
        internetConnectivityChecker: connectivity,
        schedulerInterval: const Duration(days: 1),
      );
      addTearDown(localController.dispose);
      await localController.initialize();

      await localController.checkSite('site-1');
      await localController.checkSite('site-1');

      expect(localController.isOffline, isTrue);
      expect(localController.sites.single.status, HealthStatus.unknown);
      expect(localChecker.checkCount, 0);
      expect(connectivity.assessmentCount, 1);
      expect(localBridge.notifications, hasLength(1));
      expect(localBridge.notifications.single.title, '📡 No internet');
      expect(
        localBridge.notifications.single.body,
        'Sites unchanged · Monitoring paused',
      );

      await localController.recheckConnectivity();

      expect(localController.isOffline, isFalse);
      expect(localBridge.notifications, hasLength(2));
      expect(localBridge.notifications.last.title, '🟢 Internet restored');
      expect(localBridge.notifications.last.body, 'Monitoring remains paused');
      expect(
        localBridge.notifications.map((message) => message.notificationKey),
        everyElement('network:connectivity'),
      );

      await localController.checkSite('site-1');
      expect(localChecker.checkCount, 1);
      expect(localController.sites.single.status, HealthStatus.up);
    },
  );

  test('reacts to interface changes without waiting for a due check', () async {
    final changes = StreamController<void>();
    addTearDown(changes.close);
    final now = DateTime.now().toUtc();
    final connectivity = FakeInternetConnectivityChecker(
      changes: changes.stream,
      assessments: <ConnectivityAssessment>[
        ConnectivityAssessment(
          availability: InternetAvailability.online,
          issue: ConnectivityIssue.none,
          transports: const <NetworkTransport>[NetworkTransport.wifi],
          checkedAt: now,
        ),
        ConnectivityAssessment(
          availability: InternetAvailability.offline,
          issue: ConnectivityIssue.noNetwork,
          transports: const <NetworkTransport>[],
          checkedAt: now.add(const Duration(seconds: 1)),
        ),
      ],
    );
    final localBridge = FakeDesktopBridge();
    final localController = MonitorController(
      repository: MemoryMonitorRepository(
        paused: false,
        sites: <SiteMonitor>[_unknownSite()],
      ),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: localBridge,
      internetConnectivityChecker: connectivity,
      schedulerInterval: const Duration(days: 1),
      connectivityDebounce: Duration.zero,
    );
    addTearDown(localController.dispose);
    await localController.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(localController.sites.single.status, HealthStatus.up);

    changes.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(localController.isOffline, isTrue);
    expect(localController.sites.single.status, HealthStatus.up);
    expect(localBridge.notifications.single.title, '📡 No network');
  });

  test(
    'background scheduler exclusively owns interface-change alerts',
    () async {
      final changes = StreamController<void>();
      addTearDown(changes.close);
      final connectivity = FakeInternetConnectivityChecker(
        changes: changes.stream,
        assessments: <ConnectivityAssessment>[
          ConnectivityAssessment(
            availability: InternetAvailability.offline,
            issue: ConnectivityIssue.noNetwork,
            transports: const <NetworkTransport>[],
            checkedAt: DateTime.now().toUtc(),
          ),
        ],
      );
      final localBridge = FakeDesktopBridge();
      final localController = MonitorController(
        repository: MemoryMonitorRepository(
          paused: false,
          sites: <SiteMonitor>[_unknownSite()],
        ),
        healthChecker: ScriptedHealthChecker(),
        faviconResolver: FakeFaviconResolver(),
        desktopBridge: localBridge,
        backgroundMonitor: FakeBackgroundMonitor(),
        internetConnectivityChecker: connectivity,
        schedulerInterval: const Duration(days: 1),
        connectivityDebounce: Duration.zero,
      );
      addTearDown(localController.dispose);
      await localController.initialize();

      changes.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(connectivity.assessmentCount, 0);
      expect(localBridge.notifications, isEmpty);

      await localController.recheckConnectivity();
      expect(connectivity.assessmentCount, 1);
      expect(localBridge.notifications.single.title, '📡 No network');
    },
  );

  test(
    'launch at startup reflects and updates the system registration',
    () async {
      bridge.launchAtStartup = true;
      await controller.initialize();

      expect(controller.launchAtStartupSupported, isTrue);
      expect(controller.launchAtStartupEnabled, isTrue);

      await controller.setLaunchAtStartupEnabled(false);

      expect(controller.launchAtStartupEnabled, isFalse);
      expect(bridge.launchAtStartup, isFalse);
      expect(bridge.launchAtStartupUpdateCount, 1);
    },
  );

  test('refreshes launch-at-startup state when the app resumes', () async {
    await controller.initialize();
    expect(controller.launchAtStartupEnabled, isFalse);

    bridge.launchAtStartup = true;
    await controller.handleAppResumed();

    expect(controller.launchAtStartupEnabled, isTrue);
  });

  test('refreshes notification permission when the app resumes', () async {
    await controller.initialize();
    expect(
      controller.notificationPermission,
      NotificationPermission.authorized,
    );

    bridge.permission = NotificationPermission.denied;
    await controller.handleAppResumed();

    expect(controller.notificationPermission, NotificationPermission.denied);
  });

  test('discards a website response that spans sleep or app resume', () async {
    final sleepingChecker = _CompleterHealthChecker();
    final localController = MonitorController(
      repository: MemoryMonitorRepository(
        paused: true,
        sites: <SiteMonitor>[_unknownSite()],
      ),
      healthChecker: sleepingChecker,
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    addTearDown(localController.dispose);
    await localController.initialize();

    final check = localController.checkSite('site-1');
    await sleepingChecker.started.future;
    await localController.handleAppResumed();
    sleepingChecker.complete(_result(HealthStatus.down, statusCode: 503));
    await check;

    expect(localController.sites.single.status, HealthStatus.unknown);
    expect(localController.sites.single.history, isEmpty);
  });

  test('coalesces concurrent checks for the same website', () async {
    final blockingChecker = _CompleterHealthChecker();
    final localController = MonitorController(
      repository: MemoryMonitorRepository(
        paused: true,
        sites: <SiteMonitor>[_unknownSite()],
      ),
      healthChecker: blockingChecker,
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    addTearDown(localController.dispose);
    await localController.initialize();

    final first = localController.checkSite('site-1');
    final second = localController.checkSite('site-1');
    await blockingChecker.started.future;

    expect(blockingChecker.checkCount, 1);
    blockingChecker.complete(_result(HealthStatus.up, statusCode: 200));
    await Future.wait(<Future<void>>[first, second]);

    expect(blockingChecker.checkCount, 1);
    expect(localController.sites.single.history, hasLength(1));
  });

  test('discards an in-flight result after the website is disabled', () async {
    final blockingChecker = _CompleterHealthChecker();
    final localBridge = FakeDesktopBridge();
    final localController = MonitorController(
      repository: MemoryMonitorRepository(
        paused: true,
        sites: <SiteMonitor>[_unknownSite()],
      ),
      healthChecker: blockingChecker,
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: localBridge,
      schedulerInterval: const Duration(days: 1),
    );
    addTearDown(localController.dispose);
    await localController.initialize();

    final check = localController.checkSite('site-1');
    await blockingChecker.started.future;
    await localController.setSiteEnabled('site-1', false);
    blockingChecker.complete(_result(HealthStatus.down, statusCode: 503));
    await check;

    expect(localController.sites.single.status, HealthStatus.unknown);
    expect(localController.sites.single.history, isEmpty);
    expect(localBridge.notifications, isEmpty);
  });

  test('does not race app resume with a permission request', () async {
    bridge.permission = NotificationPermission.notDetermined;
    bridge.permissionRequestCompleter = Completer<NotificationPermission>();
    await controller.initialize();

    final request = controller.requestNotifications();
    await Future<void>.delayed(Duration.zero);
    expect(controller.isRequestingNotificationPermission, isTrue);
    expect(bridge.permissionRequestCount, 1);

    await controller.handleAppResumed();
    expect(bridge.permissionCheckCount, 1);

    await controller.requestNotifications();
    expect(bridge.permissionRequestCount, 1);

    bridge.permissionRequestCompleter?.complete(
      NotificationPermission.authorized,
    );
    await request;

    expect(controller.isRequestingNotificationPermission, isFalse);
    expect(
      controller.notificationPermission,
      NotificationPermission.authorized,
    );
  });

  test('resolved favicon is attached and persisted', () async {
    await controller.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.sites.single.faviconUrl,
      'https://example.com/favicon.ico',
    );
    expect(
      repository.state.sites.single.faviconUrl,
      'https://example.com/favicon.ico',
    );
  });

  test('restores history in memory when clearing cannot be saved', () async {
    final existing = _result(HealthStatus.up, statusCode: 200).toRecord();
    final localController = MonitorController(
      repository: _FailingSaveRepository(
        paused: true,
        sites: <SiteMonitor>[
          _unknownSite().copyWith(
            status: HealthStatus.up,
            history: <CheckRecord>[existing],
            lastCheck: existing,
          ),
        ],
      ),
      healthChecker: ScriptedHealthChecker(),
      faviconResolver: FakeFaviconResolver(),
      desktopBridge: FakeDesktopBridge(),
      schedulerInterval: const Duration(days: 1),
    );
    addTearDown(localController.dispose);
    await localController.initialize();

    await localController.clearHistory();

    expect(localController.sites.single.history, hasLength(1));
    expect(localController.errorMessage, startsWith('Could not clear history'));
  });
}

SiteMonitor _unknownSite({String name = 'Example'}) {
  return SiteMonitor(
    id: 'site-1',
    name: name,
    baseUrl: 'https://example.com',
    probeUrl: null,
    faviconUrl: null,
    intervalSeconds: 60,
    enabled: true,
    status: HealthStatus.unknown,
    createdAt: DateTime.utc(2026, 1, 1),
    history: const <CheckRecord>[],
  );
}

HealthCheckResult _result(
  HealthStatus status, {
  int? statusCode,
  String? error,
  String? failureDetail,
}) {
  return HealthCheckResult(
    status: status,
    checkedAt: DateTime.utc(
      2026,
      1,
      1,
    ).add(Duration(seconds: _resultSequence++)),
    responseTimeMs: 25,
    statusCode: statusCode,
    error: error,
    failureDetail: failureDetail,
    checkedUrl: 'https://example.com/health',
  );
}

var _resultSequence = 0;

class _CompleterHealthChecker implements HealthChecker {
  final Completer<void> started = Completer<void>();
  final Completer<HealthCheckResult> _result = Completer<HealthCheckResult>();
  int checkCount = 0;

  @override
  Future<HealthCheckResult> check(Uri baseUri, {Uri? preferredProbe}) {
    checkCount += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    return _result.future;
  }

  void complete(HealthCheckResult result) => _result.complete(result);

  @override
  void close() {}
}

class _FailingSaveRepository extends MemoryMonitorRepository {
  _FailingSaveRepository({required super.sites, required super.paused});

  @override
  Future<void> save(PersistedMonitorState state) {
    throw StateError('disk unavailable');
  }
}
