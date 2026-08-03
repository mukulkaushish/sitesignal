import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_signal/features/monitoring/data/desktop_app_bridge.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('preview routing stops prior system and bundled players', () async {
    final events = <String>[];
    final player = _RecordingSoundPreviewPlayer(events);
    var playerCreationCount = 0;
    final bridge = DesktopAppBridge(
      soundPreviewPlayerFactory: () {
        playerCreationCount += 1;
        return player;
      },
      systemNotificationSoundPlayer: () async {
        events.add('system:play');
        return true;
      },
      systemNotificationSoundStopper: () async {
        events.add('system:stop');
      },
    );
    addTearDown(bridge.dispose);

    await bridge.playNotificationSoundPreview(
      NotificationSoundPreference.system,
    );
    await bridge.playNotificationSoundPreview(
      NotificationSoundPreference.brightChime,
    );
    await bridge.playNotificationSoundPreview(
      NotificationSoundPreference.beacon,
    );
    await bridge.playNotificationSoundPreview(
      NotificationSoundPreference.silent,
    );

    expect(playerCreationCount, 1);
    expect(events, <String>[
      'system:stop',
      'system:play',
      'system:stop',
      'asset:site_signal_bright_chime.wav',
      'asset:stop',
      'system:stop',
      'asset:site_signal_beacon.wav',
      'asset:stop',
      'system:stop',
    ]);
  });

  test('maps selected sounds to Android channel and alert details', () {
    final customChannel = AndroidNotificationSoundConfiguration.channel(
      NotificationSoundPreference.brightChime,
    );
    final customDetails = AndroidNotificationSoundConfiguration.details(
      preference: NotificationSoundPreference.brightChime,
      suppressSound: false,
      number: 2,
    );

    expect(customChannel.id, endsWith('_v4'));
    expect(customChannel.playSound, isTrue);
    expect(customChannel.enableVibration, isTrue);
    expect(customChannel.sound, isA<RawResourceAndroidNotificationSound>());
    expect(customChannel.sound?.sound, 'site_signal_bright_chime');
    expect(customDetails.channelId, customChannel.id);
    expect(customDetails.playSound, isTrue);
    expect(customDetails.silent, isFalse);
    expect(customDetails.sound?.sound, 'site_signal_bright_chime');
    expect(
      customDetails.channelAction,
      AndroidNotificationChannelAction.createIfNotExists,
    );

    final systemChannel = AndroidNotificationSoundConfiguration.channel(
      NotificationSoundPreference.system,
    );
    final systemDetails = AndroidNotificationSoundConfiguration.details(
      preference: NotificationSoundPreference.system,
      suppressSound: false,
      number: 0,
    );

    expect(systemChannel.playSound, isTrue);
    expect(systemChannel.sound, isNull);
    expect(systemDetails.playSound, isTrue);
    expect(systemDetails.sound, isNull);
    expect(systemDetails.silent, isFalse);

    final silentChannel = AndroidNotificationSoundConfiguration.channel(
      NotificationSoundPreference.silent,
    );
    final suppressedCustom = AndroidNotificationSoundConfiguration.details(
      preference: NotificationSoundPreference.beacon,
      suppressSound: true,
      number: 0,
    );

    expect(silentChannel.playSound, isFalse);
    expect(silentChannel.sound, isNull);
    expect(silentChannel.enableVibration, isFalse);
    expect(
      suppressedCustom.channelId,
      NotificationSoundPreference.silent.profile.androidChannelId,
    );
    expect(suppressedCustom.playSound, isFalse);
    expect(suppressedCustom.sound, isNull);
    expect(suppressedCustom.silent, isTrue);
  });
}

class _RecordingSoundPreviewPlayer implements NotificationSoundPreviewPlayer {
  _RecordingSoundPreviewPlayer(this.events);

  final List<String> events;

  @override
  Future<void> dispose() async {
    events.add('asset:dispose');
  }

  @override
  Future<void> playAsset(String fileName) async {
    events.add('asset:$fileName');
  }

  @override
  Future<void> stop() async {
    events.add('asset:stop');
  }
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
