import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:site_signal/features/monitoring/domain/entities/favicon_image.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/favicon_resolver.dart';

class HttpFaviconResolver implements FaviconResolver {
  HttpFaviconResolver({
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static const int _maximumHtmlBytes = 64 * 1024;
  static const int _maximumImageBytes = 256 * 1024;
  static const int _maximumCandidates = 4;
  static const int _maximumRedirects = 5;
  static const int _maximumSourceDimension = 4096;
  static const int _maximumSourcePixels = 16 * 1000 * 1000;
  static const int _maximumOutputDimension = 64;
  static const int _maximumAnimationFrames = 32;
  static const Set<int> _redirectStatusCodes = <int>{301, 302, 303, 307, 308};

  static const Map<String, String> _pageHeaders = <String, String>{
    'Accept': 'text/html,application/xhtml+xml',
    'Cache-Control': 'no-cache',
    'User-Agent': 'SiteSignal/1.0 favicon-discovery',
  };
  static const Map<String, String> _imageHeaders = <String, String>{
    'Accept': 'image/*',
    'Cache-Control': 'no-cache',
    'User-Agent': 'SiteSignal/1.0 favicon-discovery',
  };

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  @override
  Future<FaviconImage?> resolve(Uri baseUri) async {
    final deadline = _ResolutionDeadline(timeout);
    try {
      final origin = SiteMonitor.normalizeOrigin(baseUri);
      return await _resolve(origin, deadline);
    } on Object {
      return null;
    } finally {
      deadline.dispose();
    }
  }

  Future<FaviconImage?> _resolve(
    Uri origin,
    _ResolutionDeadline deadline,
  ) async {
    final candidates = <Uri>[];
    try {
      final page = await _fetchSameOrigin(
        origin: origin,
        initialUri: origin,
        headers: _pageHeaders,
        maximumBodyBytes: _maximumHtmlBytes,
        deadline: deadline,
        acceptsResponse: _isHtmlResponse,
      );
      if (page != null) {
        final html = utf8.decode(page.body, allowMalformed: true);
        candidates.addAll(_declaredIcons(html, page.uri, origin));
      }
    } on Object {
      // A missing page response does not rule out a conventional favicon.
    }

    candidates.add(origin.resolve('/favicon.ico'));
    final uniqueCandidates = <String>{};
    for (final candidate in candidates) {
      if (deadline.expired || !uniqueCandidates.add(candidate.toString())) {
        continue;
      }
      _FetchedResponse? resolved;
      try {
        resolved = await _fetchSameOrigin(
          origin: origin,
          initialUri: candidate,
          headers: _imageHeaders,
          maximumBodyBytes: _maximumImageBytes,
          deadline: deadline,
          acceptsResponse: _isPotentialImageResponse,
        );
      } on Object {
        continue;
      }
      if (resolved == null) {
        continue;
      }
      final favicon = await deadline.guard(_decodeFavicon(resolved.body));
      if (favicon != null) {
        return favicon;
      }
    }
    return null;
  }

  Future<FaviconImage?> _decodeFavicon(Uint8List encodedBytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(encodedBytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final sourceWidth = descriptor.width;
      final sourceHeight = descriptor.height;
      if (sourceWidth <= 0 ||
          sourceHeight <= 0 ||
          sourceWidth > _maximumSourceDimension ||
          sourceHeight > _maximumSourceDimension ||
          sourceWidth * sourceHeight > _maximumSourcePixels) {
        return null;
      }

      final targetSize = _targetSize(sourceWidth, sourceHeight);
      codec = await descriptor.instantiateCodec(
        targetWidth: targetSize.width,
        targetHeight: targetSize.height,
      );
      if (codec.frameCount <= 0 || codec.frameCount > _maximumAnimationFrames) {
        return null;
      }

      final frame = await codec.getNextFrame();
      image = frame.image;
      if (image.width <= 0 ||
          image.height <= 0 ||
          image.width > _maximumOutputDimension ||
          image.height > _maximumOutputDimension) {
        return null;
      }
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null || byteData.lengthInBytes == 0) {
        return null;
      }
      final pngBytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      return FaviconImage.fromPngBytes(pngBytes);
    } on Object {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  ({int width, int height}) _targetSize(int width, int height) {
    if (width <= _maximumOutputDimension && height <= _maximumOutputDimension) {
      return (width: width, height: height);
    }
    if (width >= height) {
      return (
        width: _maximumOutputDimension,
        height: ((height * _maximumOutputDimension) / width).round().clamp(
          1,
          _maximumOutputDimension,
        ),
      );
    }
    return (
      width: ((width * _maximumOutputDimension) / height).round().clamp(
        1,
        _maximumOutputDimension,
      ),
      height: _maximumOutputDimension,
    );
  }

  Future<_FetchedResponse?> _fetchSameOrigin({
    required Uri origin,
    required Uri initialUri,
    required Map<String, String> headers,
    required int maximumBodyBytes,
    required _ResolutionDeadline deadline,
    required bool Function(http.StreamedResponse response) acceptsResponse,
  }) async {
    var uri = initialUri.removeFragment();
    var redirectCount = 0;
    final visited = <String>{};

    while (!deadline.expired) {
      if (!_isHttpUri(uri) ||
          !_sameOrigin(origin, uri) ||
          !visited.add(uri.toString())) {
        return null;
      }

      final request =
          http.AbortableRequest('GET', uri, abortTrigger: deadline.abortTrigger)
            ..followRedirects = false
            ..headers.addAll(headers);
      final responseFuture = _client.send(request);
      unawaited(_cancelLateResponse(responseFuture, deadline));
      final response = await deadline.guard(responseFuture);

      if (_redirectStatusCodes.contains(response.statusCode)) {
        _cancelStream(response.stream);
        final location = response.headers['location']?.trim();
        if (location == null ||
            location.isEmpty ||
            redirectCount >= _maximumRedirects) {
          return null;
        }

        late final Uri nextUri;
        try {
          nextUri = uri.resolve(location).removeFragment();
        } on FormatException {
          return null;
        }
        if (!_isHttpUri(nextUri) || !_sameOrigin(origin, nextUri)) {
          return null;
        }
        redirectCount += 1;
        uri = nextUri;
        continue;
      }

      final contentLength = response.contentLength;
      if (!acceptsResponse(response) ||
          (contentLength != null && contentLength > maximumBodyBytes)) {
        _cancelStream(response.stream);
        return null;
      }

      final body = await _readBounded(
        response.stream,
        maximumBodyBytes,
        deadline,
      );
      if (body == null) {
        return null;
      }
      return _FetchedResponse(uri: uri, body: body);
    }
    return null;
  }

  Future<void> _cancelLateResponse(
    Future<http.StreamedResponse> responseFuture,
    _ResolutionDeadline deadline,
  ) async {
    try {
      final response = await responseFuture;
      if (deadline.expired) {
        _cancelStream(response.stream);
      }
    } on Object {
      // The active resolution reports request failures as a null result.
    }
  }

  Future<Uint8List?> _readBounded(
    Stream<List<int>> stream,
    int maximumBytes,
    _ResolutionDeadline deadline,
  ) {
    final completer = Completer<Uint8List?>();
    final bytes = BytesBuilder(copy: false);
    // Cancellation is performed by finish() for every terminal path.
    // ignore: cancel_subscriptions
    StreamSubscription<List<int>>? subscription;
    var byteCount = 0;
    var finished = false;

    void finish(Uint8List? value) {
      if (finished) {
        return;
      }
      finished = true;
      final currentSubscription = subscription;
      if (currentSubscription != null) {
        unawaited(_cancelQuietly(currentSubscription));
      }
      completer.complete(value);
    }

    try {
      subscription = stream.listen(
        (chunk) {
          if (finished) {
            return;
          }
          final remaining = maximumBytes - byteCount;
          if (chunk.length > remaining) {
            finish(null);
            return;
          }
          byteCount += chunk.length;
          bytes.add(chunk);
        },
        onError: (Object _, StackTrace _) => finish(null),
        onDone: () => finish(bytes.takeBytes()),
        cancelOnError: false,
      );
    } on Object {
      finish(null);
    }

    if (finished && subscription != null) {
      unawaited(_cancelQuietly(subscription));
    } else if (deadline.expired) {
      finish(null);
    } else {
      unawaited(deadline.abortTrigger.then((_) => finish(null)));
    }
    return completer.future;
  }

  void _cancelStream(Stream<List<int>> stream) {
    StreamSubscription<List<int>> subscription;
    try {
      subscription = stream.listen(
        null,
        onError: (Object _, StackTrace _) {},
        cancelOnError: true,
      );
    } on Object {
      return;
    }
    unawaited(_cancelQuietly(subscription));
  }

  Future<void> _cancelQuietly(
    StreamSubscription<List<int>> subscription,
  ) async {
    try {
      await subscription.cancel();
    } on Object {
      // Cancellation is best-effort; the resolver has already rejected it.
    }
  }

  Iterable<Uri> _declaredIcons(String html, Uri pageUri, Uri origin) sync* {
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

      final candidate = pageUri.resolve(href.trim()).removeFragment();
      if (!_isHttpUri(candidate) || !_sameOrigin(origin, candidate)) {
        continue;
      }
      yield candidate;
      yielded += 1;
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

  bool _isHtmlResponse(http.StreamedResponse response) {
    if (!_isSuccessful(response.statusCode)) {
      return false;
    }
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    return contentType.contains('text/html') ||
        contentType.contains('application/xhtml+xml');
  }

  bool _isPotentialImageResponse(http.StreamedResponse response) {
    if (!_isSuccessful(response.statusCode)) {
      return false;
    }
    final contentType = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    return contentType != 'image/svg+xml' &&
        contentType != 'text/html' &&
        contentType != 'application/xhtml+xml';
  }

  bool _isSuccessful(int statusCode) {
    return statusCode >= 200 && statusCode < 300;
  }

  bool _sameOrigin(Uri first, Uri second) {
    return first.scheme.toLowerCase() == second.scheme.toLowerCase() &&
        first.host.toLowerCase() == second.host.toLowerCase() &&
        _effectivePort(first) == _effectivePort(second);
  }

  bool _isHttpUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) {
      return uri.port;
    }
    return switch (uri.scheme.toLowerCase()) {
      'http' => 80,
      'https' => 443,
      _ => uri.port,
    };
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

final class _FetchedResponse {
  const _FetchedResponse({required this.uri, required this.body});

  final Uri uri;
  final Uint8List body;
}

final class _ResolutionDeadline {
  _ResolutionDeadline(Duration timeout) {
    _timer = Timer(timeout, _abort);
  }

  final Completer<void> _abortCompleter = Completer<void>();
  late final Timer _timer;

  Future<void> get abortTrigger => _abortCompleter.future;
  bool get expired => _abortCompleter.isCompleted;

  Future<T> guard<T>(Future<T> operation) {
    if (expired) {
      return Future<T>.error(TimeoutException('Favicon resolution timed out'));
    }
    return Future.any<T>(<Future<T>>[
      operation,
      abortTrigger.then<T>(
        (_) => throw TimeoutException('Favicon resolution timed out'),
      ),
    ]);
  }

  void _abort() {
    if (!_abortCompleter.isCompleted) {
      _abortCompleter.complete();
    }
  }

  void dispose() {
    _timer.cancel();
  }
}
