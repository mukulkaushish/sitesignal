enum InternetAvailability { unknown, online, offline }

enum ConnectivityIssue { none, noNetwork, noInternet }

enum NetworkTransport {
  wifi,
  mobile,
  ethernet,
  vpn,
  satellite,
  bluetooth,
  other,
  unknown,
}

abstract final class ConnectivityPolicy {
  static const Duration offlineRecheckInterval = Duration(seconds: 15);
  static const Duration onlineFreshness = Duration(seconds: 30);

  static Duration freshnessFor(InternetAvailability availability) {
    return availability == InternetAvailability.offline
        ? offlineRecheckInterval
        : onlineFreshness;
  }
}

class ConnectivityAssessment {
  const ConnectivityAssessment({
    required this.availability,
    required this.issue,
    required this.transports,
    required this.checkedAt,
  });

  const ConnectivityAssessment.unknown()
    : availability = InternetAvailability.unknown,
      issue = ConnectivityIssue.none,
      transports = const <NetworkTransport>[],
      checkedAt = null;

  final InternetAvailability availability;
  final ConnectivityIssue issue;
  final List<NetworkTransport> transports;
  final DateTime? checkedAt;
}

abstract interface class InternetConnectivityChecker {
  Stream<void> get changes;

  Future<ConnectivityAssessment> assess();

  void close();
}

class AssumedOnlineConnectivityChecker implements InternetConnectivityChecker {
  const AssumedOnlineConnectivityChecker();

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<ConnectivityAssessment> assess() async => ConnectivityAssessment(
    availability: InternetAvailability.online,
    issue: ConnectivityIssue.none,
    transports: const <NetworkTransport>[NetworkTransport.unknown],
    checkedAt: DateTime.now().toUtc(),
  );

  @override
  void close() {}
}
