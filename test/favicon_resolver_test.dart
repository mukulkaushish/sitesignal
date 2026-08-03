import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_signal/features/monitoring/data/http_favicon_resolver.dart';
import 'package:site_signal/features/monitoring/domain/entities/favicon_image.dart';

final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDw'
  'AEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  group('FaviconImage', () {
    test('defensively copies normalized PNG bytes', () {
      final source = Uint8List.fromList(_pngBytes);
      final expected = Uint8List.fromList(source);
      final favicon = FaviconImage.fromPngBytes(source);

      source[0] = 0;
      final exposed = favicon.pngBytes;
      exposed[1] = 0;

      expect(favicon.pngBytes, orderedEquals(expected));
    });
  });

  group('HttpFaviconResolver', () {
    test('normalizes and downsizes a declared image to PNG', () async {
      final source = await _renderPng(128, 32);
      final requested = <String>[];
      final resolver = HttpFaviconResolver(
        client: MockClient((request) async {
          requested.add(request.url.toString());
          if (request.url.path.isEmpty) {
            return http.Response(
              '<link rel="shortcut icon" href="/assets/site.png">',
              200,
              headers: const <String, String>{'content-type': 'text/html'},
            );
          }
          if (request.url.path == '/assets/site.png') {
            return http.Response.bytes(
              source,
              200,
              headers: const <String, String>{'content-type': 'image/png'},
            );
          }
          return http.Response('', 404);
        }),
      );

      final result = await _resolveAndClose(resolver);
      final decoded = await _expectNormalizedPng(result);

      expect((decoded.width, decoded.height), (64, 16));
      expect(requested, <String>[
        'https://example.com',
        'https://example.com/assets/site.png',
      ]);
    });

    test('requests only exact same-origin declared icons', () async {
      final requested = <Uri>[];
      final resolver = HttpFaviconResolver(
        client: MockClient((request) async {
          requested.add(request.url);
          if (request.url.path.isEmpty) {
            return http.Response(
              '<link rel="icon" href="https://cdn.example.net/icon.png">'
              '<link rel="icon" href="http://example.com/insecure.png">'
              '<link rel="icon" href="https://example.com:444/other.png">'
              '<link rel="icon" href="https://example.com:443/same.png">',
              200,
              headers: const <String, String>{'content-type': 'text/html'},
            );
          }
          if (request.url.path == '/same.png') {
            return http.Response.bytes(
              _pngBytes,
              200,
              headers: const <String, String>{'content-type': 'image/png'},
            );
          }
          return http.Response('', 404);
        }),
      );

      final result = await _resolveAndClose(resolver);

      await _expectNormalizedPng(result);
      expect(requested, hasLength(2));
      expect(requested.last.path, '/same.png');
      expect(requested.map((uri) => uri.host), everyElement('example.com'));
      expect(requested.map((uri) => uri.scheme), everyElement('https'));
      expect(requested.map((uri) => uri.port), everyElement(443));
    });

    test('follows same-origin page and icon redirects', () async {
      final requested = <String>[];
      final resolver = HttpFaviconResolver(
        client: MockClient((request) async {
          requested.add(request.url.toString());
          return switch (request.url.path) {
            '' => http.Response(
              '',
              302,
              headers: const <String, String>{'location': '/status/ui/'},
            ),
            '/status/ui/' => http.Response(
              '<link rel="icon" href="icons/site">',
              200,
              headers: const <String, String>{'content-type': 'text/html'},
            ),
            '/status/ui/icons/site' => http.Response(
              '',
              308,
              headers: const <String, String>{'location': '../final.png'},
            ),
            '/status/ui/final.png' => http.Response.bytes(
              _pngBytes,
              200,
              headers: const <String, String>{'content-type': 'image/png'},
            ),
            _ => http.Response('', 404),
          };
        }),
      );

      final result = await _resolveAndClose(resolver);

      await _expectNormalizedPng(result);
      expect(requested, <String>[
        'https://example.com',
        'https://example.com/status/ui/',
        'https://example.com/status/ui/icons/site',
        'https://example.com/status/ui/final.png',
      ]);
    });

    test('rejects and cancels a cross-origin page redirect', () async {
      final redirectBody = _StreamProbe.neverEnding(const <int>[]);
      final requested = <String>[];
      final resolver = HttpFaviconResolver(
        client: MockClient.streaming((request, _) async {
          requested.add(request.url.toString());
          if (request.url.path.isEmpty) {
            return http.StreamedResponse(
              redirectBody.stream,
              301,
              headers: const <String, String>{
                'location': 'https://tracking.example.net/page',
              },
            );
          }
          return _streamedBytes(const <int>[], 404);
        }),
      );

      try {
        final result = await _resolveAndClose(resolver);
        await Future<void>.delayed(Duration.zero);

        expect(result, isNull);
        expect(redirectBody.cancelled, isTrue);
        expect(requested, <String>[
          'https://example.com',
          'https://example.com/favicon.ico',
        ]);
      } finally {
        await redirectBody.dispose();
      }
    });

    test('rejects a cross-origin icon redirect before requesting it', () async {
      final requested = <String>[];
      final resolver = HttpFaviconResolver(
        client: MockClient((request) async {
          requested.add(request.url.toString());
          if (request.url.path.isEmpty) {
            return http.Response(
              '<link rel="icon" href="/icon">',
              200,
              headers: const <String, String>{'content-type': 'text/html'},
            );
          }
          if (request.url.path == '/icon') {
            return http.Response(
              '',
              307,
              headers: const <String, String>{
                'location': 'https://tracking.example.net/icon.png',
              },
            );
          }
          return http.Response('', 404);
        }),
      );

      final result = await _resolveAndClose(resolver);

      expect(result, isNull);
      expect(requested, <String>[
        'https://example.com',
        'https://example.com/icon',
        'https://example.com/favicon.ico',
      ]);
    });

    test('rejects redirect loops and redirects beyond five hops', () async {
      final loopRequests = <String>[];
      final loopResolver = HttpFaviconResolver(
        client: MockClient((request) async {
          loopRequests.add(request.url.toString());
          if (request.url.path == '/favicon.ico') {
            return http.Response('', 404);
          }
          return http.Response(
            '',
            302,
            headers: <String, String>{
              'location': switch (request.url.path) {
                '' => '/loop-a',
                '/loop-a' => '/loop-b',
                _ => '/loop-a',
              },
            },
          );
        }),
      );
      expect(await _resolveAndClose(loopResolver), isNull);
      expect(loopRequests, <String>[
        'https://example.com',
        'https://example.com/loop-a',
        'https://example.com/loop-b',
        'https://example.com/favicon.ico',
      ]);

      final hopRequests = <String>[];
      final hopResolver = HttpFaviconResolver(
        client: MockClient((request) async {
          hopRequests.add(request.url.toString());
          if (request.url.path == '/favicon.ico') {
            return http.Response('', 404);
          }
          final hop = request.url.path.isEmpty
              ? 0
              : int.parse(request.url.pathSegments.last);
          return http.Response(
            '',
            303,
            headers: <String, String>{'location': '/hop/${hop + 1}'},
          );
        }),
      );
      expect(await _resolveAndClose(hopResolver), isNull);
      expect(hopRequests, contains('https://example.com/hop/5'));
      expect(hopRequests, isNot(contains('https://example.com/hop/6')));
    });

    test('falls back to the conventional favicon', () async {
      final requested = <String>[];
      final resolver = HttpFaviconResolver(
        client: MockClient((request) async {
          requested.add(request.url.toString());
          if (request.url.path.isEmpty) {
            return http.Response(
              '<title>Example</title>',
              200,
              headers: const <String, String>{'content-type': 'text/html'},
            );
          }
          return http.Response.bytes(
            _pngBytes,
            200,
            headers: const <String, String>{'content-type': 'image/png'},
          );
        }),
      );

      final result = await _resolveAndClose(resolver);

      await _expectNormalizedPng(result);
      expect(requested.last, 'https://example.com/favicon.ico');
    });

    test(
      'rejects oversized dimensions, pixels, frames, and corrupt data',
      () async {
        final tooWide = _grayscalePng(4097, 1);
        final tooManyPixels = _grayscalePng(4001, 4000);
        final tooManyFrames = _animatedGif(33);
        final corrupt = _corruptPng();

        expect(await _descriptorSize(tooWide), (4097, 1));
        expect(await _descriptorSize(tooManyPixels), (4001, 4000));
        final animated = await _inspectEncoded(tooManyFrames);
        expect(animated.frameCount, 33);
        await _expectDecodeFailure(corrupt);

        final fixtures = <String, Uint8List>{
          'dimension': tooWide,
          'pixel count': tooManyPixels,
          'frame count': tooManyFrames,
          'corrupt decode': corrupt,
        };
        for (final MapEntry(key: reason, value: bytes) in fixtures.entries) {
          final result = await _resolveIconBytes(bytes);
          expect(result, isNull, reason: reason);
        }
      },
    );

    test('rejects HTML and SVG image responses', () async {
      final resolver = HttpFaviconResolver(
        client: MockClient((request) async {
          if (request.url.path.isEmpty) {
            return http.Response(
              '<link rel="icon" href="/icon.svg">',
              200,
              headers: const <String, String>{'content-type': 'text/html'},
            );
          }
          if (request.url.path == '/icon.svg') {
            return http.Response(
              '<svg xmlns="http://www.w3.org/2000/svg"/>',
              200,
              headers: const <String, String>{'content-type': 'image/svg+xml'},
            );
          }
          return http.Response(
            '<!doctype html><html></html>',
            200,
            headers: const <String, String>{'content-type': 'text/html'},
          );
        }),
      );

      expect(await _resolveAndClose(resolver), isNull);
    });

    test('cancels HTML and image bodies above their byte caps', () async {
      final htmlBody = _StreamProbe.once(Uint8List((64 * 1024) + 1));
      final htmlResolver = HttpFaviconResolver(
        client: MockClient.streaming((request, _) async {
          if (request.url.path.isEmpty) {
            return http.StreamedResponse(
              htmlBody.stream,
              200,
              headers: const <String, String>{'content-type': 'text/html'},
            );
          }
          return _streamedBytes(const <int>[], 404);
        }),
      );
      try {
        expect(await _resolveAndClose(htmlResolver), isNull);
        await Future<void>.delayed(Duration.zero);
        expect(htmlBody.cancelled, isTrue);
      } finally {
        await htmlBody.dispose();
      }

      final imageBody = _StreamProbe.once(Uint8List((256 * 1024) + 1));
      final imageResolver = HttpFaviconResolver(
        client: MockClient.streaming((request, _) async {
          if (request.url.path.isEmpty) {
            return _streamedBytes(
              utf8.encode('<link rel="icon" href="/large.png">'),
              200,
              headers: const <String, String>{'content-type': 'text/html'},
            );
          }
          if (request.url.path == '/large.png') {
            return http.StreamedResponse(
              imageBody.stream,
              200,
              headers: const <String, String>{'content-type': 'image/png'},
            );
          }
          return _streamedBytes(const <int>[], 404);
        }),
      );
      try {
        expect(await _resolveAndClose(imageResolver), isNull);
        await Future<void>.delayed(Duration.zero);
        expect(imageBody.cancelled, isTrue);
      } finally {
        await imageBody.dispose();
      }
    });

    test('aborts when response headers never arrive', () async {
      final client = _NeverRespondingClient();
      final resolver = HttpFaviconResolver(
        client: client,
        timeout: const Duration(milliseconds: 35),
      );
      final stopwatch = Stopwatch()..start();

      final result = await _resolveAndClose(
        resolver,
      ).timeout(const Duration(seconds: 1));
      stopwatch.stop();
      await Future<void>.delayed(Duration.zero);

      expect(result, isNull);
      expect(client.aborted, isTrue);
      expect(client.requestCount, 1);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    });

    test('cancels delayed, trickling, and never-ending bodies', () async {
      final scenarios = <(String, _StreamProbe Function())>[
        (
          'delayed',
          () => _StreamProbe.delayed(_pngBytes, const Duration(seconds: 1)),
        ),
        (
          'trickling',
          () =>
              _StreamProbe.trickle(_pngBytes, const Duration(milliseconds: 12)),
        ),
        ('never-ending', () => _StreamProbe.neverEnding(_pngBytes)),
      ];

      for (final (reason, createBody) in scenarios) {
        final body = createBody();
        try {
          final outcome = await _runTimedBody(body);
          expect(outcome.result, isNull, reason: reason);
          expect(body.cancelled, isTrue, reason: reason);
          expect(outcome.aborted, isTrue, reason: reason);
          expect(outcome.requested, <String>[
            'https://example.com',
            'https://example.com/icon.png',
          ]);
          expect(outcome.abortTriggers, hasLength(2));
          expect(
            identical(outcome.abortTriggers.first, outcome.abortTriggers.last),
            isTrue,
          );
          expect(outcome.elapsed, lessThan(const Duration(milliseconds: 500)));
        } finally {
          await body.dispose();
        }
      }
    });
  });
}

