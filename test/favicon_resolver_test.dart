import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_signal/features/monitoring/data/http_favicon_resolver.dart';

void main() {
  test('discovers a favicon declared by the base page', () async {
    final requested = <String>[];
    final resolver = HttpFaviconResolver(
      client: MockClient((request) async {
        requested.add(request.url.toString());
        if (request.url.path.isEmpty) {
          return http.Response(
            '<html><head><link rel="shortcut icon" '
            'href="/assets/site.png"></head></html>',
            200,
            headers: const <String, String>{'content-type': 'text/html'},
          );
        }
        if (request.url.path == '/assets/site.png') {
          return http.Response(
            'image-bytes',
            200,
            headers: const <String, String>{'content-type': 'image/png'},
          );
        }
        return http.Response('', 404);
      }),
    );

    final result = await resolver.resolve(Uri.parse('https://example.com'));

    expect(result, Uri.parse('https://example.com/assets/site.png'));
    expect(requested, <String>[
      'https://example.com',
      'https://example.com/assets/site.png',
    ]);
  });

  test('falls back to the conventional favicon path', () async {
    final resolver = HttpFaviconResolver(
      client: MockClient((request) async {
        if (request.url.path.isEmpty) {
          return http.Response(
            '<html><head><title>Example</title></head></html>',
            200,
            headers: const <String, String>{'content-type': 'text/html'},
          );
        }
        return http.Response(
          'icon',
          200,
          headers: const <String, String>{'content-type': 'image/x-icon'},
        );
      }),
    );

    final result = await resolver.resolve(Uri.parse('https://example.com'));

    expect(result, Uri.parse('https://example.com/favicon.ico'));
  });

  test('returns null so the UI can display its default icon', () async {
    final resolver = HttpFaviconResolver(
      client: MockClient((_) async => http.Response('', 404)),
    );

    final result = await resolver.resolve(Uri.parse('https://example.com'));

    expect(result, isNull);
  });

  test('does not mistake an HTML catch-all page for a favicon', () async {
    final resolver = HttpFaviconResolver(
      client: MockClient(
        (_) async => http.Response(
          '<!doctype html><html><title>App</title></html>',
          200,
          headers: const <String, String>{'content-type': 'text/html'},
        ),
      ),
    );

    final result = await resolver.resolve(Uri.parse('https://example.com'));

    expect(result, isNull);
  });

  test(
    'rejects SVG icons that the raster image widget cannot decode',
    () async {
      final resolver = HttpFaviconResolver(
        client: MockClient((request) async {
          if (request.url.path.isEmpty) {
            return http.Response(
              '<html><head><link rel="icon" href="/icon.svg"></head></html>',
              200,
              headers: const <String, String>{'content-type': 'text/html'},
            );
          }
          if (request.url.path == '/icon.svg') {
            return http.Response(
              '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
              200,
              headers: const <String, String>{'content-type': 'image/svg+xml'},
            );
          }
          return http.Response('', 404);
        }),
      );

      final result = await resolver.resolve(Uri.parse('https://example.com'));

      expect(result, isNull);
    },
  );
}
