enum HealthStatus {
  unknown,
  up,
  down;

  static HealthStatus fromName(String? value) {
    return HealthStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => HealthStatus.unknown,
    );
  }
}

const int defaultMonitorHistoryLimit = 100;

extension HealthStatusLabel on HealthStatus {
  String get label => switch (this) {
    HealthStatus.unknown => 'Checking',
    HealthStatus.up => 'Up',
    HealthStatus.down => 'Down',
  };
}

class CheckRecord {
  const CheckRecord({
    required this.checkedAt,
    required this.status,
    required this.responseTimeMs,
    required this.statusCode,
    required this.error,
    required this.checkedUrl,
    this.failureDetail,
  });

  final DateTime checkedAt;
  final HealthStatus status;
  final int? responseTimeMs;
  final int? statusCode;
  final String? error;
  final String checkedUrl;
  final String? failureDetail;
}

extension CheckRecordHistory on Iterable<CheckRecord> {
  /// Merges newest-first transition histories without duplicate states.
  List<CheckRecord> mergeTransitions(
    Iterable<CheckRecord> other, {
    int limit = defaultMonitorHistoryLimit,
  }) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final records = <CheckRecord>[...this, ...other]
      ..sort((first, second) {
        final timeOrder = first.checkedAt.toUtc().compareTo(
          second.checkedAt.toUtc(),
        );
        return timeOrder != 0
            ? timeOrder
            : first.status.index.compareTo(second.status.index);
      });
    final transitions = <CheckRecord>[];
    final seen = <(int, HealthStatus, int?, String)>{};
    for (final record in records) {
      final key = (
        record.checkedAt.toUtc().microsecondsSinceEpoch,
        record.status,
        record.statusCode,
        record.checkedUrl,
      );
      if (!seen.add(key)) {
        continue;
      }
      if (transitions.isEmpty || transitions.last.status != record.status) {
        transitions.add(record);
      }
    }
    return transitions.reversed.take(limit).toList(growable: false);
  }
}

class SiteMonitor {
  const SiteMonitor({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.probeUrl,
    required this.faviconUrl,
    required this.intervalSeconds,
    required this.enabled,
    required this.status,
    required this.createdAt,
    required this.history,
    this.lastCheck,
  });

  final String id;
  final String name;

  /// Normalized origin supplied by the user, without a path or query.
  final String baseUrl;

  /// Last automatically discovered healthy endpoint. Null means discovery has
  /// not succeeded yet; the checker will try the bounded candidate set.
  final String? probeUrl;

  /// Resolved page icon URL. The UI always retains a local fallback for sites
  /// without an icon or whose remote image later becomes unavailable.
  final String? faviconUrl;

  final int intervalSeconds;
  final bool enabled;
  final HealthStatus status;
  final DateTime createdAt;

  /// Most recent probe result, including repeated states. This is deliberately
  /// separate from [history], which contains only initial/transition events.
  final CheckRecord? lastCheck;

  /// Initial state and subsequent status changes, newest first.
  final List<CheckRecord> history;

  CheckRecord? get latestCheck =>
      lastCheck ?? (history.isEmpty ? null : history.first);

  double? uptimePercentAt(DateTime asOf) {
    if (history.isEmpty) {
      return null;
    }

    final transitions = history.reversed.toList(growable: false);
    final end = asOf.toUtc();
    final start = transitions.first.checkedAt.toUtc();
    if (!end.isAfter(start)) {
      return transitions.first.status == HealthStatus.up ? 100 : 0;
    }

    var healthyMilliseconds = 0;
    for (var index = 0; index < transitions.length; index++) {
      final intervalStart = transitions[index].checkedAt.toUtc();
      final intervalEnd = index + 1 < transitions.length
          ? transitions[index + 1].checkedAt.toUtc()
          : end;
      if (transitions[index].status == HealthStatus.up &&
          intervalEnd.isAfter(intervalStart)) {
        healthyMilliseconds += intervalEnd
            .difference(intervalStart)
            .inMilliseconds;
      }
    }
    final totalMilliseconds = end.difference(start).inMilliseconds;
    return ((healthyMilliseconds / totalMilliseconds) * 100)
        .clamp(0, 100)
        .toDouble();
  }

  double? get uptimePercent => uptimePercentAt(DateTime.now().toUtc());

  String get host {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) {
      return baseUrl;
    }
    return uri.host;
  }

  String get probeLabel {
    final probe = Uri.tryParse(probeUrl ?? '');
    if (probe == null || probe.path.isEmpty || probe.path == '/') {
      return 'Base URL';
    }
    return probe.path;
  }

  SiteMonitor copyWith({
    String? name,
    String? baseUrl,
    String? probeUrl,
    bool clearProbeUrl = false,
    String? faviconUrl,
    bool clearFaviconUrl = false,
    int? intervalSeconds,
    bool? enabled,
    HealthStatus? status,
    List<CheckRecord>? history,
    CheckRecord? lastCheck,
    bool clearLastCheck = false,
  }) {
    return SiteMonitor(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      probeUrl: clearProbeUrl ? null : probeUrl ?? this.probeUrl,
      faviconUrl: clearFaviconUrl ? null : faviconUrl ?? this.faviconUrl,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      enabled: enabled ?? this.enabled,
      status: status ?? this.status,
      createdAt: createdAt,
      history: List<CheckRecord>.unmodifiable(history ?? this.history),
      lastCheck: clearLastCheck ? null : lastCheck ?? this.lastCheck,
    );
  }

  static String normalizeBaseUrl(String input) {
    var normalized = input.trim();
    if (!normalized.contains('://')) {
      normalized = 'https://$normalized';
    }
    return normalizeOrigin(Uri.parse(normalized)).origin;
  }

  /// Scheme/host/port only, lowercased, dropping path/query/fragment/userinfo.
  /// Shared so origin comparisons agree across storage, health checks, and
  /// favicon discovery.
  static Uri normalizeOrigin(Uri uri) {
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
    );
  }

  static String? validateBaseUrl(String input) {
    final value = input.trim();
    if (value.isEmpty) {
      return 'Enter a base URL.';
    }
    if (value.length > 2048) {
      return 'The URL is too long.';
    }

    Uri? uri;
    try {
      var candidate = value;
      if (!candidate.contains('://')) {
        candidate = 'https://$candidate';
      }
      uri = Uri.parse(candidate);
    } on FormatException {
      return 'Enter a valid URL.';
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Only HTTP and HTTPS URLs are supported.';
    }
    if (uri.host.isEmpty || uri.host.contains(' ')) {
      return 'Enter a URL with a valid host.';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'URLs containing usernames or passwords are not supported.';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return 'Enter only the base URL, without a path.';
    }
    if (uri.hasQuery || uri.hasFragment) {
      return 'Enter only the base URL, without a query or fragment.';
    }
    return null;
  }
}