Future<FaviconImage?> _resolveAndClose(HttpFaviconResolver resolver) async {
  try {
    return await resolver.resolve(Uri.parse('https://example.com'));
  } finally {
    resolver.close();
  }
}

Future<FaviconImage?> _resolveIconBytes(Uint8List bytes) {
  return _resolveAndClose(
    HttpFaviconResolver(
      client: MockClient((request) async {
        if (request.url.path.isEmpty) {
          return http.Response(
            '<link rel="icon" href="/icon">',
            200,
            headers: const <String, String>{'content-type': 'text/html'},
          );
        }
        if (request.url.path == '/icon') {
          return http.Response.bytes(
            bytes,
            200,
            headers: const <String, String>{'content-type': 'image/png'},
          );
        }
        return http.Response('', 404);
      }),
    ),
  );
}

Future<_ImageInfo> _expectNormalizedPng(FaviconImage? favicon) async {
  expect(favicon, isNotNull);
  if (favicon == null) {
    throw TestFailure('Expected a normalized favicon');
  }
  final firstCopy = favicon.pngBytes;
  final secondCopy = favicon.pngBytes;
  expect(identical(firstCopy, secondCopy), isFalse);
  final info = await _inspectEncoded(firstCopy);
  expect(info.frameCount, 1);
  expect(info.width, inInclusiveRange(1, 64));
  expect(info.height, inInclusiveRange(1, 64));
  return info;
}

