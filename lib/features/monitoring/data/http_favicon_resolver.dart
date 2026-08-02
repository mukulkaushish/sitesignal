import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/favicon_resolver.dart';

class HttpFaviconResolver implements FaviconResolver {
  HttpFaviconResolver({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const int _maximumHtmlBytes = 64 * 1024;
  static const int _maximumCandidates = 4;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  @override
  Future<Uri?> resolve(Uri baseUri) async {
    final origin = SiteMonitor.normalizeOrigin(baseUri);
    final candidates = <Uri>[];

    try {
      final html = await _readPageHtml(origin);
      if (html != null) {
        candidates.addAll(_declaredIcons(html, origin));
      }
    } on Object {
      // A missing page response does not rule out a conventional favicon.
    }

    candidates.add(origin.resolve('/favicon.ico'));
    final uniqueCandidates = <String>{};
    for (final candidate in candidates) {
      if (!uniqueCandidates.add(candidate.toString())) {
        continue;
      }
      if (await _isUsableImage(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  Future<String?> _readPageHtml(Uri uri) async {
    final request = http.Request('GET', uri)
      ..followRedirects = true
      ..maxRedirects = 5
      ..headers.addAll(const <String, String>{
        'Accept': 'text/html,application/xhtml+xml',
        'Cache-Control': 'no-cache',
        'User-Agent': 'SiteSignal/1.0 favicon-discovery',
      });
    final response = await _client.send(request).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>().timeout(timeout);
      return null;
    }

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (!contentType.contains('text/html') &&
        !contentType.contains('application/xhtml+xml')) {
      await response.stream.drain<void>().timeout(timeout);
      return null;
    }

    final bytes = await _readBounded(response.stream, _maximumHtmlBytes);
    return utf8.decode(bytes, allowMalformed: true);
  }

  Iterable<Uri> _declaredIcons(String html, Uri pageUri) sync* {
    final linkPattern = RegExp(r'<link\b[^>]*>', caseSensitive: false);
    var yielded = 0;
    for (final match in linkPattern.allMatches(html)) {
      final tag = match.group(0) ?? '';
      final rel = _attribute(tag, 'rel')?.toLowerCase();
      final href = _attribute(tag, 'href');
      if (rel == null ||
          !rel.split(RegExp(r'\s+')).contains('icon') ||
          href == null ||
          href.trim().isEmpty) {
        continue;
      }

      final candidate = pageUri.resolve(href.trim());
      if (candidate.scheme != 'http' && candidate.scheme != 'https') {
        continue;
      }
      yield candidate;
      yielded++;
      if (yielded >= _maximumCandidates) {
        return;
      }
    }
  }

  String? _attribute(String tag, String name) {
    final quoted = RegExp(
      '$name\\s*=\\s*(["\\\'])(.*?)\\1',
      caseSensitive: false,
    ).firstMatch(tag);
    if (quoted != null) {
      return quoted.group(2);
    }
    return RegExp(
      '$name\\s*=\\s*([^\\s>]+)',
      caseSensitive: false,
    ).firstMatch(tag)?.group(1);
  }

  Future<bool> _isUsableImage(Uri uri) async {
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers.addAll(const <String, String>{
          'Accept': 'image/*',
          'Cache-Control': 'no-cache',
          'User-Agent': 'SiteSignal/1.0 favicon-discovery',
        });
      final response = await _client.send(request).timeout(timeout);
      final firstBytes = await _readBounded(response.stream, 32);
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      final healthyStatus =
          response.statusCode >= 200 && response.statusCode < 300;
      final bodyStart = utf8
          .decode(firstBytes, allowMalformed: true)
          .trimLeft()
          .toLowerCase();
      final returnedHtml =
          bodyStart.startsWith('<!doctype html') ||
          bodyStart.startsWith('<html');
      final returnedSvg =
          contentType.contains('image/svg') || bodyStart.startsWith('<svg');
      return healthyStatus &&
          firstBytes.isNotEmpty &&
          !returnedHtml &&
          !returnedSvg &&
          (contentType.startsWith('image/') || _hasImageExtension(uri.path));
    } on Object {
      return false;
    }
  }

  Future<List<int>> _readBounded(
    Stream<List<int>> stream,
    int maximumBytes,
  ) async {
    final bytes = <int>[];
    await for (final chunk in stream.timeout(timeout)) {
      final remaining = maximumBytes - bytes.length;
      if (remaining <= 0) {
        break;
      }
      bytes.addAll(
        chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
      );
      if (bytes.length >= maximumBytes) {
        break;
      }
    }
    return bytes;
  }

  bool _hasImageExtension(String path) {
    final normalized = path.toLowerCase();
    return normalized.endsWith('.ico') ||
        normalized.endsWith('.png') ||
        normalized.endsWith('.jpg') ||
        normalized.endsWith('.jpeg') ||
        normalized.endsWith('.gif') ||
        normalized.endsWith('.webp');
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
