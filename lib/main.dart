import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:site_signal/app/site_signal_app.dart';
import 'package:site_signal/core/platform/package_info_extensions.dart';
import 'package:site_signal/features/monitoring/data/desktop_app_bridge.dart';
import 'package:site_signal/features/monitoring/data/http_favicon_resolver.dart';
import 'package:site_signal/features/monitoring/data/http_health_checker.dart';
import 'package:site_signal/features/monitoring/data/http_internet_connectivity_checker.dart';
import 'package:site_signal/features/monitoring/data/mobile_background_monitor.dart';
import 'package:site_signal/features/monitoring/data/sqlite_monitor_repository.dart';
import 'package:site_signal/features/monitoring/domain/repositories/monitor_repository.dart';
import 'package:site_signal/features/monitoring/domain/services/background_monitor.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';
import 'package:site_signal/features/updates/data/github_release_update_checker.dart';
import 'package:site_signal/features/updates/domain/services/update_checker.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final isDesktop =
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
  if (isDesktop) {
    try {
      await windowManager.ensureInitialized();
      unawaited(
        windowManager
            .waitUntilReadyToShow(
              const WindowOptions(
                size: Size(1080, 720),
                minimumSize: Size(760, 560),
                center: true,
                skipTaskbar: false,
                title: 'SiteSignal',
              ),
              () async {
                await windowManager.show();
                await windowManager.focus();
              },
            )
            .onError((Object error, StackTrace stackTrace) {
              debugPrint('Could not prepare the desktop window: $error');
            }),
      );
    } on Object catch (error) {
      // Flutter's runner may still provide a usable default window. Starting
      // the app is safer than turning an optional sizing failure into a crash.
      debugPrint('Could not initialize desktop window controls: $error');
    }
  }

  var applicationVersion = 'Version unavailable';
  UpdateChecker updateChecker = const DisabledUpdateChecker();
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    applicationVersion = packageInfo.displayVersion;
    updateChecker = GitHubReleaseUpdateChecker(
      installedVersion: packageInfo.version,
    );
  } on Object catch (error) {
    debugPrint('Could not read application version: $error');
  }

  final repository = SqliteMonitorRepository();
  PersistedMonitorState? initialState;
  try {
    initialState = await repository.load();
  } on Object catch (error) {
    debugPrint('Could not preload saved appearance: $error');
  }

  final controller = MonitorController(
    repository: repository,
    healthChecker: HttpHealthChecker(),
    faviconResolver: HttpFaviconResolver(),
    desktopBridge: DesktopAppBridge(),
    internetConnectivityChecker: HttpInternetConnectivityChecker(),
    updateChecker: updateChecker,
    backgroundMonitor: !kIsWeb && (Platform.isAndroid || Platform.isIOS)
        ? MobileBackgroundMonitor()
        : const UnsupportedBackgroundMonitor(),
    initialState: initialState,
  );

  runApp(
    SiteSignalApp(
      controller: controller,
      applicationVersion: applicationVersion,
    ),
  );
  unawaited(controller.initialize());
}
