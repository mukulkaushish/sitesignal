import 'dart:convert';

import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/background_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';
import 'package:site_signal/features/monitoring/domain/services/monitoring_policy.dart';

class BackgroundMonitorSnapshotCodec {
  const BackgroundMonitorSnapshotCodec._();

  static const schemaVersion = 2;

  static String encode(BackgroundMonitorSnapshot snapshot) {
    return jsonEncode(<String, Object?>{
      'schemaVersion': schemaVersion,
      'updatedAt': snapshot.updatedAt.toUtc().toIso8601String(),
      'paused': snapshot.paused,
      'notificationSoundPreference': snapshot.notificationSoundPreference.name,
      'connectivity': _connectivityToJson(snapshot.connectivity),
      'sites': snapshot.sites.map(_siteToJson).toList(growable: false),
    });
  }

  static BackgroundMonitorSnapshot? decode(String? source) {
    if (source == null || source.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != schemaVersion) {
        return null;
      }
      final rawSites = decoded['sites'];
      if (rawSites is! List) {
        return null;
      }
      final sites = <SiteMonitor>[];
      for (final rawSite in rawSites) {
        if (rawSite is Map<String, dynamic>) {
          final site = _siteFromJson(rawSite);
          if (site != null) {
            sites.add(site);
          }
        }
      }
      return BackgroundMonitorSnapshot(
        sites: List<SiteMonitor>.unmodifiable(sites),
        paused: decoded['paused'] == true,
        notificationSoundPreference: NotificationSoundPreference.fromName(
          decoded['notificationSoundPreference'] as String?,
        ),
        updatedAt:
            DateTime.tryParse(decoded['updatedAt'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        connectivity: _connectivityFromJson(decoded['connectivity']),
      );
    } on Object {
      return null;
    }
  }

  static Map<String, Object?> _siteToJson(SiteMonitor site) {
    return <String, Object?>{
      'id': site.id,
      'name': site.name,
      'baseUrl': site.baseUrl,
      'probeUrl': site.probeUrl,
      'faviconUrl': site.faviconUrl,
      'intervalSeconds': site.intervalSeconds,
      'enabled': site.enabled,
      'status': site.status.name,
      'createdAt': site.createdAt.toUtc().toIso8601String(),
      'lastCheck': _recordToJson(site.lastCheck),
      'history': site.history.map(_recordToJson).toList(growable: false),
    };
  }

  static SiteMonitor? _siteFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final baseUrl = json['baseUrl'] as String? ?? '';
    if (id.isEmpty || baseUrl.isEmpty) {
      return null;
    }
    final history = <CheckRecord>[];
    final rawHistory = json['history'];
    if (rawHistory is List) {
      for (final rawRecord in rawHistory) {
        if (rawRecord is Map<String, dynamic>) {
          final record = _recordFromJson(rawRecord);
          if (record != null) {
            history.add(record);
          }
        }
      }
    }
    final rawLastCheck = json['lastCheck'];
    final lastCheck = rawLastCheck is Map<String, dynamic>
        ? _recordFromJson(rawLastCheck)
        : null;
    return SiteMonitor(
      id: id,
      name: json['name'] as String? ?? Uri.tryParse(baseUrl)?.host ?? baseUrl,
      baseUrl: baseUrl,
      probeUrl: json['probeUrl'] as String?,
      faviconUrl: json['faviconUrl'] as String?,
      intervalSeconds: MonitoringPolicy.normalizeIntervalSeconds(
        (json['intervalSeconds'] as num?)?.toInt() ??
            MonitoringPolicy.defaultIntervalSeconds,
      ),
      enabled: json['enabled'] == true,
      status: HealthStatus.fromName(json['status'] as String?),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      lastCheck: lastCheck,
      history: List<CheckRecord>.unmodifiable(
        history.take(defaultMonitorHistoryLimit),
      ),
    );
  }

  static Map<String, Object?>? _recordToJson(CheckRecord? record) {
    if (record == null) {
      return null;
    }
    return <String, Object?>{
      'checkedAt': record.checkedAt.toUtc().toIso8601String(),
      'status': record.status.name,
      'responseTimeMs': record.responseTimeMs,
      'statusCode': record.statusCode,
      'error': record.error,
      'checkedUrl': record.checkedUrl,
      'failureDetail': record.failureDetail,
    };
  }

  static CheckRecord? _recordFromJson(Map<String, dynamic> json) {
    final checkedAt = DateTime.tryParse(json['checkedAt'] as String? ?? '');
    final checkedUrl = json['checkedUrl'] as String? ?? '';
    if (checkedAt == null || checkedUrl.isEmpty) {
      return null;
    }
    return CheckRecord(
      checkedAt: checkedAt.toUtc(),
      status: HealthStatus.fromName(json['status'] as String?),
      responseTimeMs: (json['responseTimeMs'] as num?)?.toInt(),
      statusCode: (json['statusCode'] as num?)?.toInt(),
      error: json['error'] as String?,
      checkedUrl: checkedUrl,
      failureDetail: json['failureDetail'] as String?,
    );
  }

  static Map<String, Object?> _connectivityToJson(
    ConnectivityAssessment assessment,
  ) {
    return <String, Object?>{
      'availability': assessment.availability.name,
      'issue': assessment.issue.name,
      'transports': assessment.transports
          .map((transport) => transport.name)
          .toList(growable: false),
      'checkedAt': assessment.checkedAt?.toUtc().toIso8601String(),
    };
  }

  static ConnectivityAssessment _connectivityFromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return const ConnectivityAssessment.unknown();
    }
    final availability = InternetAvailability.values.firstWhere(
      (item) => item.name == value['availability'],
      orElse: () => InternetAvailability.unknown,
    );
    final issue = ConnectivityIssue.values.firstWhere(
      (item) => item.name == value['issue'],
      orElse: () => ConnectivityIssue.none,
    );
    final transports = <NetworkTransport>[];
    final rawTransports = value['transports'];
    if (rawTransports is List) {
      for (final rawTransport in rawTransports.whereType<String>()) {
        transports.add(
          NetworkTransport.values.firstWhere(
            (item) => item.name == rawTransport,
            orElse: () => NetworkTransport.unknown,
          ),
        );
      }
    }
    return ConnectivityAssessment(
      availability: availability,
      issue: issue,
      transports: List<NetworkTransport>.unmodifiable(transports),
      checkedAt: DateTime.tryParse(
        value['checkedAt'] as String? ?? '',
      )?.toUtc(),
    );
  }
}
