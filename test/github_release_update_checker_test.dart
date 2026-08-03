import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_signal/features/updates/data/github_release_update_checker.dart';

void main() {
  test('recommends a newer stable GitHub release', () async {
    late http.Request capturedRequest;
    final checker = GitHubReleaseUpdateChecker(
      installedVersion: '1.9.9',
      client: MockClient((request) async {
        capturedRequest = request;
        return _releaseResponse(tagName: 'v2.0.0');
      }),
    );

    final update = await checker.checkForUpdate();

    expect(update?.version, '2.0.0');
    expect(
      update?.releaseUrl,
      'https://github.com/mukulkaushish/sitesignal/releases/tag/v2.0.0',
    );
    expect(
      capturedRequest.url.toString(),
      'https://api.github.com/repos/mukulkaushish/sitesignal/releases/latest',
    );
    expect(capturedRequest.headers['accept'], 'application/vnd.github+json');
  });

  test('does not recommend the installed or an older release', () async {
    for (final tagName in <String>['v1.0.1', 'v1.0.0']) {
      final checker = GitHubReleaseUpdateChecker(
        installedVersion: '1.0.1',
        client: MockClient((_) async => _releaseResponse(tagName: tagName)),
      );

      expect(await checker.checkForUpdate(), isNull);
    }
  });

  test('defensively ignores drafts and prereleases', () async {
    for (final flags in <(bool, bool)>[(true, false), (false, true)]) {
      final checker = GitHubReleaseUpdateChecker(
        installedVersion: '1.0.0',
        client: MockClient(
          (_) async => _releaseResponse(
            tagName: 'v2.0.0',
            draft: flags.$1,
            prerelease: flags.$2,
          ),
        ),
      );

      expect(await checker.checkForUpdate(), isNull);
    }
  });

  test('reports malformed and failed GitHub responses', () async {
    final malformed = GitHubReleaseUpdateChecker(
      installedVersion: '1.0.0',
      client: MockClient((_) async => http.Response('not json', 200)),
    );
    final unavailable = GitHubReleaseUpdateChecker(
      installedVersion: '1.0.0',
      client: MockClient((_) async => http.Response('', 503)),
    );

    await expectLater(
      malformed.checkForUpdate(),
      throwsA(isA<UpdateCheckException>()),
    );
    await expectLater(
      unavailable.checkForUpdate(),
      throwsA(
        isA<UpdateCheckException>().having(
          (error) => error.message,
          'message',
          contains('HTTP 503'),
        ),
      ),
    );
  });
}

http.Response _releaseResponse({
  required String tagName,
  bool draft = false,
  bool prerelease = false,
}) {
  return http.Response(
    jsonEncode(<String, Object?>{
      'tag_name': tagName,
      'draft': draft,
      'prerelease': prerelease,
    }),
    200,
  );
}
