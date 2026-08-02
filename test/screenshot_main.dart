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

import 'support/demo_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const themeName = String.fromEnvironment(
    'SCREENSHOT_THEME',
    defaultValue: 'dark',
  );
  const viewportName = String.fromEnvironment(
    'SCREENSHOT_VIEWPORT',
    defaultValue: 'desktop',
  );
  final themePreference = themeName == 'light'
      ? AppThemePreference.light
      : AppThemePreference.dark;
  if (!kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
    final size = switch (viewportName) {
      'phone' => const Size(430, 932),
      'tablet' => const Size(834, 1112),
      _ => const Size(1440, 900),
    };
    await windowManager.ensureInitialized();
    unawaited(
      windowManager.waitUntilReadyToShow(
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
      ),
    );
  }
  final controller = await createDemoMonitorController(
    themePreference: themePreference,
  );
  runApp(_ScreenshotCapture(controller: controller, themeName: themeName));
}

class _ScreenshotCapture extends StatefulWidget {
  const _ScreenshotCapture({required this.controller, required this.themeName});

  final MonitorController controller;
  final String themeName;

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
      // Let fonts, icons, desktop window sizing, and the first route settle.
      await Future<void>.delayed(const Duration(seconds: 2));
      await WidgetsBinding.instance.endOfFrame;

      final context = _boundaryKey.currentContext;
      if (context == null) {
        throw StateError('Screenshot boundary is not mounted.');
      }
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
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

      final outputFile = await _outputFile(widget.themeName);
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

  Future<File> _outputFile(String themeName) async {
    const requestedPath = String.fromEnvironment('SCREENSHOT_OUTPUT');
    if (requestedPath.isNotEmpty) {
      return File(requestedPath);
    }
    final temporaryDirectory = await getTemporaryDirectory();
    final platformName = Platform.isAndroid ? 'android' : 'macos';
    return File(
      path.join(
        temporaryDirectory.path,
        'sitesignal-$platformName-$themeName.png',
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
      ),
    );
  }
}
