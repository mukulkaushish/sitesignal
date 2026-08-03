import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_signal/features/monitoring/domain/entities/monitor_fleet_summary.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/desktop_bridge.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

abstract interface class NotificationSoundPreviewPlayer {
  Future<void> playAsset(String fileName);

  Future<void> stop();

  Future<void> dispose();
}

typedef DashboardMenuAction = ({String key, String label});

@visibleForTesting
DashboardMenuAction dashboardMenuActionForVisibility(bool visible) => visible
    ? (key: 'hide_window', label: 'Hide Dashboard')
    : (key: 'show_window', label: 'Show Dashboard');

abstract final class AndroidNotificationSoundConfiguration {
  static const _description = 'Outage and recovery alerts for monitored sites';

  static AndroidNotificationChannel channel(
    NotificationSoundPreference preference,
  ) {
    final profile = preference.profile;
    final playSound = preference.playsSound;
    return AndroidNotificationChannel(
      profile.androidChannelId,
      profile.androidChannelName,
      description: _description,
      importance: Importance.high,
      playSound: playSound,
      sound: profile.resourceName == null
          ? null
          : RawResourceAndroidNotificationSound(profile.resourceName),
      enableVibration: playSound,
      showBadge: true,
    );
  }

  static AndroidNotificationDetails details({
    required NotificationSoundPreference preference,
    required bool suppressSound,
    required int number,
  }) {
    final playSound = preference.playsSound && !suppressSound;
    final profile = suppressSound
        ? NotificationSoundPreference.silent.profile
        : preference.profile;
    return AndroidNotificationDetails(
      profile.androidChannelId,
      profile.androidChannelName,
      channelDescription: _description,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.status,
      icon: 'ic_notification',
      playSound: playSound,
      sound: !playSound || profile.resourceName == null
          ? null
          : RawResourceAndroidNotificationSound(profile.resourceName),
      enableVibration: playSound,
      silent: !playSound,
      number: number,
    );
  }
}

