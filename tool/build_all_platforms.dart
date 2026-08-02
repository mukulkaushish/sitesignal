import 'dart:io';

import 'package:path/path.dart' as path;

const _supportedTargets = <String>{
  'all',
  'android',
  'linux',
  'macos',
  'windows',
};

Future<void> main(List<String> arguments) async {
  try {
    final options = _BuildOptions.parse(arguments);
    if (options.showHelp) {
      stdout.write(_usage);
      return;
    }

    final script = File.fromUri(Platform.script).absolute;
    final projectDirectory = script.parent.parent.path;
    final builder = _ReleaseBuilder(
      projectDirectory: projectDirectory,
      options: options,
    );
    await builder.build();
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    stderr.write(_usage);
    exitCode = 64;
  } on _BuildException catch (error) {
    stderr.writeln('\nBuild failed: ${error.message}');
    exitCode = 1;
  }
}

class _BuildOptions {
  const _BuildOptions({
    required this.target,
    required this.architecture,
    required this.skipPubGet,
    required this.showHelp,
  });

  final String target;
  final String architecture;
  final bool skipPubGet;
  final bool showHelp;

  static _BuildOptions parse(List<String> arguments) {
    var target = 'all';
    var architecture = 'all';
    var skipPubGet = false;
    var showHelp = false;

    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      if (argument == '--help' || argument == '-h') {
        showHelp = true;
      } else if (argument == '--skip-pub-get') {
        skipPubGet = true;
      } else if (argument == '--target') {
        if (index + 1 >= arguments.length) {
          throw const _UsageException('--target requires a value.');
        }
        target = arguments[index += 1];
      } else if (argument.startsWith('--target=')) {
        target = argument.substring('--target='.length);
      } else if (argument == '--arch') {
        if (index + 1 >= arguments.length) {
          throw const _UsageException('--arch requires a value.');
        }
        architecture = arguments[index += 1];
      } else if (argument.startsWith('--arch=')) {
        architecture = argument.substring('--arch='.length);
      } else {
        throw _UsageException('Unknown argument: $argument');
      }
    }

    target = _normalizeTarget(target);
    architecture = _normalizeArchitecture(architecture);
    if (!_supportedTargets.contains(target)) {
      throw _UsageException('Unsupported target: $target');
    }

    return _BuildOptions(
      target: target,
      architecture: architecture,
      skipPubGet: skipPubGet,
      showHelp: showHelp,
    );
  }
}

class _ReleaseBuilder {
  _ReleaseBuilder({required this.projectDirectory, required this.options});

  final String projectDirectory;
  final _BuildOptions options;
  final List<String> _artifacts = <String>[];

  late final String hostArchitecture = _readHostArchitecture();

