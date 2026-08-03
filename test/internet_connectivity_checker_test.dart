import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_signal/features/monitoring/data/http_internet_connectivity_checker.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';

void main() {
  test('reports no network without issuing an external probe', () async {
    var requestCount = 0;
    final checker = HttpInternetConnectivityChecker(
      client: MockClient((request) async {
        requestCount += 1;
        return http.Response('', 500);
      }),
      connectivityProvider: () async => <ConnectivityResult>[
        ConnectivityResult.none,
      ],
    );

    final assessment = await checker.assess();

    expect(assessment.availability, InternetAvailability.offline);
    expect(assessment.issue, ConnectivityIssue.noNetwork);
    expect(requestCount, 0);
  });

  test(
    'detects Wi-Fi without validated internet or a captive portal',
    () async {
      final checker = HttpInternetConnectivityChecker(
        client: MockClient((request) async => http.Response('Sign in', 200)),
        connectivityProvider: () async => <ConnectivityResult>[
          ConnectivityResult.wifi,
        ],
      );

      final assessment = await checker.assess();

      expect(assessment.availability, InternetAvailability.offline);
      expect(assessment.issue, ConnectivityIssue.noInternet);
      expect(assessment.transports, <NetworkTransport>[NetworkTransport.wifi]);
    },
  );

  test(
    'accepts internet access when either independent probe validates',
    () async {
      final checker = HttpInternetConnectivityChecker(
        client: MockClient((request) async {
          if (request.url.host == 'www.msftconnecttest.com') {
            return http.Response('Microsoft Connect Test', 200);
          }
          return http.Response('', 503);
        }),
        connectivityProvider: () async => <ConnectivityResult>[
          ConnectivityResult.mobile,
        ],
      );

      final assessment = await checker.assess();

      expect(assessment.availability, InternetAvailability.online);
      expect(assessment.issue, ConnectivityIssue.none);
      expect(assessment.transports, <NetworkTransport>[
        NetworkTransport.mobile,
      ]);
    },
  );

  test('cancels response streams for rejected statuses', () async {
    final bodies = <_TrackedBody>[];
    final checker = HttpInternetConnectivityChecker(
      client: _ProbeClient((request) async {
        final body = _TrackedBody.never();
        bodies.add(body);
        return http.StreamedResponse(body.stream, 503);
      }),
      connectivityProvider: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
    );

    final assessment = await checker.assess();
    await _waitForBodiesToClose(bodies);

    expect(assessment.availability, InternetAvailability.offline);
    expect(bodies, hasLength(2));
    for (final body in bodies) {
      expect(body.listened, isTrue);
      expect(body.cancelled, isTrue);
      expect(body.isClosed, isTrue);
      expect(body.hasActiveTimer, isFalse);
    }
  });

  test('cancels a successful no-body probe without draining it', () async {
    final bodies = <String, _TrackedBody>{};
    final checker = HttpInternetConnectivityChecker(
      client: _ProbeClient((request) async {
        final body = _TrackedBody.never();
        bodies[request.url.host] = body;
        return http.StreamedResponse(
          body.stream,
          request.url.host == 'connectivitycheck.gstatic.com' ? 204 : 503,
        );
      }),
      connectivityProvider: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
    );

    final assessment = await checker.assess();
    await _waitForBodiesToClose(bodies.values);

    expect(assessment.availability, InternetAvailability.online);
    final body = bodies['connectivitycheck.gstatic.com'];
    expect(body, isNotNull);
    expect(body?.listened, isTrue);
    expect(body?.cancelled, isTrue);
    expect(body?.isClosed, isTrue);
  });

  test('bounds expected-body inspection and cancels an open stream', () async {
    final bodies = <String, _TrackedBody>{};
    final checker = HttpInternetConnectivityChecker(
      client: _ProbeClient((request) async {
        final isBodyProbe = request.url.host == 'www.msftconnecttest.com';
        final body = _TrackedBody.trickle(
          isBodyProbe
              ? List<int>.filled(256, 'x'.codeUnitAt(0))
              : const <int>[],
          const Duration(milliseconds: 1),
        );
        bodies[request.url.host] = body;
        return http.StreamedResponse(body.stream, isBodyProbe ? 200 : 503);
      }),
      connectivityProvider: () async => <ConnectivityResult>[
        ConnectivityResult.mobile,
      ],
    );

    final assessment = await checker.assess();
    await _waitForBodiesToClose(bodies.values);

    expect(assessment.availability, InternetAvailability.offline);
    final body = bodies['www.msftconnecttest.com'];
    expect(body, isNotNull);
    expect(body?.emittedBytes, 129);
    expect(body?.cancelled, isTrue);
    expect(body?.isClosed, isTrue);
  });

  test(
    'rejects matching expected-body prefix when a later chunk exceeds the cap',
    () async {
      final expectedBytes = utf8.encode('Microsoft Connect Test');
      final matchingPrefix = <int>[
        ...expectedBytes,
        ...List<int>.filled(128 - expectedBytes.length, ' '.codeUnitAt(0)),
      ];
      final body = _SequencedBody(<List<int>>[
        matchingPrefix,
        utf8.encode('captive portal'),
      ], const Duration(milliseconds: 1));
      final checker = HttpInternetConnectivityChecker(
        client: _ProbeClient((request) async {
          if (request.url.host == 'www.msftconnecttest.com') {
            return http.StreamedResponse(body.stream, 200);
          }
          return http.StreamedResponse(Stream<List<int>>.empty(), 503);
        }),
        connectivityProvider: () async => <ConnectivityResult>[
          ConnectivityResult.wifi,
        ],
      );

      final assessment = await checker.assess();
      await body.done;

      expect(assessment.availability, InternetAvailability.offline);
      expect(body.emittedChunks, 2);
      expect(body.cancelled, isTrue);
      expect(body.isClosed, isTrue);
      expect(body.hasActiveTimer, isFalse);
    },
  );

  test(
    'a delayed expected body reaches one deadline and is cancelled',
    () async {
      final body = _TrackedBody.delayed(
        utf8.encode('Microsoft Connect Test'),
        const Duration(seconds: 1),
      );
      final checker = HttpInternetConnectivityChecker(
        client: _ProbeClient((request) async {
          if (request.url.host == 'www.msftconnecttest.com') {
            return http.StreamedResponse(body.stream, 200);
          }
          return http.StreamedResponse(Stream<List<int>>.empty(), 503);
        }),
        connectivityProvider: () async => <ConnectivityResult>[
          ConnectivityResult.wifi,
        ],
        timeout: const Duration(milliseconds: 30),
      );
      final stopwatch = Stopwatch()..start();

      final assessment = await checker.assess();
      stopwatch.stop();
      await _waitForBodiesToClose(<_TrackedBody>[body]);

      expect(assessment.availability, InternetAvailability.offline);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
      expect(body.cancelled, isTrue);
      expect(body.isClosed, isTrue);
      expect(body.hasActiveTimer, isFalse);
    },
  );

  test('a never-ending expected body times out and is cancelled', () async {
    final body = _TrackedBody.never(utf8.encode('Microsoft'));
    final checker = HttpInternetConnectivityChecker(
      client: _ProbeClient((request) async {
        if (request.url.host == 'www.msftconnecttest.com') {
          return http.StreamedResponse(body.stream, 200);
        }
        return http.StreamedResponse(Stream<List<int>>.empty(), 503);
      }),
      connectivityProvider: () async => <ConnectivityResult>[
        ConnectivityResult.wifi,
      ],
      timeout: const Duration(milliseconds: 30),
    );

    final assessment = await checker.assess();
    await _waitForBodiesToClose(<_TrackedBody>[body]);

    expect(assessment.availability, InternetAvailability.offline);
    expect(body.cancelled, isTrue);
    expect(body.isClosed, isTrue);
    expect(body.hasActiveTimer, isFalse);
  });

  test('a fast winner aborts the other in-flight request', () async {
    final winningBodies = <_TrackedBody>[];
    var losingProbeStarted = false;
    var losingProbeAborted = false;
    final requests = <http.BaseRequest>[];
    final checker = HttpInternetConnectivityChecker(
      client: _ProbeClient((request) {
        requests.add(request);
        final abortTrigger = _requestAbortTrigger(request);
        if (request.url.host == 'connectivitycheck.gstatic.com') {
          final body = _TrackedBody.never();
          winningBodies.add(body);
          return Future<http.StreamedResponse>.value(
            http.StreamedResponse(body.stream, 204),
          );
        }
        losingProbeStarted = true;
        return abortTrigger.then<http.StreamedResponse>((_) {
          losingProbeAborted = true;
          throw http.RequestAbortedException(request.url);
        });
      }),
      connectivityProvider: () async => <ConnectivityResult>[
        ConnectivityResult.mobile,
      ],
      timeout: const Duration(seconds: 2),
    );
    final stopwatch = Stopwatch()..start();

    final assessment = await checker.assess();
    stopwatch.stop();
    await _waitForBodiesToClose(winningBodies);

    expect(assessment.availability, InternetAvailability.online);
    expect(requests, hasLength(2));
    expect(requests, everyElement(isA<http.AbortableRequest>()));
    expect(losingProbeStarted, isTrue);
    expect(losingProbeAborted, isTrue);
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    expect(winningBodies.single.cancelled, isTrue);
    expect(winningBodies.single.isClosed, isTrue);
    expect(winningBodies.single.hasActiveTimer, isFalse);
  });
}