Future<_ImageInfo> _inspectEncoded(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec();
    final frameCount = codec.frameCount;
    final frame = await codec.getNextFrame();
    image = frame.image;
    return _ImageInfo(
      width: image.width,
      height: image.height,
      frameCount: frameCount,
    );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<(int, int)> _descriptorSize(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (descriptor.width, descriptor.height);
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<void> _expectDecodeFailure(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  Object? decodeError;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    codec = await descriptor.instantiateCodec();
    try {
      final frame = await codec.getNextFrame();
      image = frame.image;
    } on Object catch (error) {
      decodeError = error;
    }
    expect(decodeError, isNotNull);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<Uint8List> _renderPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xff3478f6),
  );
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Flutter could not encode the test PNG');
    }
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

Uint8List _grayscalePng(int width, int height) {
  final compressed = BytesBuilder(copy: false);
  final sink = ZLibEncoder().startChunkedConversion(
    ByteConversionSink.withCallback(compressed.add),
  );
  final row = Uint8List(width + 1);
  for (var index = 0; index < height; index += 1) {
    sink.add(row);
  }
  sink.close();

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 0);
  final output = BytesBuilder(copy: false)
    ..add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  _addPngChunk(output, 'IHDR', header.buffer.asUint8List());
  _addPngChunk(output, 'IDAT', compressed.takeBytes());
  _addPngChunk(output, 'IEND', const <int>[]);
  return output.takeBytes();
}