  Future<void> build() async {
    final pubspec = File(path.join(projectDirectory, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      throw _BuildException(
        'Could not find pubspec.yaml at $projectDirectory.',
      );
    }

    final targets = options.target == 'all'
        ? _targetsForCurrentHost()
        : <String>[options.target];

    stdout.writeln(
      'Building ${targets.join(', ')} on '
      '${Platform.operatingSystem} $hostArchitecture.',
    );
    if (options.target == 'all') {
      _printNativeTargetNotice();
    }

    if (!options.skipPubGet) {
      await _run('flutter', const <String>['pub', 'get']);
    }

    for (final target in targets) {
      switch (target) {
        case 'android':
          await _buildAndroid();
        case 'linux':
          await _buildLinux();
        case 'macos':
          await _buildMacos();
        case 'windows':
          await _buildWindows();
      }
    }

    stdout.writeln('\nRelease build complete.');
    for (final artifact in _artifacts) {
      stdout.writeln('  ${path.relative(artifact, from: projectDirectory)}');
    }
  }

  List<String> _targetsForCurrentHost() {
    if (Platform.isMacOS) {
      return const <String>['macos', 'android'];
    }
    if (Platform.isLinux) {
      return const <String>['linux', 'android'];
    }
    if (Platform.isWindows) {
      return const <String>['windows', 'android'];
    }
    throw _BuildException(
      'Unsupported build host: ${Platform.operatingSystem}.',
    );
  }

  void _printNativeTargetNotice() {
    if (Platform.isMacOS) {
      stdout.writeln(
        'Linux and Windows desktop releases require matching native runners; '
        'the CI matrix builds those architectures.',
      );
    } else if (Platform.isLinux) {
      stdout.writeln(
        'macOS and Windows releases require native runners; the CI '
        'matrix builds them.',
      );
    } else if (Platform.isWindows) {
      stdout.writeln(
        'macOS and Linux releases require native runners; the CI '
        'matrix builds them.',
      );
    }
  }

  Future<void> _buildMacos() async {
    _requireHost(Platform.isMacOS, 'macOS');
    final architecture = _macosArchitecture();
    await _run('/bin/sh', <String>[
      path.join(projectDirectory, 'tool', 'package_macos_minimal.sh'),
      architecture,
    ]);

    final architectures = architecture == 'all'
        ? const <String>['arm64', 'x86_64']
        : <String>[architecture];
    for (final item in architectures) {
      _recordArtifact(
        path.join(
          projectDirectory,
          'build',
          'distributions',
          'macos',
          item,
          'SiteSignal-macos-$item.zip',
        ),
      );
    }
  }

  Future<void> _buildLinux() async {
    _requireHost(Platform.isLinux, 'Linux');
    final architecture = _nativeDesktopArchitecture('Linux');
    await _run('/bin/sh', <String>[
      path.join(projectDirectory, 'tool', 'package_linux_release.sh'),
      architecture,
    ]);
    _recordArtifact(
      path.join(
        projectDirectory,
        'build',
        'distributions',
        'linux',
        architecture,
        'SiteSignal-linux-$architecture.tar.gz',
      ),
    );
  }

  Future<void> _buildWindows() async {
    _requireHost(Platform.isWindows, 'Windows');
    final architecture = _nativeDesktopArchitecture('Windows');
    final flutterArchitecture = architecture == 'x86_64' ? 'x64' : 'arm64';
    await _run('powershell.exe', <String>[
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      path.join(projectDirectory, 'tool', 'package_windows_release.ps1'),
      '-Architecture',
      flutterArchitecture,
    ]);
    final outputDirectory = path.join(
      projectDirectory,
      'build',
      'distributions',
      'windows',
      architecture,
    );
    _recordArtifact(
      path.join(outputDirectory, 'SiteSignal-windows-$architecture.zip'),
    );
    _recordArtifact(
      path.join(outputDirectory, 'SiteSignal-windows-$architecture.msix'),
    );
  }

  Future<void> _buildAndroid() async {
    final architectures = _androidArchitectures();
    final flutterArguments = <String>[
      'build',
      'apk',
      '--release',
      '--split-per-abi',
      '--split-debug-info=${path.join(projectDirectory, 'build', 'debug-symbols', 'android')}',
    ];
    if (architectures.length == 1) {
      flutterArguments.add(
        '--target-platform=${architectures.single.flutterTarget}',
      );
    }
    await _run('flutter', flutterArguments);

    for (final architecture in architectures) {
      final source = File(
        path.join(
          projectDirectory,
          'build',
          'app',
          'outputs',
          'flutter-apk',
          architecture.flutterOutput,
        ),
      );
      if (!source.existsSync()) {
        throw _BuildException('Missing Android APK: ${source.path}');
      }
      final outputDirectory = Directory(
        path.join(
          projectDirectory,
          'build',
          'distributions',
          'android',
          architecture.name,
        ),
      )..createSync(recursive: true);
      final output = path.join(
        outputDirectory.path,
        'SiteSignal-android-${architecture.artifactName}.apk',
      );
      final oldOutput = File(output);
      if (oldOutput.existsSync()) {
        oldOutput.deleteSync();
      }
      await source.copy(output);
      _recordArtifact(output);
    }
  }

  String _macosArchitecture() {
    switch (options.architecture) {
      case 'all':
        return 'all';
      case 'host':
        return hostArchitecture;
      case 'arm64':
      case 'x86_64':
        return options.architecture;
      default:
        throw const _BuildException(
          'macOS architecture must be all, arm64, or x86_64.',
        );
    }
  }

  String _nativeDesktopArchitecture(String target) {
    final requested =
        options.architecture == 'all' || options.architecture == 'host'
        ? hostArchitecture
        : options.architecture;
    if (requested != 'arm64' && requested != 'x86_64') {
      throw _BuildException('$target architecture must be arm64 or x86_64.');
    }
    if (requested != hostArchitecture) {
      throw _BuildException(
        '$target desktop builds must match the host architecture. Requested '
        '$requested on $hostArchitecture.',
      );
    }
    return requested;
  }

  List<_AndroidArchitecture> _androidArchitectures() {
    switch (options.architecture) {
      case 'all':
        return _AndroidArchitecture.values;
      case 'host':
        if (hostArchitecture == 'arm64') {
          return const <_AndroidArchitecture>[_AndroidArchitecture.arm64];
        }
        return const <_AndroidArchitecture>[_AndroidArchitecture.x86_64];
      case 'arm32':
        return const <_AndroidArchitecture>[_AndroidArchitecture.arm32];
      case 'arm64':
        return const <_AndroidArchitecture>[_AndroidArchitecture.arm64];
      case 'x86_64':
        return const <_AndroidArchitecture>[_AndroidArchitecture.x86_64];
      default:
        throw const _BuildException(
          'Android architecture must be all, arm32, arm64, or x86_64.',
        );
    }
  }

  Future<void> _run(String executable, List<String> arguments) async {
    stdout.writeln('\n> ${_displayCommand(executable, arguments)}');
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: projectDirectory,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    final result = await process.exitCode;
    if (result != 0) {
      throw _BuildException(
        '${_displayCommand(executable, arguments)} exited with code $result.',
      );
    }
  }

  void _recordArtifact(String artifact) {
    if (!File(artifact).existsSync()) {
      throw _BuildException('Expected artifact was not created: $artifact');
    }
    _artifacts.add(artifact);
  }

  void _requireHost(bool isSupported, String target) {
    if (!isSupported) {
      throw _BuildException('$target releases require a $target build host.');
    }
  }

  String _readHostArchitecture() {
    String architecture;
    if (Platform.isWindows) {
      architecture =
          Platform.environment['PROCESSOR_ARCHITEW6432'] ??
          Platform.environment['PROCESSOR_ARCHITECTURE'] ??
          '';
    } else {
      final result = Process.runSync('uname', const <String>['-m']);
      if (result.exitCode != 0) {
        throw const _BuildException('Could not determine host architecture.');
      }
      architecture = (result.stdout as String).trim();
    }

    final normalized = _normalizeArchitecture(architecture);
    if (normalized != 'arm64' && normalized != 'x86_64') {
      throw _BuildException('Unsupported host architecture: $architecture');
    }
    return normalized;
  }
}

enum _AndroidArchitecture {
  arm32(
    name: 'arm32',
    artifactName: 'armv7',
    flutterTarget: 'android-arm',
    flutterOutput: 'app-armeabi-v7a-release.apk',
  ),
  arm64(
    name: 'arm64',
    artifactName: 'arm64',
    flutterTarget: 'android-arm64',
    flutterOutput: 'app-arm64-v8a-release.apk',
  ),
  x86_64(
    name: 'x86_64',
    artifactName: 'x86_64',
    flutterTarget: 'android-x64',
    flutterOutput: 'app-x86_64-release.apk',
  );