typedef _ProbeHandler =
    Future<http.StreamedResponse> Function(http.BaseRequest request);

final class _ProbeClient extends http.BaseClient {
  _ProbeClient(this._handler);

  final _ProbeHandler _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

enum _TrackedBodyMode { delayed, never, trickle }

final class _TrackedBody {
  _TrackedBody.never([this.bytes = const <int>[]])
    : mode = _TrackedBodyMode.never,
      delay = Duration.zero;

  _TrackedBody.delayed(this.bytes, this.delay)
    : mode = _TrackedBodyMode.delayed;

  _TrackedBody.trickle(this.bytes, this.delay)
    : mode = _TrackedBodyMode.trickle;

  final List<int> bytes;
  final Duration delay;
  final _TrackedBodyMode mode;
  Timer? _timer;
  var listened = false;
  var cancelled = false;
  var emittedBytes = 0;
  var _nextByte = 0;

  late final StreamController<List<int>> _controller =
      StreamController<List<int>>(onListen: _start, onCancel: _cancel);

  Stream<List<int>> get stream => _controller.stream;

  bool get isClosed => _controller.isClosed;

  bool get hasActiveTimer => _timer?.isActive ?? false;

  Future<void> get done => _controller.done;

  void _start() {
    listened = true;
    switch (mode) {
      case _TrackedBodyMode.delayed:
        _timer = Timer(delay, () {
          _timer = null;
          if (!cancelled) {
            emittedBytes += bytes.length;
            _controller.add(bytes);
            unawaited(_close());
          }
        });
      case _TrackedBodyMode.never:
        if (bytes.isNotEmpty) {
          emittedBytes += bytes.length;
          _controller.add(bytes);
        }
      case _TrackedBodyMode.trickle:
        _timer = Timer.periodic(delay, (timer) {
          if (cancelled || _nextByte >= bytes.length) {
            timer.cancel();
            _timer = null;
            unawaited(_close());
            return;
          }
          _controller.add(<int>[bytes[_nextByte]]);
          emittedBytes += 1;
          _nextByte += 1;
        });
    }
  }

