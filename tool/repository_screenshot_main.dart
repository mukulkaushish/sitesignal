import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:site_signal/app/site_signal_app.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/demo_app.dart';

final _screenshotReferenceTime = DateTime.utc(2026, 8, 3, 12);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const pageName = String.fromEnvironment(
    'SCREENSHOT_PAGE',
    defaultValue: 'overview',
  );
  final section = switch (pageName) {
    'overview' => DashboardSection.overview,
    'history' => DashboardSection.history,
    'settings' => DashboardSection.settings,
    _ => throw ArgumentError.value(pageName, 'SCREENSHOT_PAGE'),
  };
  const viewportName = String.fromEnvironment(
    'SCREENSHOT_VIEWPORT',
    defaultValue: 'desktop',
  );
  if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    final size = switch (viewportName) {
      'phone' => const Size(430, 932),
      'tablet' => const Size(834, 1112),
      _ => const Size(1440, 900),
    };
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: size,
        minimumSize: const Size(320, 480),
        center: true,
        title: 'SiteSignal',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  final controller = await createDemoMonitorController(
    themePreference: AppThemePreference.light,
    referenceTime: _screenshotReferenceTime,
  );
  runApp(
    _ScreenshotCapture(
      controller: controller,
      pageName: pageName,
      section: section,
    ),
  );
}

class _ScreenshotCapture extends StatefulWidget {
  const _ScreenshotCapture({
    required this.controller,
    required this.pageName,
    required this.section,
  });

  final MonitorController controller;
  final String pageName;
  final DashboardSection section;

  @override
  State<_ScreenshotCapture> createState() => _ScreenshotCaptureState();
}

class _ScreenshotCaptureState extends State<_ScreenshotCapture> {
  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_capture());
    });
  }

  Future<void> _capture() async {
    try {
      // Wait for two explicitly scheduled frames, then allow one short bounded
      // delay for native window chrome and platform fonts to finish settling.
      for (var index = 0; index < 2; index += 1) {
        WidgetsBinding.instance.scheduleFrame();
        await WidgetsBinding.instance.endOfFrame;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;

      if (!mounted) {
        throw StateError('Screenshot capture was disposed before rendering.');
      }
      final boundaryContext = _boundaryKey.currentContext;
      if (boundaryContext == null || !boundaryContext.mounted) {
        throw StateError('Screenshot boundary is not mounted.');
      }
      final renderObject = boundaryContext.findRenderObject();
      if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
        throw StateError('Screenshot boundary is not ready.');
      }

      // macOS is supersampled for a sharp repository asset. Android uses this
      // file only as a readiness marker; adb captures the physical display so
      // the final image includes native status and navigation bars.
      final pixelRatio = Platform.isAndroid ? 1.0 : 2.0;
      final image = await renderObject.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) {
        throw StateError('Flutter could not encode the screenshot.');
      }

      final outputFile = await _outputFile(widget.pageName);
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(data.buffer.asUint8List(), flush: true);
      stdout.writeln('SCREENSHOT_SAVED=${outputFile.path}');
      await stdout.flush();
      if (Platform.isAndroid) {
        return;
      }
      exit(0);
    } on Object catch (error, stackTrace) {
      stderr
        ..writeln('SCREENSHOT_FAILED=$error')
        ..writeln(stackTrace);
      await stderr.flush();
      exit(1);
    }
  }

  Future<File> _outputFile(String pageName) async {
    const requestedPath = String.fromEnvironment('SCREENSHOT_OUTPUT');
    if (requestedPath.isNotEmpty) {
      return File(requestedPath);
    }
    final temporaryDirectory = await getTemporaryDirectory();
    final platformName = Platform.isAndroid ? 'android' : 'macos';
    return File(
      path.join(
        temporaryDirectory.path,
        'sitesignal-$platformName-$pageName-light.png',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: SiteSignalApp(
        controller: widget.controller,
        applicationVersion: '1.0.0',
        initialSection: widget.section,
      ),
    );
  }
}
