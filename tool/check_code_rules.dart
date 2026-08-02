import 'dart:io';

final _forceUnwrapPattern = RegExp(
  r'[A-Za-z0-9_\)\]]!(?!=)\s*(?:[.\[\),;?:+\-*/%<>&|^~]|$)',
);
final _kotlinForceUnwrapPattern = RegExp(r'!!');

extension _ProjectSourceFile on File {
  bool get isCheckedSource {
    final components = path.split(Platform.pathSeparator);
    const excludedDirectories = <String>{
      '.dart_tool',
      '.gradle',
      '.symlinks',
      'Pods',
      'build',
    };
    if (components.any(excludedDirectories.contains)) {
      return false;
    }
    return path.endsWith('.dart') ||
        path.endsWith('.kt') ||
        path.endsWith('.swift');
  }
}

Future<void> main() async {
  final violations = <String>[];
  for (final root in const <String>[
    'lib',
    'test',
    'tool',
    'android',
    'ios',
    'macos',
  ]) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      continue;
    }
    final files =
        directory
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((file) => file.isCheckedSource)
            .toList(growable: false)
          ..sort((first, second) => first.path.compareTo(second.path));
    for (final file in files) {
      final lines = await file.readAsLines();
      for (var index = 0; index < lines.length; index += 1) {
        final line = lines[index];
        final violates = file.path.endsWith('.kt')
            ? _kotlinForceUnwrapPattern.hasMatch(line)
            : _forceUnwrapPattern.hasMatch(line);
        if (violates) {
          violations.add('${file.path}:${index + 1}: ${lines[index].trim()}');
        }
      }
    }
  }

  final pubspec = await File('pubspec.yaml').readAsString();
  final flutterVersion = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  final msixVersion = RegExp(
    r'^\s*msix_version:\s*(\d+)\.(\d+)\.(\d+)\.(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (flutterVersion == null || msixVersion == null) {
    violations.add(
      'pubspec.yaml: Flutter and MSIX versions must both use numeric release metadata.',
    );
  } else {
    final expectedMsix = <String>[
      for (var index = 1; index <= 4; index += 1)
        flutterVersion.group(index) ?? '',
    ].join('.');
    final actualMsix = <String>[
      for (var index = 1; index <= 4; index += 1)
        msixVersion.group(index) ?? '',
    ].join('.');
    if (actualMsix != expectedMsix) {
      violations.add(
        'pubspec.yaml: msix_version $actualMsix must match app version $expectedMsix.',
      );
    }
  }

  const expectedContent = <String, List<String>>{
    'pubspec.yaml': <String>[
      'display_name: SiteSignal',
      'identity_name: dev.sitesignal.app',
      'logo_path: assets/app_icon.png',
    ],
    'android/app/build.gradle.kts': <String>[
      'namespace = "dev.sitesignal.app"',
      'applicationId = "dev.sitesignal.app"',
    ],
    'android/app/src/main/AndroidManifest.xml': <String>[
      'android:label="SiteSignal"',
      'android:icon="@mipmap/ic_launcher"',
      'android:roundIcon="@mipmap/ic_launcher"',
    ],
    'ios/Runner.xcodeproj/project.pbxproj': <String>[
      'PRODUCT_BUNDLE_IDENTIFIER = dev.sitesignal.app;',
    ],
    'macos/Runner/Configs/AppInfo.xcconfig': <String>[
      'PRODUCT_NAME = SiteSignal',
      'PRODUCT_BUNDLE_IDENTIFIER = dev.sitesignal.app',
    ],
    'linux/CMakeLists.txt': <String>[
      'set(BINARY_NAME "site_signal")',
      'set(APPLICATION_ID "dev.sitesignal.app")',
    ],
    'windows/runner/Runner.rc': <String>['VALUE "ProductName", "SiteSignal"'],
    'web/manifest.json': <String>[
      '"name": "SiteSignal"',
      '"theme_color": "#2563EB"',
    ],
    'lib/core/theme/app_accent_color.dart': <String>[
      'static const int defaultValue = 0xFF2563EB;',
    ],
    'tool/generate_tray_icons.swift': <String>[
      'calibratedRed: 0.145, green: 0.388, blue: 0.922',
    ],
  };
  for (final entry in expectedContent.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      violations.add(
        '${entry.key}: required project metadata file is missing.',
      );
      continue;
    }
    final content = await file.readAsString();
    for (final expected in entry.value) {
      if (!content.contains(expected)) {
        violations.add(
          '${entry.key}: expected canonical metadata `$expected`.',
        );
      }
    }
  }

  const requiredAssets = <String>[
    'assets/app_icon.png',
    'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
    'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
    'windows/runner/resources/app_icon.ico',
    'web/icons/Icon-512.png',
  ];
  for (final assetPath in requiredAssets) {
    if (!File(assetPath).existsSync()) {
      violations.add(
        '$assetPath: required generated or licensed asset missing.',
      );
    }
  }

  for (final soundName in const <String>[
    'site_signal_alert.wav',
    'site_signal_bright_chime.wav',
    'site_signal_soft_pulse.wav',
    'site_signal_beacon.wav',
  ]) {
    final flutterSound = File('assets/$soundName');
    final androidSound = File('android/app/src/main/res/raw/$soundName');
    if (!flutterSound.existsSync() || !androidSound.existsSync()) {
      violations.add(
        '$soundName: Flutter and Android sound copies are required.',
      );
      continue;
    }
    if (!_sameBytes(
      flutterSound.readAsBytesSync(),
      androidSound.readAsBytesSync(),
    )) {
      violations.add('$soundName: Flutter and Android copies have drifted.');
    }
  }

  if (violations.isEmpty) {
    stdout.writeln(
      'Code rules passed: null safety, metadata, and generated assets are consistent.',
    );
    return;
  }
  stderr.writeln('Project code and metadata rules failed:');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}

bool _sameBytes(List<int> first, List<int> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}
