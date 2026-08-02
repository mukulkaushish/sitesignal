import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/data/desktop_app_bridge.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';

void main() {
  test(
    'keeps one fresh notification per site without clearing other sites',
    () async {
      final notifications = _RecordingNotificationsPlatform();
      FlutterLocalNotificationsPlatform.instance = notifications;
      debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final bridge = DesktopAppBridge();

      await Future.wait(<Future<void>>[
        bridge.showNotification(
          notificationKey: 'site:api',
          title: '🔴 API is down',
          body: 'HTTP 503.',
          soundPreference: NotificationSoundPreference.siteSignal,
        ),
        bridge.showNotification(
          notificationKey: 'site:shop',
          title: '🔴 Shop is down',
          body: 'Connection timed out.',
          soundPreference: NotificationSoundPreference.siteSignal,
        ),
        bridge.showNotification(
          notificationKey: 'site:api',
          title: '🟢 API is back online',
          body: 'HTTP 200 · 25 ms.',
          soundPreference: NotificationSoundPreference.siteSignal,
        ),
      ]);

      // Different sites notify concurrently now (only same-site calls are
      // serialized), so only per-site event order is guaranteed, not
      // interleaving between site:api and site:shop.
      final apiId = notifications.activeIds.firstWhere(
        (id) => notifications.activeTitles[id] == '🟢 API is back online',
      );
      final shopId = notifications.activeIds.firstWhere((id) => id != apiId);

      expect(notifications.shownIds.where((id) => id == apiId).length, 2);
      expect(notifications.shownIds.where((id) => id == shopId).length, 1);
      expect(
        notifications.events.where((event) => event.endsWith(':$apiId')),
        <String>[
          'cancel:$apiId',
          'show:$apiId',
          'cancel:$apiId',
          'show:$apiId',
        ],
      );
      expect(
        notifications.events.where((event) => event.endsWith(':$shopId')),
        <String>['cancel:$shopId', 'show:$shopId'],
      );
      expect(notifications.activeIds, <int>{apiId, shopId});
      expect(notifications.activeTitles[apiId], '🟢 API is back online');
      expect(notifications.activeTitles[shopId], '🔴 Shop is down');
    },
  );
}

class _RecordingNotificationsPlatform
    extends FlutterLocalNotificationsPlatform {
  final List<String> events = <String>[];
  final List<int> shownIds = <int>[];
  final Set<int> activeIds = <int>{};
  final Map<int, String?> activeTitles = <int, String?>{};

  @override
  Future<void> cancel({required int id}) async {
    events.add('cancel:$id');
    activeIds.remove(id);
    activeTitles.remove(id);
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
  }) async {
    events.add('show:$id');
    shownIds.add(id);
    activeIds.add(id);
    activeTitles[id] = title;
  }
}
