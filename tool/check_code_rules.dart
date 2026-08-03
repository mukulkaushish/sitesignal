import 'dart:io';
import 'dart:typed_data';

final _forceUnwrapPattern = RegExp(
  r'[A-Za-z0-9_\)\]]!(?!=)\s*(?:[.\[\),;?:+\-*/%<>&|^~]|$)',
);
final _kotlinForceUnwrapPattern = RegExp(r'!!');
final _pinnedActionPattern = RegExp(r'^[^@\s]+@[0-9a-fA-F]{40}$');
final _pinnedDockerPattern = RegExp(
  r'^docker://[^@\s]+@sha256:[0-9a-fA-F]{64}$',
);

const _requiredScreenshots = <String, ({int minWidth, int minHeight})>{
  'docs/screenshots/macos-overview-light.png': (
    minWidth: 2000,
    minHeight: 1000,
  ),
  'docs/screenshots/macos-history-light.png': (minWidth: 2000, minHeight: 1000),
  'docs/screenshots/macos-settings-light.png': (
    minWidth: 2000,
    minHeight: 1000,
  ),
  'docs/screenshots/android-overview-light.png': (
    minWidth: 1000,
    minHeight: 2000,
  ),
  'docs/screenshots/android-history-light.png': (
    minWidth: 1000,
    minHeight: 2000,
  ),
  'docs/screenshots/android-settings-light.png': (
    minWidth: 1000,
    minHeight: 2000,
  ),
};

const _pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
const _videoExtensions = <String>{
  '.avi',
  '.gif',
  '.m4v',
  '.mkv',
  '.mov',
  '.mp4',
  '.webm',
};

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

  await _checkPinnedWorkflowUses(violations);
  _checkRepositoryScreenshots(violations);
  await _checkTrackedRepositoryMedia(violations);

  if (violations.isEmpty) {
    stdout.writeln(
      'Code rules passed: source, metadata, workflows, and repository media are consistent.',
    );
    return;
  }
  stderr.writeln('Project code and metadata rules failed:');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}

Future<void> _checkPinnedWorkflowUses(List<String> violations) async {
  final workflowDirectory = Directory('.github/workflows');
  if (!workflowDirectory.existsSync()) {
    violations.add(
      '.github/workflows: required workflow directory is missing.',
    );
    return;
  }
  final workflowFiles =
      workflowDirectory
          .listSync(followLinks: false)
          .whereType<File>()
          .where(
            (file) => file.path.endsWith('.yml') || file.path.endsWith('.yaml'),
          )
          .toList(growable: false)
        ..sort((first, second) => first.path.compareTo(second.path));
  for (final file in workflowFiles) {
    final lines = await file.readAsLines();
    for (var index = 0; index < lines.length; index += 1) {
      var content = lines[index].trimLeft();
      if (content.startsWith('-')) {
        content = content.substring(1).trimLeft();
      }
      if (!content.startsWith('uses:')) {
        continue;
      }
      var reference = content.substring('uses:'.length).trim();
      final commentIndex = reference.indexOf(RegExp(r'\s+#'));
      if (commentIndex >= 0) {
        reference = reference.substring(0, commentIndex).trimRight();
      }
      if (reference.length >= 2 &&
          ((reference.startsWith("'") && reference.endsWith("'")) ||
              (reference.startsWith('"') && reference.endsWith('"')))) {
        reference = reference.substring(1, reference.length - 1);
      }
      if (reference.startsWith('./')) {
        continue;
      }
      final correctlyPinned = reference.startsWith('docker://')
          ? _pinnedDockerPattern.hasMatch(reference)
          : _pinnedActionPattern.hasMatch(reference);
      if (!correctlyPinned) {
        violations.add(
          '${file.path}:${index + 1}: external uses `$reference` must be pinned '
          'to a full commit SHA (or Docker sha256 digest).',
        );
      }
    }
  }
}

void _checkRepositoryScreenshots(List<String> violations) {
  for (final entry in _requiredScreenshots.entries) {
    final file = File(entry.key);
    if (!file.existsSync()) {
      violations.add(
        '${entry.key}: required light-mode screenshot is missing.',
      );
      continue;
    }
    final bytes = file.readAsBytesSync();
    if (bytes.length < 24 || !_startsWith(bytes, _pngSignature)) {
      violations.add(
        '${entry.key}: screenshot must have a valid PNG signature.',
      );
      continue;
    }
    if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
      violations.add('${entry.key}: PNG must start with an IHDR chunk.');
      continue;
    }
    final data = ByteData.sublistView(bytes);
    final width = data.getUint32(16, Endian.big);
    final height = data.getUint32(20, Endian.big);
    final minimum = entry.value;
    if (width < minimum.minWidth || height < minimum.minHeight) {
      violations.add(
        '${entry.key}: ${width}x$height is below the required '
        '${minimum.minWidth}x${minimum.minHeight}.',
      );
    }
  }
}

Future<void> _checkTrackedRepositoryMedia(List<String> violations) async {
  final result = await Process.run('git', const <String>['ls-files', '-z']);
  if (result.exitCode != 0) {
    violations.add('git ls-files: could not inspect tracked repository media.');
    return;
  }
  for (final rawPath in (result.stdout as String).split('\u0000')) {
    final filePath = rawPath.replaceAll('\\', '/');
    if (filePath.isEmpty) {
      continue;
    }
    final lowerPath = filePath.toLowerCase();
    final dotIndex = lowerPath.lastIndexOf('.');
    final extension = dotIndex < 0 ? '' : lowerPath.substring(dotIndex);
    if (_videoExtensions.contains(extension)) {
      violations.add(
        '$filePath: tracked video or animation media is not allowed.',
      );
    }
    if (lowerPath.startsWith('docs/screenshots/') &&
        lowerPath.contains('dark') &&
        const <String>{'.png', '.jpg', '.jpeg', '.webp'}.contains(extension)) {
      violations.add(
        '$filePath: only light-mode repository screenshots are allowed.',
      );
    }
  }
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index += 1) {
    if (bytes[index] != prefix[index]) {
      return false;
    }
  }
  return true;
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
