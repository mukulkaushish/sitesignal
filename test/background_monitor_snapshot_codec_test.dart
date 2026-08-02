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
            faviconUrl: null,
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

      final decoded = BackgroundMonitorSnapshotCodec.decode(
        BackgroundMonitorSnapshotCodec.encode(snapshot),
      );

      expect(decoded, isNotNull);
      final restored = decoded;
      expect(restored?.sites.single.lastCheck?.statusCode, 200);
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
}