Uint8List _corruptPng() {
  final header = ByteData(13)
    ..setUint32(0, 1)
    ..setUint32(4, 1)
    ..setUint8(8, 8)
    ..setUint8(9, 0);
  final output = BytesBuilder(copy: false)
    ..add(const <int>[137, 80, 78, 71, 13, 10, 26, 10]);
  _addPngChunk(output, 'IHDR', header.buffer.asUint8List());
  _addPngChunk(output, 'IDAT', const <int>[0x78, 0x9c, 0x00]);
  _addPngChunk(output, 'IEND', const <int>[]);
  return output.takeBytes();
}

void _addPngChunk(BytesBuilder output, String type, List<int> data) {
  final typeBytes = ascii.encode(type);
  final length = ByteData(4)..setUint32(0, data.length);
  final checksum = ByteData(4)
    ..setUint32(0, _crc32(<int>[...typeBytes, ...data]));
  output
    ..add(length.buffer.asUint8List())
    ..add(typeBytes)
    ..add(data)
    ..add(checksum.buffer.asUint8List());
}

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 0 ? crc >>> 1 : 0xedb88320 ^ (crc >>> 1);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Uint8List _animatedGif(int frameCount) {
  const header = <int>[
    0x47,
    0x49,
    0x46,
    0x38,
    0x39,
    0x61,
    0x01,
    0x00,
    0x01,
    0x00,
    0x80,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0xff,
    0xff,
    0xff,
  ];
  const frame = <int>[
    0x2c,
    0x00,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x01,
    0x00,
    0x00,
    0x02,
    0x01,
    0x4c,
    0x00,
  ];
  final output = BytesBuilder(copy: false)..add(header);
  for (var index = 0; index < frameCount; index += 1) {
    output.add(frame);
  }
  output.addByte(0x3b);
  return output.takeBytes();
}

