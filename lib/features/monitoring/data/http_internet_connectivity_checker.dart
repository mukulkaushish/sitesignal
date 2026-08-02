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

  Future<bool> _anyProbeSucceeds() {
    final completed = Completer<bool>();
    var remaining = _probes.length;
    for (final probe in _probes) {
      unawaited(
        _runProbe(probe).then((reachable) {
          if (completed.isCompleted) {
            return;
          }
          if (reachable) {
            completed.complete(true);
            return;
          }
          remaining -= 1;
          if (remaining == 0) {
            completed.complete(false);
          }
        }),
      );
    }
    return completed.future;
  }

  Future<bool> _runProbe(_ReachabilityProbe probe) async {
    try {
      final request = http.Request('GET', Uri.parse(probe.uri))
        ..followRedirects = false
        ..headers.addAll(const <String, String>{
          'Accept': 'text/plain',
          'Cache-Control': 'no-cache',
          'User-Agent': 'SiteSignal/1.0 connectivity-check',
        });
      final response = await _client.send(request).timeout(timeout);
      if (response.statusCode != probe.expectedStatus) {
        await response.stream.drain<void>().timeout(timeout);
        return false;
      }
      if (probe.expectedBody == null) {
        await response.stream.drain<void>().timeout(timeout);
        return true;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        final remaining = 128 - bytes.length;
        if (remaining <= 0) {
          break;
        }
        bytes.addAll(
          chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
        );
      }
      return utf8.decode(bytes, allowMalformed: true).trim() ==
          probe.expectedBody;
    } on Object {
      return false;
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