  void _cancel() {
    cancelled = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_close());
  }

  Future<void> _close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

final class _SequencedBody {
  _SequencedBody(this.chunks, this.interval);

  final List<List<int>> chunks;
  final Duration interval;
  Timer? _timer;
  var _nextChunk = 0;
  var emittedChunks = 0;
  var cancelled = false;

  late final StreamController<List<int>> _controller =
      StreamController<List<int>>(onListen: _start, onCancel: _cancel);

  Stream<List<int>> get stream => _controller.stream;

  Future<void> get done => _controller.done;

  bool get isClosed => _controller.isClosed;

  bool get hasActiveTimer => _timer?.isActive ?? false;

  void _start() {
    _timer = Timer.periodic(interval, (timer) {
      if (_nextChunk >= chunks.length) {
        timer.cancel();
        _timer = null;
        unawaited(_close());
        return;
      }
      _controller.add(chunks[_nextChunk]);
      _nextChunk += 1;
      emittedChunks += 1;
    });
  }

  void _cancel() {
    cancelled = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_close());
  }

  Future<void> _close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

Future<void> _waitForBodiesToClose(Iterable<_TrackedBody> bodies) async {
  await Future.wait(<Future<void>>[for (final body in bodies) body.done]);
}

Future<void> _requestAbortTrigger(http.BaseRequest request) {
  if (request case http.AbortableRequest(:final abortTrigger?)) {
    return abortTrigger;
  }
  throw StateError('Expected an AbortableRequest with an abort trigger');
}
