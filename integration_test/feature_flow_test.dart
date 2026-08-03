import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:site_signal/app/site_signal_app.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';

import '../test/support/demo_app.dart';
import '../test/support/fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exercises the complete responsive feature set', (tester) async {
    final bridge = FakeDesktopBridge();
    final controller = await createDemoMonitorController(desktopBridge: bridge);
    await tester.pumpWidget(
      SiteSignalApp(controller: controller, applicationVersion: '1.0.1'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Production API'), findsOneWidget);
    expect(
      controller.sites.map((site) => site.name),
      containsAll(<String>['Production API', 'Storefront']),
    );

    debugPrint('FEATURE_FLOW_READY');
    await _hold(tester, const Duration(seconds: 3));

    // Add a sanitized example monitor and show interval selection.
    await tester.tap(find.byTooltip('Add website'));
    await tester.pumpAndSettle();
    expect(find.text('Add a website'), findsOneWidget);
    await _hold(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Status page');
    await tester.enterText(
      find.byKey(const ValueKey('monitor-url-field')),
      'status.example.com',
    );
    await _dismissKeyboard(tester);
    final thirtySeconds = find.byKey(const ValueKey('monitor-interval-30'));
    await tester.ensureVisible(thirtySeconds);
    await tester.tap(thirtySeconds);
    await _hold(tester);
    final saveMonitor = find.byKey(const ValueKey('save-monitor-button'));
    await tester.ensureVisible(saveMonitor);
    await tester.tap(saveMonitor);
    await tester.pumpAndSettle();
    expect(controller.sites.any((site) => site.name == 'Status page'), isTrue);
    await _hold(tester, const Duration(seconds: 2));

    // Demonstrate per-site disable, enable, and edit controls.
    await _openFirstMonitorMenu(tester);
    await _hold(tester);
    await tester.tap(find.text('Disable').last);
    await tester.pumpAndSettle();
    expect(controller.sites.first.enabled, isFalse);
    await _hold(tester);
    await _openFirstMonitorMenu(tester);
    await tester.tap(find.text('Enable').last);
    await tester.pumpAndSettle();
    expect(controller.sites.first.enabled, isTrue);
    await _hold(tester);
    await _openFirstMonitorMenu(tester);
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    expect(find.text('Edit monitor'), findsOneWidget);
    await _dismissKeyboard(tester);
    await _hold(tester, const Duration(seconds: 2));
    Navigator.of(tester.element(find.text('Edit monitor'))).pop();
    await tester.pumpAndSettle();
    await _openFirstMonitorMenu(tester);
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(find.text('Remove monitor?'), findsOneWidget);
    await _hold(tester);
    Navigator.of(tester.element(find.text('Remove monitor?'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Check all now'));
    await tester.pumpAndSettle();
    await _hold(tester);

    // Browse transition history, website filtering, date ranges, and clearing.
    await tester.tap(find.text('History').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-site-filter')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-range-filter')), findsOneWidget);
    await _hold(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('history-site-filter')));
    await tester.pumpAndSettle();
    await _hold(tester);
    await tester.tap(find.text('Storefront').last);
    await tester.pumpAndSettle();
    await _hold(tester);
    await tester.tap(find.byKey(const ValueKey('history-range-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    await _hold(tester);
    await tester.tap(find.text('Clear history').last);
    await tester.pumpAndSettle();
    expect(find.text('Clear all history?'), findsOneWidget);
    await _hold(tester);
    Navigator.of(tester.element(find.text('Clear all history?'))).pop();
    await tester.pumpAndSettle();

    // Show theme, accent, monitoring, sounds, test alerts, and device behavior.
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Automatic monitoring'), findsOneWidget);
    await _hold(tester, const Duration(seconds: 2));
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();
    await _hold(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('primary-color-control')));
    await tester.pumpAndSettle();
    await _hold(tester);
    await tester.tap(find.byKey(const ValueKey('accent-color-059669')));
    await tester.pumpAndSettle();
    await _hold(tester);
    await tester.tap(find.byKey(const ValueKey('accent-color-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Automatic monitoring').last);
    await tester.pumpAndSettle();
    await _hold(tester);
    await tester.tap(find.text('Automatic monitoring').last);
    await tester.pumpAndSettle();

    final soundControl = find.byKey(
      const ValueKey('notification-sound-control'),
    );
    await tester.scrollUntilVisible(
      soundControl,
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await _hold(tester, const Duration(seconds: 2));
    await tester.tap(soundControl);
    await tester.pumpAndSettle();
    await _hold(tester);
    await tester.tap(find.text('Bright chime').last);
    await tester.pumpAndSettle();
    expect(
      controller.notificationSoundPreference,
      NotificationSoundPreference.brightChime,
    );
    await _hold(tester, const Duration(seconds: 2));

    await tester.tap(soundControl);
    await tester.pumpAndSettle();
    final systemDefault = find.text('System default').last;
    await tester.ensureVisible(systemDefault);
    await tester.tap(systemDefault);
    await tester.pumpAndSettle();
    expect(
      controller.notificationSoundPreference,
      NotificationSoundPreference.system,
    );
    await _hold(tester);
    final sendTest = find.text('Send test').last;
    await tester.ensureVisible(sendTest);
    await tester.pumpAndSettle();
    final previewCountBeforeTest = bridge.soundPreviews.length;
    await tester.tap(sendTest);
    await tester.pumpAndSettle();
    // This fake-backed walkthrough verifies Dart routing only; it does not
    // verify operating-system audio output.
    expect(
      bridge.notifications.last.soundPreference,
      NotificationSoundPreference.system,
    );
    expect(bridge.notifications.last.suppressSound, isFalse);
    expect(bridge.soundPreviews, hasLength(previewCountBeforeTest));
    await _hold(tester);

    await tester.scrollUntilVisible(
      find.text('About'),
      240,
      scrollable: find.byType(Scrollable).last,
    );
    await _hold(tester, const Duration(seconds: 3));

    await tester.tap(find.text('Overview').last);
    await tester.pumpAndSettle();
    expect(find.text('Production API'), findsOneWidget);
    await _hold(tester, const Duration(seconds: 3));
    debugPrint('FEATURE_FLOW_COMPLETE');
  });
}

Future<void> _openFirstMonitorMenu(WidgetTester tester) async {
  final menu = find.byTooltip('More actions').first;
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
}

Future<void> _hold(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 100),
]) async {
  await tester.pumpAndSettle();
  await tester.pump(duration);
}

Future<void> _dismissKeyboard(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await tester.pumpAndSettle();
}