class DesktopAppBridge
    with TrayListener, WindowListener
    implements DesktopBridge {
  factory DesktopAppBridge({
    NotificationSoundPreviewPlayer Function()? soundPreviewPlayerFactory,
    Future<bool> Function()? systemNotificationSoundPlayer,
    Future<void> Function()? systemNotificationSoundStopper,
  }) {
    return DesktopAppBridge._(
      soundPreviewPlayerFactory ?? _AudioNotificationSoundPlayer.new,
      systemNotificationSoundPlayer,
      systemNotificationSoundStopper,
    );
  }

  DesktopAppBridge._(
    this._soundPreviewPlayerFactory,
    this._systemNotificationSoundPlayer,
    this._systemNotificationSoundStopper,
  );

  static const _neutralIcon = 'assets/tray_icon.png';
  static const _healthyIcon = 'assets/tray_icon_up.png';
  static const _downIcon = 'assets/tray_icon_down.png';
  static const _pausedIcon = 'assets/tray_icon_paused.png';
  static const _windowsIcon = 'windows/runner/resources/app_icon.ico';
  static const _desktopChannel = MethodChannel('dev.sitesignal.app/desktop');
  static const _notificationPermissionRequestedKey =
      'notification_permission_requested';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final NotificationSoundPreviewPlayer Function() _soundPreviewPlayerFactory;
  final Future<bool> Function()? _systemNotificationSoundPlayer;
  final Future<void> Function()? _systemNotificationSoundStopper;

  Future<void> Function()? _onCheckAll;
  Future<void> Function()? _onTogglePaused;
  Future<void> Function()? _onQuitRequested;
  Map<String, SiteMonitor> _sitesById = <String, SiteMonitor>{};
  List<SiteMonitor> _lastSites = const <SiteMonitor>[];
  bool _lastPaused = false;
  String? _currentIcon;
  int _downCount = 0;
  bool _initialized = false;
  bool _quitting = false;
  bool? _windowVisible;
  final Map<String, Future<void>> _notificationChains =
      <String, Future<void>>{};
  Future<NotificationPermission>? _permissionRequest;
  NotificationSoundPreviewPlayer? _soundPreviewPlayer;
  Future<void> _soundPreviewQueue = Future<void>.value();
  int _soundPreviewGeneration = 0;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  bool get _supportsNotifications =>
      !kIsWeb &&
      (Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows);

  @override
  Future<void> initialize({
    required Future<void> Function() onCheckAll,
    required Future<void> Function() onTogglePaused,
    required Future<void> Function() onQuitRequested,
  }) async {
    _onCheckAll = onCheckAll;
    _onTogglePaused = onTogglePaused;
    _onQuitRequested = onQuitRequested;
    if (!_supportsNotifications || _initialized) {
      return;
    }

    var listenersAdded = false;
    try {
      if (_isDesktop) {
        launchAtStartup.setup(
          appName: 'SiteSignal',
          appPath: Platform.resolvedExecutable,
          packageName: 'dev.sitesignal.app',
        );
      }
      await _prepareNotificationSounds();

      await _notifications.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('ic_notification'),
          iOS: const DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            defaultPresentAlert: true,
            defaultPresentBadge: true,
            defaultPresentSound: true,
            defaultPresentBanner: true,
            defaultPresentList: true,
          ),
          macOS: const DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            defaultPresentAlert: true,
            defaultPresentBadge: true,
            defaultPresentSound: true,
            defaultPresentBanner: true,
            defaultPresentList: true,
          ),
          linux: LinuxInitializationSettings(
            defaultActionName: 'Open SiteSignal',
            defaultIcon: AssetsLinuxIcon(_neutralIcon),
          ),
          windows: _windowsInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (_) {
          if (_isDesktop) {
            showWindow().detachPlatformCallback('notification activation');
          }
        },
      );
      await _createAndroidNotificationChannels();

      if (_isDesktop) {
        await _setTrayIcon(_neutralIcon);
        if (Platform.isMacOS || Platform.isWindows) {
          await trayManager.setToolTip('SiteSignal website health');
        }
        trayManager.addListener(this);
        windowManager.addListener(this);
        listenersAdded = true;
        // Close-to-tray is enabled only after the tray is known to be usable.
        await windowManager.setPreventClose(true);
        _windowVisible = await windowManager.isVisible();
      }
      _initialized = true;
    } on Object {
      if (_isDesktop) {
        if (listenersAdded) {
          trayManager.removeListener(this);
          windowManager.removeListener(this);
        }
        try {
          await windowManager.setPreventClose(false);
        } on Object {
          // A normal close remains the intended fallback after partial setup.
        }
        try {
          await trayManager.destroy();
        } on Object {
          // The failed setup may not have created a tray resource.
        }
        _currentIcon = null;
      }
      rethrow;
    }
  }

  @override
  Future<void> updateMenu({
    required List<SiteMonitor> sites,
    required bool paused,
  }) async {
    final summary = sites.fleetSummary;
    _downCount = summary.downCount;
    await _setAppBadge(summary.downCount);
    if (!_isDesktop) {
      return;
    }
    _lastSites = List<SiteMonitor>.unmodifiable(sites);
    _lastPaused = paused;
    _sitesById = <String, SiteMonitor>{for (final site in sites) site.id: site};
    final windowVisible = _windowVisible ??= await windowManager.isVisible();
    final dashboardAction = dashboardMenuActionForVisibility(windowVisible);

    final statusLabel = paused
        ? 'Monitoring paused'
        : switch (summary.state) {
            MonitorFleetState.down =>
              '${summary.downCount} site${summary.downCount == 1 ? '' : 's'} down',
            MonitorFleetState.noEnabledSites => 'No sites configured',
            MonitorFleetState.checking =>
              'Checking ${summary.unknownCount} site${summary.unknownCount == 1 ? '' : 's'}',
            MonitorFleetState.healthy =>
              'All ${summary.healthyCount} site${summary.healthyCount == 1 ? '' : 's'} healthy',
          };

    final items = <MenuItem>[
      MenuItem(label: 'SiteSignal — $statusLabel', disabled: true),
      MenuItem.separator(),
      for (final site in sites.take(10))
        MenuItem(
          key: 'site:${site.id}',
          label: '${_statusGlyph(site, paused)}  ${site.name}',
          sublabel: _siteSublabel(site),
          disabled: !site.enabled,
        ),
      if (sites.isEmpty)
        MenuItem(label: 'Add a site from the dashboard', disabled: true),
      if (sites.isNotEmpty) MenuItem.separator(),
      MenuItem(key: dashboardAction.key, label: dashboardAction.label),
      MenuItem(
        key: 'check_all',
        label: 'Check All Now',
        disabled: summary.enabledCount == 0,
      ),
      MenuItem(
        key: 'toggle_paused',
        label: paused ? 'Resume Monitoring' : 'Pause Monitoring',
        disabled: summary.enabledCount == 0,
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: 'Quit SiteSignal'),
    ];
    await trayManager.setContextMenu(Menu(items: items));

    final icon = paused
        ? _pausedIcon
        : switch (summary.state) {
            MonitorFleetState.down => _downIcon,
            MonitorFleetState.healthy => _healthyIcon,
            MonitorFleetState.noEnabledSites ||
            MonitorFleetState.checking => _neutralIcon,
          };
    await _setTrayIcon(icon);

    if (Platform.isMacOS) {
      await trayManager.setTitle(
        paused
            ? ' Ⅱ'
            : summary.downCount > 0
            ? ' ${summary.downCount}'
            : '',
      );
      await trayManager.setToolTip('SiteSignal — $statusLabel');
    } else if (Platform.isWindows) {
      await trayManager.setToolTip('SiteSignal — $statusLabel');
    }
  }

  @override
  Future<NotificationPermission> notificationPermission() async {
    if (!_supportsNotifications) {
      return NotificationPermission.unsupported;
    }
    if (Platform.isLinux || Platform.isWindows) {
      return NotificationPermission.authorized;
    }

    if (Platform.isAndroid) {
      final enabled = await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
      if (enabled == null) {
        return NotificationPermission.unsupported;
      }
      if (enabled) {
        return NotificationPermission.authorized;
      }
      return await _hasRequestedNotificationPermission()
          ? NotificationPermission.denied
          : NotificationPermission.notDetermined;
    }

    final permissions = Platform.isIOS
        ? await _notifications
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions()
        : await _notifications
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions();
    if (permissions == null) {
      return NotificationPermission.unsupported;
    }
    if (permissions.isProvisionalEnabled) {
      return NotificationPermission.provisional;
    }
    if (permissions.isEnabled) {
      return NotificationPermission.authorized;
    }
    return await _hasRequestedNotificationPermission()
        ? NotificationPermission.denied
        : NotificationPermission.notDetermined;
  }

  @override
  Future<NotificationPermission> requestNotificationPermission() async {
    final inFlight = _permissionRequest;
    if (inFlight != null) {
      return inFlight;
    }
    final operation = _requestNotificationPermission();
    _permissionRequest = operation;
    try {
      return await operation;
    } finally {
      if (identical(_permissionRequest, operation)) {
        _permissionRequest = null;
      }
    }
  }

  @override
  Future<bool?> launchAtStartupEnabled() async {
    if (!_isDesktop) {
      return null;
    }
    try {
      return await launchAtStartup.isEnabled();
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      if (error.code == 'launch_at_startup_unsupported') {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<bool> setLaunchAtStartupEnabled(bool enabled) async {
    if (!_isDesktop) {
      throw UnsupportedError('Launch at startup is desktop-only.');
    }
    final changed = enabled
        ? await launchAtStartup.enable()
        : await launchAtStartup.disable();
    if (!changed) {
      return false;
    }
    return launchAtStartup.isEnabled();
  }

  Future<NotificationPermission> _requestNotificationPermission() async {
    if (!_supportsNotifications) {
      return NotificationPermission.unsupported;
    }
    if (Platform.isLinux || Platform.isWindows) {
      return NotificationPermission.authorized;
    }

    // The native APIs expose the current enabled state, but not consistently
    // whether the prompt was already shown. Remember the attempt before opening
    // the OS dialog so an interrupted process cannot create a prompt loop.
    await _rememberNotificationPermissionRequest();

    if (Platform.isAndroid) {
      final granted = await _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return granted == true
          ? NotificationPermission.authorized
          : NotificationPermission.denied;
    }

    final granted = Platform.isIOS
        ? await _notifications
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true)
        : await _notifications
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true);
    return granted == true
        ? NotificationPermission.authorized
        : NotificationPermission.denied;
  }

  Future<bool> _hasRequestedNotificationPermission() async {
    try {
      return await SharedPreferencesAsync().getBool(
            _notificationPermissionRequestedKey,
          ) ??
          false;
    } on Object {
      // If preferences are temporarily unavailable, prefer the recoverable
      // first-run path. The request itself remains serialized above.
      return false;
    }
  }

  Future<void> _rememberNotificationPermissionRequest() async {
    try {
      await SharedPreferencesAsync().setBool(
        _notificationPermissionRequestedKey,
        true,
      );
    } on Object {
      // Permission prompting must still work when preferences are unavailable.
    }
  }

  @override
  Future<void> playNotificationSoundPreview(
    NotificationSoundPreference soundPreference,
  ) {
    final generation = ++_soundPreviewGeneration;
    final previous = _soundPreviewQueue;
    final operation = () async {
      try {
        await previous;
      } on Object {
        // A failed preview must not prevent the next selection from playing.
      }
      if (_quitting || generation != _soundPreviewGeneration) {
        return;
      }

      final existingPlayer = _soundPreviewPlayer;
      if (existingPlayer != null) {
        await existingPlayer.stop();
      }
      await _stopSystemNotificationSound();
      if (_quitting || generation != _soundPreviewGeneration) {
        return;
      }
      if (soundPreference == NotificationSoundPreference.system) {
        await _playSystemNotificationSound();
        return;
      }
      final fileName = soundPreference.profile.fileName;
      if (fileName == null || !soundPreference.playsSound) {
        return;
      }
      if (_quitting || generation != _soundPreviewGeneration) {
        return;
      }

      final player = existingPlayer ?? _soundPreviewPlayerFactory();
      _soundPreviewPlayer = player;
      await player.playAsset(fileName);
    }();
    _soundPreviewQueue = operation;
    return operation;
  }

  Future<void> _playSystemNotificationSound() async {
    final injectedPlayer = _systemNotificationSoundPlayer;
    if (injectedPlayer != null && await injectedPlayer()) {
      return;
    }
    if (Platform.isAndroid || Platform.isMacOS) {
      try {
        final played = await _desktopChannel.invokeMethod<bool>(
          'playSystemNotificationSound',
        );
        if (played == true) {
          return;
        }
      } on PlatformException {
        // Fall through to Flutter's desktop system-alert implementation.
      } on MissingPluginException {
        // Fall through to Flutter's desktop system-alert implementation.
      }
      if (Platform.isAndroid) {
        throw StateError('No system notification sound is available.');
      }
    }
    await SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _stopSystemNotificationSound() async {
    final injectedStopper = _systemNotificationSoundStopper;
    if (injectedStopper != null) {
      await injectedStopper();
      return;
    }
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _desktopChannel.invokeMethod<bool>('stopSystemNotificationSound');
    } on MissingPluginException {
      // A bundled sound can still be previewed by an older native runner.
    }
  }

  @override
  Future<void> showNotification({
    required String notificationKey,
    required String title,
    required String body,
    required NotificationSoundPreference soundPreference,
    bool suppressSound = false,
  }) async {
    if (!_supportsNotifications) {
      return;
    }
    final normalizedKey = notificationKey.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(
        notificationKey,
        'notificationKey',
        'A notification key is required.',
      );
    }
    final previousNotification = _notificationChains[normalizedKey];
    final completed = Completer<void>();
    _notificationChains[normalizedKey] = completed.future;
    await previousNotification;
    try {
      await _showFreshNotification(
        notificationKey: normalizedKey,
        title: title,
        body: body,
        soundPreference: soundPreference,
        suppressSound: suppressSound,
      );
    } finally {
      completed.complete();
      if (identical(_notificationChains[normalizedKey], completed.future)) {
        unawaited(_notificationChains.remove(normalizedKey));
      }
    }
  }

  Future<void> _showFreshNotification({
    required String notificationKey,
    required String title,
    required String body,
    required NotificationSoundPreference soundPreference,
    required bool suppressSound,
  }) async {
    final notificationId = _notificationIdForKey(notificationKey);
    final soundProfile = soundPreference.profile;
    final playSound = soundPreference.playsSound && !suppressSound;

    // Removing only this stable slot makes the next show a fresh alert while
    // preserving the latest notifications for every other monitored site.
    await _notifications.cancel(id: notificationId);
    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: playSound,
      presentBanner: true,
      presentList: true,
      sound: playSound ? soundProfile.fileName : null,
      badgeNumber: _downCount,
      threadIdentifier: 'sitesignal-site-$notificationId',
      interruptionLevel: InterruptionLevel.active,
    );
    await _notifications.show(
      id: notificationId,
      title: title,
      body: body,
      payload: 'open-dashboard',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationSoundConfiguration.details(
          preference: soundPreference,
          suppressSound: suppressSound,
          number: _downCount,
        ),
        iOS: darwinDetails,
        macOS: darwinDetails,
        linux: LinuxNotificationDetails(
          sound: playSound ? soundPreference.linuxSound : null,
          suppressSound: !playSound,
          urgency: LinuxNotificationUrgency.normal,
          category: LinuxNotificationCategory.device,
        ),
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
          audio: playSound
              ? soundPreference.windowsAudio
              : WindowsNotificationAudio.silent(),
        ),
      ),
    );
  }

  int _notificationIdForKey(String notificationKey) {
    // Dart String.hashCode is not guaranteed to remain stable between
    // processes. FNV-1a gives each site a deterministic positive 31-bit slot,
    // allowing a new app process to replace that site's delivered alert too.
    var hash = 0x811C9DC5;
    for (final byte in utf8.encode(notificationKey)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final notificationId = hash & 0x7FFFFFFF;
    return notificationId == 0 ? 1 : notificationId;
  }

  Future<void> _prepareNotificationSounds() async {
    if (!Platform.isMacOS && !Platform.isIOS) {
      return;
    }
    // Belt-and-suspenders: the .wav files are also bundled directly into the
    // macOS app's Resources (the location `UNNotificationSound(named:)`
    // reliably resolves on macOS). This container-Library/Sounds copy mirrors
    // Apple's iOS-documented fallback location; failures here must not block
    // startup, but must not be invisible either, so log rather than swallow.
    try {
      final libraryDirectory = await getLibraryDirectory();
      final soundsDirectory = Directory(
        path.join(libraryDirectory.path, 'Sounds'),
      );
      await soundsDirectory.create(recursive: true);
      for (final preference in NotificationSoundPreference.values) {
        final profile = preference.profile;
        final assetPath = profile.assetPath;
        final fileName = profile.fileName;
        if (assetPath == null || fileName == null) {
          continue;
        }
        final asset = await rootBundle.load(assetPath);
        await File(path.join(soundsDirectory.path, fileName)).writeAsBytes(
          asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
          flush: true,
        );
      }
    } on Object catch (error) {
      if (kDebugMode) {
        debugPrint('Notification sound preparation failed: $error');
      }
    }
  }

  Future<void> _createAndroidNotificationChannels() async {
    if (!Platform.isAndroid) {
      return;
    }
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      return;
    }
    for (final preference in NotificationSoundPreference.values) {
      await android.createNotificationChannel(
        AndroidNotificationSoundConfiguration.channel(preference),
      );
    }
  }

  WindowsInitializationSettings _windowsInitializationSettings() {
    final iconPath = Platform.isWindows
        ? path.join(
            File(Platform.resolvedExecutable).parent.path,
            'data',
            'flutter_assets',
            _windowsIcon,
          )
        : null;
    return WindowsInitializationSettings(
      appName: 'SiteSignal',
      appUserModelId: 'SiteSignal.Desktop.App',
      guid: '58eb5ca9-581d-4c53-bb0c-d1a4363da6cd',
      iconPath: iconPath,
    );
  }

  Future<void> _setAppBadge(int count) async {
    if (!Platform.isMacOS) {
      return;
    }
    try {
      await _desktopChannel.invokeMethod<void>('setBadgeCount', count);
    } on PlatformException {
      // A Dock badge is supplementary; tray state remains the primary status.
    } on MissingPluginException {
      // Keep older runners usable if the Dart bundle is updated independently.
    }
  }

  @override
  Future<void> openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw ArgumentError('Could not open $url.');
    }
  }

  @override
  Future<bool> openNotificationSettings() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _desktopChannel.invokeMethod<bool>(
            'openNotificationSettings',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> showWindow() async {
    if (!_isDesktop) {
      return;
    }
    _windowVisible = true;
    // Restore the Dock/taskbar presence before showing, so the window can
    // become key/frontmost normally.
    try {
      await windowManager.setSkipTaskbar(false);
      await windowManager.show();
      await windowManager.focus();
    } on Object {
      _windowVisible = null;
      rethrow;
    }
    await _refreshMenu();
  }

  Future<void> hideWindow() async {
    if (!_isDesktop) {
      return;
    }
    // Keep the menu tied to the requested state. On macOS, isVisible() can
    // briefly report the old value after orderOut/hide completes.
    _windowVisible = false;
    // macOS only orders out a window once it's no longer key; hiding it while
    // it's still focused silently no-ops on the first call.
    try {
      if (Platform.isMacOS) {
        await windowManager.blur();
      }
      await windowManager.hide();
      // Drop the Dock icon/taskbar entry too; the tray icon remains the way
      // back in, matching a proper background/menu-bar-only app.
      await windowManager.setSkipTaskbar(true);
    } on Object {
      _windowVisible = null;
      rethrow;
    }
    await _refreshMenu();
  }

  Future<void> _refreshMenu() {
    if (!_initialized || _quitting) {
      return Future<void>.value();
    }
    return updateMenu(sites: _lastSites, paused: _lastPaused);
  }

  Future<void> _setTrayIcon(String icon) async {
    if (_currentIcon == icon) {
      return;
    }
    await trayManager.setIcon(
      Platform.isWindows ? _windowsIcon : icon,
      // Template mode forces macOS to render the icon monochrome, which would
      // strip the green/red/gray status color these assets exist to show.
      isTemplate: false,
    );
    _currentIcon = icon;
  }

  String _statusGlyph(SiteMonitor site, bool paused) {
    if (!site.enabled || paused) {
      return '⚪';
    }
    return switch (site.status) {
      HealthStatus.up => '🟢',
      HealthStatus.down => '🔴',
      HealthStatus.unknown => '⚪',
    };
  }

  String _siteSublabel(SiteMonitor site) {
    if (!site.enabled) {
      return 'Disabled';
    }
    final latest = site.latestCheck;
    if (latest == null) {
      return site.host;
    }
    if (latest.status == HealthStatus.down) {
      return latest.error ?? 'Unavailable';
    }
    return latest.responseTimeMs == null
        ? site.host
        : '${latest.responseTimeMs} ms';
  }

  @override
  void onTrayIconMouseDown() {
    if (Platform.isMacOS) {
      trayManager.popUpContextMenu().detachPlatformCallback(
        'tray context menu',
      );
    } else if (Platform.isWindows) {
      showWindow().detachPlatformCallback('tray window activation');
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (Platform.isMacOS) {
      trayManager.popUpContextMenu().detachPlatformCallback(
        'tray context menu',
      );
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    _handleMenuItem(menuItem.key).detachPlatformCallback('tray menu action');
  }

  Future<void> _handleMenuItem(String? key) async {
    switch (key) {
      case 'show_window':
        await showWindow();
      case 'hide_window':
        await hideWindow();
      case 'check_all':
        await _onCheckAll?.call();
      case 'toggle_paused':
        await _onTogglePaused?.call();
      case 'quit':
        _quitting = true;
        await _onQuitRequested?.call();
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
        exit(0);
      default:
        if (key case final value? when value.startsWith('site:')) {
          final site = _sitesById[value.substring(5)];
          if (site != null) {
            await openUrl(site.baseUrl);
          }
        }
    }
  }

  @override
  void onWindowClose() {
    if (!_quitting) {
      hideWindow().detachPlatformCallback('window close');
    }
  }

  @override
  void dispose() {
    _quitting = true;
    _soundPreviewGeneration += 1;
    final soundPreviewPlayer = _soundPreviewPlayer;
    _soundPreviewPlayer = null;
    soundPreviewPlayer?.dispose().detachPlatformCallback(
      'sound preview disposal',
    );
    _onQuitRequested = null;
    if (_isDesktop) {
      trayManager.removeListener(this);
      windowManager.removeListener(this);
    }
  }
}

final class _AudioNotificationSoundPlayer
    implements NotificationSoundPreviewPlayer {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> playAsset(String fileName) {
    return _player.play(AssetSource(fileName));
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

extension _PlatformNotificationSound on NotificationSoundPreference {
  LinuxNotificationSound? get linuxSound {
    final assetPath = profile.assetPath;
    if (assetPath != null) {
      return AssetsLinuxSound(assetPath);
    }
    return playsSound ? ThemeLinuxSound('message') : null;
  }

  WindowsNotificationAudio get windowsAudio {
    final assetPath = profile.assetPath;
    if (assetPath != null) {
      return WindowsNotificationAudio.asset(
        assetPath,
        fallback: WindowsNotificationSound.defaultSound,
      );
    }
    return playsSound
        ? WindowsNotificationAudio.preset(
            sound: WindowsNotificationSound.defaultSound,
          )
        : WindowsNotificationAudio.silent();
  }
}

extension _ContainedPlatformCallback on Future<void> {
  void detachPlatformCallback(String operation) {
    unawaited(
      onError((Object error, StackTrace stackTrace) {
        debugPrint('Could not complete $operation: $error');
      }),
    );
  }
}
