import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';

typedef ConnectivityProvider = Future<List<ConnectivityResult>> Function();
typedef ConnectivityChangesProvider = Stream<List<ConnectivityResult>>;

class HttpInternetConnectivityChecker implements InternetConnectivityChecker {
  HttpInternetConnectivityChecker({
    http.Client? client,
    this.connectivityProvider,
    this.connectivityChanges,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _connectivity = Connectivity();

  final http.Client _client;
  final bool _ownsClient;
  final Connectivity _connectivity;
  final ConnectivityProvider? connectivityProvider;
  final ConnectivityChangesProvider? connectivityChanges;
  final Duration timeout;

  static const int _maximumExpectedBodyBytes = 128;

  @override
  Stream<void> get changes =>
      (connectivityChanges ?? _connectivity.onConnectivityChanged).map((_) {});

  static const _probes = <_ReachabilityProbe>[
    _ReachabilityProbe(
      uri: 'http://connectivitycheck.gstatic.com/generate_204',
      expectedStatus: 204,
    ),
    _ReachabilityProbe(
      uri: 'http://www.msftconnecttest.com/connecttest.txt',
      expectedStatus: 200,
      expectedBody: 'Microsoft Connect Test',
    ),
  ];

  @override
  Future<ConnectivityAssessment> assess() async {
    final checkedAt = DateTime.now().toUtc();
    List<ConnectivityResult>? connectivity;
    try {
      connectivity =
          await (connectivityProvider?.call() ??
                  _connectivity.checkConnectivity())
              .timeout(timeout);
    } on Object {
      // Active probes below remain authoritative when an OS interface query is
      // temporarily unavailable.
    }
    final transports = connectivity == null
        ? const <NetworkTransport>[]
        : connectivity
              .where((result) => result != ConnectivityResult.none)
              .map(_mapTransport)
              .toSet()
              .toList(growable: false);
    if (connectivity != null &&
        (connectivity.isEmpty ||
            connectivity.every(
              (result) => result == ConnectivityResult.none,
            ))) {
      return ConnectivityAssessment(
        availability: InternetAvailability.offline,
        issue: ConnectivityIssue.noNetwork,
        transports: const <NetworkTransport>[],
        checkedAt: checkedAt,
      );
    }

    if (await _anyProbeSucceeds()) {
      return ConnectivityAssessment(
        availability: InternetAvailability.online,
        issue: ConnectivityIssue.none,
        transports: transports,
        checkedAt: checkedAt,
      );
    }
    return ConnectivityAssessment(
      availability: InternetAvailability.offline,
      issue: ConnectivityIssue.noInternet,
      transports: transports,
      checkedAt: checkedAt,
    );
  }

  Future<bool> _anyProbeSucceeds() async {
    final attempts = <_ProbeAttempt>[
      for (var index = 0; index < _probes.length; index += 1) _ProbeAttempt(),
    ];
    final completed = Completer<int?>();
    var remaining = _probes.length;
    final results = <Future<bool>>[];
    for (var index = 0; index < _probes.length; index += 1) {
      final result = _runProbe(_probes[index], attempts[index]);
      results.add(result);
      unawaited(
        result.then((reachable) {
          remaining -= 1;
          if (!completed.isCompleted && reachable) {
            completed.complete(index);
          } else if (!completed.isCompleted && remaining == 0) {
            completed.complete(null);
          }
        }),
      );
    }

    final winner = await completed.future;
    if (winner != null) {
      await Future.wait(<Future<void>>[
        for (var index = 0; index < attempts.length; index += 1)
          if (index != winner) attempts[index].abort(),
      ]);
    }
    await Future.wait(results);
    return winner != null;
  }

  Future<bool> _runProbe(
    _ReachabilityProbe probe,
    _ProbeAttempt attempt,
  ) async {
    final deadline = Timer(timeout, () {
      unawaited(attempt.abort());
    });
    try {
      final request =
          http.AbortableRequest(
              'GET',
              Uri.parse(probe.uri),
              abortTrigger: attempt.abortTrigger,
            )
            ..followRedirects = false
            ..headers.addAll(const <String, String>{
              'Accept': 'text/plain',
              'Cache-Control': 'no-cache',
              'User-Agent': 'SiteSignal/1.0 connectivity-check',
            });

      final responseReady = Completer<http.StreamedResponse?>();
      unawaited(
        _client
            .send(request)
            .then(
              (response) {
                if (!responseReady.isCompleted && !attempt.isAborted) {
                  responseReady.complete(response);
                  return;
                }
                unawaited(_cancelDetachedResponse(response.stream));
              },
              onError: (Object error, StackTrace stackTrace) {
                if (!responseReady.isCompleted) {
                  responseReady.completeError(error, stackTrace);
                }
              },
            ),
      );
      unawaited(
        attempt.abortTrigger.then((_) {
          if (!responseReady.isCompleted) {
            responseReady.complete(null);
          }
        }),
      );

      final response = await responseReady.future;
      if (response == null || attempt.isAborted) {
        if (response != null) {
          await _cancelDetachedResponse(response.stream);
        }
        return false;
      }

      final expectedBody = probe.expectedBody;
      if (response.statusCode != probe.expectedStatus || expectedBody == null) {
        final subscription = response.stream.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        attempt.attachResponse(subscription);
        await attempt.cancelResponse();
        return response.statusCode == probe.expectedStatus &&
            expectedBody == null &&
            !attempt.isAborted;
      }

      final bytes = <int>[];
      final bodyComplete = Completer<bool>();
      final subscription = response.stream.listen(
        (chunk) {
          if (bodyComplete.isCompleted) {
            return;
          }
          final remaining = _maximumExpectedBodyBytes - bytes.length;
          if (chunk.length > remaining) {
            if (remaining > 0) {
              bytes.addAll(chunk.sublist(0, remaining));
            }
            bodyComplete.complete(false);
            return;
          }
          bytes.addAll(chunk);
        },
        onError: (Object _, StackTrace _) {
          if (!bodyComplete.isCompleted) {
            bodyComplete.complete(false);
          }
        },
        onDone: () {
          if (!bodyComplete.isCompleted) {
            bodyComplete.complete(true);
          }
        },
      );
      attempt.attachResponse(subscription);
      final completedBody = await Future.any<bool>(<Future<bool>>[
        bodyComplete.future,
        attempt.abortTrigger.then((_) => false),
      ]);
      await attempt.cancelResponse();
      return completedBody &&
          !attempt.isAborted &&
          utf8.decode(bytes, allowMalformed: true).trim() == expectedBody;
    } on Object {
      return false;
    } finally {
      deadline.cancel();
      await attempt.abort();
    }
  }

  Future<void> _cancelDetachedResponse(Stream<List<int>> stream) async {
    final subscription = stream.listen(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      await subscription.cancel();
    } on Object {
      // Connectivity assessment is already complete for this response.
    }
  }

  NetworkTransport _mapTransport(ConnectivityResult result) {
    return switch (result) {
      ConnectivityResult.wifi => NetworkTransport.wifi,
      ConnectivityResult.mobile => NetworkTransport.mobile,
      ConnectivityResult.ethernet => NetworkTransport.ethernet,
      ConnectivityResult.vpn => NetworkTransport.vpn,
      ConnectivityResult.satellite => NetworkTransport.satellite,
      ConnectivityResult.bluetooth => NetworkTransport.bluetooth,
      ConnectivityResult.other => NetworkTransport.other,
      ConnectivityResult.none => NetworkTransport.unknown,
    };
  }

  @override
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class _ReachabilityProbe {
  const _ReachabilityProbe({
    required this.uri,
    required this.expectedStatus,
    this.expectedBody,
  });

  final String uri;
  final int expectedStatus;
  final String? expectedBody;
}

final class _ProbeAttempt {
  final Completer<void> _abort = Completer<void>();
  StreamSubscription<List<int>>? _responseSubscription;
  Future<void>? _responseCancellation;

  Future<void> get abortTrigger => _abort.future;

  bool get isAborted => _abort.isCompleted;

  void attachResponse(StreamSubscription<List<int>> subscription) {
    _responseSubscription = subscription;
    if (isAborted) {
      unawaited(cancelResponse());
    }
  }

  Future<void> abort() {
    if (!_abort.isCompleted) {
      _abort.complete();
    }
    return cancelResponse();
  }

  Future<void> cancelResponse() {
    final currentCancellation = _responseCancellation;
    if (currentCancellation != null) {
      return currentCancellation;
    }
    final subscription = _responseSubscription;
    if (subscription == null) {
      return Future<void>.value();
    }
    _responseSubscription = null;
    final cancellation = _cancelIgnoringErrors(subscription);
    _responseCancellation = cancellation;
    return cancellation;
  }

  Future<void> _cancelIgnoringErrors(
    StreamSubscription<List<int>> subscription,
  ) async {
    try {
      await subscription.cancel();
    } on Object {
      // Aborting a probe is best effort and must not escape assessment.
    }
  }
}
