import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_signal/features/updates/domain/entities/app_update.dart';
import 'package:site_signal/features/updates/domain/services/update_checker.dart';

final class GitHubReleaseUpdateChecker implements UpdateChecker {
  GitHubReleaseUpdateChecker({
    required String installedVersion,
    http.Client? client,
    this.timeout = const Duration(seconds: 5),
  }) : _installedVersion = _SemanticVersion.tryParse(installedVersion),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  static final Uri _latestReleaseEndpoint = Uri.https(
    'api.github.com',
    '/repos/mukulkaushish/sitesignal/releases/latest',
  );

  final _SemanticVersion? _installedVersion;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  @override
  Future<AppUpdate?> checkForUpdate() async {
    final installedVersion = _installedVersion;
    if (installedVersion == null) {
      throw const UpdateCheckException(
        'The installed SiteSignal version could not be read.',
      );
    }

    late http.Response response;
    try {
      response = await _client
          .get(
            _latestReleaseEndpoint,
            headers: const <String, String>{
              'Accept': 'application/vnd.github+json',
              'Cache-Control': 'no-cache',
              'User-Agent': 'SiteSignal update-checker',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const UpdateCheckException('The update check timed out.');
    } on Object {
      throw const UpdateCheckException(
        'SiteSignal could not reach GitHub Releases.',
      );
    }

    if (response.statusCode != 200) {
      throw UpdateCheckException(
        'GitHub Releases returned HTTP ${response.statusCode}.',
      );
    }

    final Object? payload;
    try {
      payload = jsonDecode(response.body);
    } on FormatException {
      throw const UpdateCheckException(
        'GitHub Releases returned an unreadable response.',
      );
    }
    if (payload is! Map<String, Object?> ||
        payload['draft'] == true ||
        payload['prerelease'] == true) {
      return null;
    }

    final tagName = payload['tag_name'];
    final latestVersion = tagName is String
        ? _SemanticVersion.tryParse(tagName)
        : null;
    if (latestVersion == null) {
      throw const UpdateCheckException(
        'The latest release has an unsupported version number.',
      );
    }
    if (latestVersion.compareTo(installedVersion) <= 0) {
      return null;
    }

    return AppUpdate(
      version: latestVersion.toString(),
      releaseUrl:
          'https://github.com/mukulkaushish/sitesignal/releases/tag/$tagName',
    );
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

final class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(this.major, this.minor, this.patch);

  static final RegExp _pattern = RegExp(
    r'^[vV]?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$',
  );

  final int major;
  final int minor;
  final int patch;

  static _SemanticVersion? tryParse(String value) {
    final match = _pattern.firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final major = match.group(1);
    final minor = match.group(2);
    final patch = match.group(3);
    if (major == null || minor == null || patch == null) {
      return null;
    }
    try {
      return _SemanticVersion(
        int.parse(major),
        int.parse(minor),
        int.parse(patch),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  int compareTo(_SemanticVersion other) {
    final majorComparison = major.compareTo(other.major);
    if (majorComparison != 0) {
      return majorComparison;
    }
    final minorComparison = minor.compareTo(other.minor);
    if (minorComparison != 0) {
      return minorComparison;
    }
    return patch.compareTo(other.patch);
  }

  @override
  String toString() => '$major.$minor.$patch';
}
