import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/data/background_monitor_snapshot_codec.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/background_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';

void main() {
  test(
    'round-trips monitor and connectivity state for the background isolate',
    () {
      final checkedAt = DateTime.utc(2026, 8, 2, 12, 30);
      final record = CheckRecord(
        checkedAt: checkedAt,
        status: HealthStatus.up,
        responseTimeMs: 42,
        statusCode: 200,
        error: null,
        checkedUrl: 'https://example.com/health',
      );
      final snapshot = BackgroundMonitorSnapshot(
        sites: <SiteMonitor>[
          SiteMonitor(
            id: 'site-1',
            name: 'Example',
            baseUrl: 'https://example.com',
            probeUrl: 'https://example.com/health',
            faviconUrl: 'data:image/png;base64,legacy-payload',
            intervalSeconds: 60,
            enabled: true,
            status: HealthStatus.up,
            createdAt: DateTime.utc(2026, 1, 1),
            history: <CheckRecord>[record],
            lastCheck: record,
          ),
        ],
        paused: false,
        notificationSoundPreference: NotificationSoundPreference.beacon,
        updatedAt: checkedAt,
        connectivity: ConnectivityAssessment(
          availability: InternetAvailability.offline,
          issue: ConnectivityIssue.noInternet,
          transports: const <NetworkTransport>[
            NetworkTransport.wifi,
            NetworkTransport.vpn,
          ],
          checkedAt: checkedAt,
        ),
      );

      final encoded = BackgroundMonitorSnapshotCodec.encode(snapshot);
      final encodedJson = jsonDecode(encoded) as Map<String, dynamic>;
      final encodedSite = (encodedJson['sites'] as List).single;
      expect(encodedSite, isA<Map<String, dynamic>>());
      expect(
        (encodedSite as Map<String, dynamic>),
        isNot(contains('faviconUrl')),
      );
      expect(encoded, isNot(contains('legacy-payload')));

      final decoded = BackgroundMonitorSnapshotCodec.decode(encoded);

      expect(decoded, isNotNull);
      final restored = decoded;
      expect(restored?.sites.single.lastCheck?.statusCode, 200);
      expect(restored?.sites.single.faviconUrl, isNull);
      expect(
        restored?.notificationSoundPreference,
        NotificationSoundPreference.beacon,
      );
      expect(restored?.connectivity.availability, InternetAvailability.offline);
      expect(restored?.connectivity.issue, ConnectivityIssue.noInternet);
      expect(restored?.connectivity.transports, <NetworkTransport>[
        NetworkTransport.wifi,
        NetworkTransport.vpn,
      ]);
    },
  );

  test('rejects malformed or incompatible snapshots', () {
    expect(BackgroundMonitorSnapshotCodec.decode('not-json'), isNull);
    expect(
      BackgroundMonitorSnapshotCodec.decode('{"schemaVersion":999,"sites":[]}'),
      isNull,
    );
  });

  test('decodes old schema-v2 favicon fields without retaining them', () {
    final legacy = jsonEncode(<String, Object?>{
      'schemaVersion': 2,
      'updatedAt': DateTime.utc(2026, 8, 3).toIso8601String(),
      'paused': true,
      'sites': <Object?>[
        <String, Object?>{
          'id': 'legacy',
          'name': 'Legacy',
          'baseUrl': 'https://example.com',
          'faviconUrl': 'https://example.com/favicon.ico',
          'intervalSeconds': 60,
          'enabled': true,
          'status': 'unknown',
          'createdAt': DateTime.utc(2026, 8, 3).toIso8601String(),
          'history': <Object?>[],
        },
      ],
    });

    final decoded = BackgroundMonitorSnapshotCodec.decode(legacy);

    expect(decoded, isNotNull);
    expect(decoded?.sites.single.faviconUrl, isNull);
  });
}