http.StreamedResponse _streamedBytes(
  List<int> bytes,
  int statusCode, {
  Map<String, String> headers = const <String, String>{},
}) {
  return http.StreamedResponse(
    Stream<List<int>>.value(bytes),
    statusCode,
    contentLength: bytes.length,
    headers: headers,
  );
}

Future<_TimedOutcome> _runTimedBody(_StreamProbe body) async {
  final requested = <String>[];
  final abortTriggers = <Future<void>>[];
  var aborted = false;
  final resolver = HttpFaviconResolver(
    client: MockClient.streaming((request, _) async {
      requested.add(request.url.toString());
      final abortTrigger = _requestAbortTrigger(request);
      abortTriggers.add(abortTrigger);
      if (request.url.path.isEmpty) {
        return _streamedBytes(
          utf8.encode('<link rel="icon" href="/icon.png">'),
          200,
          headers: const <String, String>{'content-type': 'text/html'},
        );
      }
      unawaited(abortTrigger.then((_) => aborted = true));
      return http.StreamedResponse(
        body.stream,
        200,
        headers: const <String, String>{'content-type': 'image/png'},
      );
    }),
    timeout: const Duration(milliseconds: 55),
  );
  final stopwatch = Stopwatch()..start();

  final result = await _resolveAndClose(
    resolver,
  ).timeout(const Duration(seconds: 1));
  stopwatch.stop();
  await Future<void>.delayed(Duration.zero);

  return _TimedOutcome(
    result: result,
    requested: requested,
    abortTriggers: abortTriggers,
    aborted: aborted,
    elapsed: stopwatch.elapsed,
  );
}

final class _ImageInfo {
  const _ImageInfo({
    required this.width,
    required this.height,
    required this.frameCount,
  });

  final int width;
  final int height;
  final int frameCount;
}

final class _TimedOutcome {
  const _TimedOutcome({
    required this.result,
    required this.requested,
    required this.abortTriggers,
    required this.aborted,
    required this.elapsed,
  });

  final FaviconImage? result;
  final List<String> requested;
  final List<Future<void>> abortTriggers;
  final bool aborted;
  final Duration elapsed;
}

enum _StreamMode { delayed, trickle, neverEnding, once }

final class _StreamProbe {
  _StreamProbe.delayed(this.bytes, this.interval) : mode = _StreamMode.delayed;

  _StreamProbe.trickle(this.bytes, this.interval) : mode = _StreamMode.trickle;

  _StreamProbe.neverEnding(this.bytes)
    : mode = _StreamMode.neverEnding,
      interval = Duration.zero;

  _StreamProbe.once(this.bytes)
    : mode = _StreamMode.once,
      interval = Duration.zero;

  final List<int> bytes;
  final Duration interval;
  final _StreamMode mode;
  Timer? _timer;
  var _index = 0;
  var cancelled = false;

  late final StreamController<List<int>> _controller =
      StreamController<List<int>>(onListen: _start, onCancel: _cancel);

  Stream<List<int>> get stream => _controller.stream;

  void _start() {
    switch (mode) {
      case _StreamMode.delayed:
        _timer = Timer(interval, () {
          if (!cancelled) {
            _controller.add(bytes);
            unawaited(_controller.close());
          }
        });
      case _StreamMode.trickle:
        _timer = Timer.periodic(interval, (timer) {
          if (cancelled) {
            timer.cancel();
            return;
          }
          _controller.add(<int>[bytes[_index]]);
          _index += 1;
          if (_index == bytes.length) {
            timer.cancel();
            unawaited(_controller.close());
          }
        });
      case _StreamMode.neverEnding:
        if (bytes.isNotEmpty) {
          _controller.add(bytes);
        }
      case _StreamMode.once:
        _controller.add(bytes);
        unawaited(_controller.close());
    }
  }

  void _cancel() {
    cancelled = true;
    _timer?.cancel();
  }

  Future<void> dispose() async {
    _timer?.cancel();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

final class _NeverRespondingClient extends http.BaseClient {
  var requestCount = 0;
  var aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requestCount += 1;
    final abortTrigger = _requestAbortTrigger(request);
    unawaited(abortTrigger.then((_) => aborted = true));
    return Completer<http.StreamedResponse>().future;
  }
}

Future<void> _requestAbortTrigger(http.BaseRequest request) {
  if (request case http.AbortableRequest(:final abortTrigger?)) {
    return abortTrigger;
  }
  throw StateError('Expected an AbortableRequest with an abort trigger');
}