  const _AndroidArchitecture({
    required this.name,
    required this.artifactName,
    required this.flutterTarget,
    required this.flutterOutput,
  });

  final String name;
  final String artifactName;
  final String flutterTarget;
  final String flutterOutput;
}

String _normalizeTarget(String value) {
  switch (value.trim().toLowerCase()) {
    case 'mac':
    case 'macos':
      return 'macos';
    case 'win':
    case 'windows':
      return 'windows';
    default:
      return value.trim().toLowerCase();
  }
}

String _normalizeArchitecture(String value) {
  switch (value.trim().toLowerCase()) {
    case 'aarch64':
    case 'arm64':
      return 'arm64';
    case 'amd64':
    case 'x64':
    case 'x86_64':
      return 'x86_64';
    case 'arm':
    case 'arm32':
    case 'armv7':
    case 'armeabi-v7a':
      return 'arm32';
    case 'all':
      return 'all';
    case 'host':
      return 'host';
    default:
      throw _UsageException('Unsupported architecture: $value');
  }
}

String _displayCommand(String executable, List<String> arguments) {
  final command = <String>[executable, ...arguments];
  return command
      .map((part) {
        if (!part.contains(RegExp(r'\s')) &&
            !part.contains("'") &&
            !part.contains('"')) {
          return part;
        }
        return "'${part.replaceAll("'", "'\\''")}'";
      })
      .join(' ');
}

class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}

class _BuildException implements Exception {
  const _BuildException(this.message);

  final String message;
}

const _usage = '''
Build and package SiteSignal releases supported by the current host.

Usage:
  dart run tool/build_all_platforms.dart [options]

Options:
  --target <target>  all, android, linux, macos, or windows.
                     Default: all targets supported by the current host.
  --arch <arch>      all, host, arm32, arm64, or x86_64 (x64 is accepted).
                     Default: all; native desktop builds use the host arch.
  --skip-pub-get     Do not run flutter pub get before building.
  -h, --help         Show this help.

Examples:
  dart run tool/build_all_platforms.dart
  dart run tool/build_all_platforms.dart --target macos --arch all
  dart run tool/build_all_platforms.dart --target linux --arch x86_64
  dart run tool/build_all_platforms.dart --target windows --arch arm64

Linux and Windows desktop releases must be built on matching native hosts. The
CI matrix supplies every required native host and invokes this same script for
each platform/architecture. iOS distribution is intentionally disabled.
''';
