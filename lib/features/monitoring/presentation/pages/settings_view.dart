import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_signal/core/theme/app_accent_color.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/core/widgets/site_signal_logo.dart';
import 'package:site_signal/features/monitoring/domain/entities/notification_sound_preference.dart';
import 'package:site_signal/features/monitoring/domain/services/background_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/desktop_bridge.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/accent_color_dialog.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/monitor_ui.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/popover_select_field.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({
    required this.controller,
    required this.applicationVersion,
    super.key,
  });

  final MonitorController controller;
  final String applicationVersion;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = AppDimensions.centeredHorizontalPadding(
          constraints.maxWidth,
          AppDimensions.settingsMaxWidth,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            AppDimensions.s20,
            horizontalPadding,
            AppDimensions.s40,
          ),
          children: [
            _SettingsSection(
              title: 'Appearance',
              subtitle: 'Choose how SiteSignal looks on this device.',
              child: SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<AppThemePreference>(
                      key: const ValueKey('theme-preference-control'),
                      segments: const <ButtonSegment<AppThemePreference>>[
                        ButtonSegment<AppThemePreference>(
                          value: AppThemePreference.system,
                          icon: Icon(Icons.brightness_auto_rounded),
                          label: Text('System'),
                        ),
                        ButtonSegment<AppThemePreference>(
                          value: AppThemePreference.light,
                          icon: Icon(Icons.light_mode_outlined),
                          label: Text('Light'),
                        ),
                        ButtonSegment<AppThemePreference>(
                          value: AppThemePreference.dark,
                          icon: Icon(Icons.dark_mode_outlined),
                          label: Text('Dark'),
                        ),
                      ],
                      selected: <AppThemePreference>{
                        controller.themePreference,
                      },
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        unawaited(
                          controller.setThemePreference(selection.single),
                        );
                      },
                    ),
                    const SizedBox(height: AppDimensions.s12),
                    Text(
                      controller.themePreference == AppThemePreference.system
                          ? 'Following the operating system appearance.'
                          : '${_themeLabel(controller.themePreference)} mode is always used.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.s16),
                    const Divider(height: 1),
                    const SizedBox(height: AppDimensions.s8),
                    _PrimaryColorPicker(controller: controller),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.s24),
            _SettingsSection(
              title: 'Monitoring',
              subtitle: 'Controls that apply to every configured website.',
              child: SectionCard(
                padding: EdgeInsets.zero,
                child: Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    secondary: const Icon(Icons.radar_rounded),
                    title: const Text('Automatic monitoring'),
                    subtitle: Text(_automaticMonitoringDescription(isDesktop)),
                    value: !controller.paused,
                    onChanged: (enabled) =>
                        unawaited(controller.setPaused(!enabled)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.s24),
            _SettingsSection(
              title: 'Notifications',
              subtitle:
                  'Alerts are sent only for outage and recovery transitions.',
              child: SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppDimensions.s16),
                      child: Row(
                        children: [
                          TonalIconBadge(
                            icon: Icons.notifications_active_outlined,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: AppDimensions.s12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _permissionTitle(
                                    controller.notificationPermission,
                                  ),
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: AppDimensions.s2),
                                Text(
                                  _permissionDescription(
                                    controller.notificationPermission,
                                  ),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppDimensions.s12),
                          if (controller.notificationPermission ==
                              NotificationPermission.notDetermined)
                            FilledButton.tonal(
                              onPressed:
                                  controller.isRequestingNotificationPermission
                                  ? null
                                  : () => unawaited(
                                      controller.requestNotifications(),
                                    ),
                              child: Text(
                                controller.isRequestingNotificationPermission
                                    ? 'Enabling…'
                                    : 'Enable',
                              ),
                            )
                          else if (controller.notificationPermission ==
                                  NotificationPermission.denied &&
                              Platform.isAndroid)
                            OutlinedButton(
                              onPressed: () => unawaited(
                                controller.openNotificationSettings(),
                              ),
                              child: const Text('Settings'),
                            )
                          else if (controller.notificationPermission ==
                                  NotificationPermission.authorized ||
                              controller.notificationPermission ==
                                  NotificationPermission.provisional)
                            OutlinedButton(
                              onPressed: controller.isSendingTestNotification
                                  ? null
                                  : () => unawaited(
                                      controller.sendTestNotification(),
                                    ),
                              child: Text(
                                controller.isSendingTestNotification
                                    ? 'Sending…'
                                    : 'Send test',
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (controller.notificationPermission !=
                        NotificationPermission.unsupported) ...[
                      const Divider(height: 1),
                      _NotificationSoundControl(controller: controller),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.s24),
            _SettingsSection(
              title: isDesktop ? 'Desktop behavior' : 'Device behavior',
              subtitle: _platformBehaviorLabel(),
              child: SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (isDesktop && controller.launchAtStartupSupported) ...[
                      Material(
                        type: MaterialType.transparency,
                        child: SwitchListTile(
                          key: const ValueKey('launch-at-startup-control'),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppDimensions.s16,
                            vertical: AppDimensions.s4,
                          ),
                          secondary: const Icon(Icons.power_rounded),
                          title: const Text('Open at system startup'),
                          subtitle: const Text(
                            'Starts SiteSignal when you sign in so tray monitoring begins automatically.',
                          ),
                          value: controller.launchAtStartupEnabled,
                          onChanged: controller.isUpdatingLaunchAtStartup
                              ? null
                              : (enabled) => unawaited(
                                  controller.setLaunchAtStartupEnabled(enabled),
                                ),
                        ),
                      ),
                      const Divider(height: 1),
                    ],
                    if (isDesktop) ...[
                      const _BehaviorRow(
                        icon: Icons.close_fullscreen_rounded,
                        title: 'Closing the dashboard',
                        value: 'Keeps monitoring in the system tray',
                      ),
                      const Divider(height: 1),
                    ] else ...[
                      _BehaviorRow(
                        icon: Platform.isAndroid
                            ? Icons.sync_lock_rounded
                            : Icons.schedule_rounded,
                        title: 'Background monitoring',
                        value: Platform.isAndroid
                            ? 'Continuous while the persistent status notification is active'
                            : 'Best effort; iOS controls refresh timing',
                      ),
                      const Divider(height: 1),
                    ],
                    const _BehaviorRow(
                      icon: Icons.signal_wifi_off_rounded,
                      title: 'Device offline',
                      value: 'One alert · checks pause · site states unchanged',
                    ),
                    const Divider(height: 1),
                    _BehaviorRow(
                      icon: Icons.storage_outlined,
                      title: 'History retention',
                      value:
                          '${controller.historyLimit} status changes per website · SQLite',
                    ),
                    const Divider(height: 1),
                    const _BehaviorRow(
                      icon: Icons.route_outlined,
                      title: 'Automatic probes',
                      value:
                          'Base URL, health, healthz, readyz, status, and more',
                    ),
                    const Divider(height: 1),
                    const _BehaviorRow(
                      icon: Icons.http_rounded,
                      title: 'Healthy responses',
                      value: 'HTTP 200–299 with placeholder-page detection',
                    ),
                    const Divider(height: 1),
                    const _BehaviorRow(
                      icon: Icons.timer_outlined,
                      title: 'Request timeout',
                      value: '10 seconds',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.s24),
            _SettingsSection(
              title: 'Updates',
              subtitle: 'Check the official stable releases on GitHub.',
              child: _UpdateSettingsCard(
                controller: controller,
                applicationVersion: applicationVersion,
              ),
            ),
            const SizedBox(height: AppDimensions.s24),
            _SettingsSection(
              title: 'About',
              subtitle: 'Local-first website health monitoring.',
              child: SectionCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SiteSignalLogo(size: AppDimensions.s48),
                    const SizedBox(width: AppDimensions.s16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SiteSignal $applicationVersion',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppDimensions.s4),
                          Text(
                            'Base URLs, discovered probes, and check history stay '
                            'in a local SQLite database on this device. '
                            'Checks run locally in the desktop process, Android '
                            'foreground service, or iOS background opportunities. '
                            'SiteSignal is not a remote uptime service.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _permissionTitle(NotificationPermission permission) {
    return switch (permission) {
      NotificationPermission.authorized => 'Notifications enabled',
      NotificationPermission.provisional => 'Quiet notifications enabled',
      NotificationPermission.denied => 'Notifications disabled',
      NotificationPermission.notDetermined => 'Notifications not enabled yet',
      NotificationPermission.unsupported => 'Notifications unavailable',
    };
  }

  String _automaticMonitoringDescription(bool isDesktop) {
    if (controller.paused) {
      return 'Paused — manual checks still work.';
    }
    if (controller.isOffline) {
      return 'Waiting for internet. Site statuses remain unchanged.';
    }
    if (isDesktop) {
      return 'Active while SiteSignal is running, including in the tray.';
    }
    final background = controller.backgroundMonitoringStatus;
    if (background.error != null) {
      return 'Background monitoring could not start. Reopen SiteSignal or check system settings.';
    }
    return switch (background.mode) {
      BackgroundMonitoringMode.continuous =>
        background.isRunning
            ? 'Runs continuously with a persistent Android status notification.'
            : 'Starting Android background monitoring…',
      BackgroundMonitoringMode.opportunistic =>
        'Runs in the foreground and during refresh windows scheduled by iOS.',
      BackgroundMonitoringMode.unavailable =>
        'Checks run while SiteSignal is open; overdue checks run on return.',
    };
  }

  String _themeLabel(AppThemePreference preference) {
    return switch (preference) {
      AppThemePreference.system => 'System',
      AppThemePreference.light => 'Light',
      AppThemePreference.dark => 'Dark',
    };
  }

  String _permissionDescription(NotificationPermission permission) {
    return switch (permission) {
      NotificationPermission.authorized =>
        'Outage and recovery alerts are allowed.',
      NotificationPermission.provisional =>
        'Alerts are delivered quietly by the operating system.',
      NotificationPermission.denied =>
        'Enable SiteSignal from your system notification settings.',
      NotificationPermission.notDetermined =>
        'Enable alerts so state changes do not go unnoticed.',
      NotificationPermission.unsupported =>
        'This device does not expose notification support.',
    };
  }

  String _platformBehaviorLabel() {
    if (Platform.isMacOS) {
      return 'macOS menu bar and Dock';
    }
    if (Platform.isWindows) {
      return 'Windows system tray';
    }
    if (Platform.isLinux) {
      return 'Linux system tray';
    }
    if (Platform.isIOS) {
      return 'iPhone and iPad app lifecycle';
    }
    if (Platform.isAndroid) {
      return 'Android app lifecycle';
    }
    return 'Local app lifecycle';
  }
}

class _UpdateSettingsCard extends StatelessWidget {
  const _UpdateSettingsCard({
    required this.controller,
    required this.applicationVersion,
  });

  final MonitorController controller;
  final String applicationVersion;

  @override
  Widget build(BuildContext context) {
    final update = controller.availableUpdate;
    final title = update == null
        ? 'Installed version $applicationVersion'
        : 'SiteSignal ${update.version} is available';
    final description = controller.isCheckingForUpdate
        ? 'Checking GitHub Releases…'
        : update != null
        ? 'A newer stable version is available. Updating is recommended.'
        : controller.updateCheckMessage ??
              'SiteSignal checks once a day and never installs updates silently.';
    final action = update == null
        ? OutlinedButton.icon(
            key: const ValueKey('check-for-updates'),
            onPressed: controller.isCheckingForUpdate
                ? null
                : () => unawaited(controller.checkForUpdates()),
            icon: controller.isCheckingForUpdate
                ? const SizedBox.square(
                    dimension: AppDimensions.s16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(
              controller.isCheckingForUpdate ? 'Checking…' : 'Check now',
            ),
          )
        : FilledButton.icon(
            key: const ValueKey('open-update-release'),
            onPressed: () => unawaited(controller.openAvailableUpdate()),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('View update'),
          );

    final details = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TonalIconBadge(
          icon: update == null
              ? Icons.system_update_outlined
              : Icons.system_update_alt_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: AppDimensions.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppDimensions.s2),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return SectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: AppDimensions.s12),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: AppDimensions.s16),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _NotificationSoundControl extends StatelessWidget {
  const _NotificationSoundControl({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final selector = PopoverSelectField<NotificationSoundPreference>(
      key: const ValueKey('notification-sound-control'),
      value: controller.notificationSoundPreference,
      labelText: 'Alert sound',
      prefixIcon: Icons.volume_up_outlined,
      options: <PopoverSelectOption<NotificationSoundPreference>>[
        for (final preference in NotificationSoundPreference.values)
          PopoverSelectOption<NotificationSoundPreference>(
            value: preference,
            label: preference.profile.label,
            description: preference.profile.selectorDescription,
            icon: _iconFor(preference),
          ),
      ],
      onSelected: (preference) =>
          unawaited(controller.selectNotificationSoundPreference(preference)),
    );

    return Padding(
      padding: const EdgeInsets.all(AppDimensions.s16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final information = Row(
            children: [
              TonalIconBadge(
                icon: Icons.music_note_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppDimensions.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notification sound',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppDimensions.s2),
                    Text(
                      controller
                          .notificationSoundPreference
                          .profile
                          .activeDescription,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                information,
                const SizedBox(height: AppDimensions.s12),
                selector,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: information),
              const SizedBox(width: AppDimensions.s16),
              SizedBox(width: 260, child: selector),
            ],
          );
        },
      ),
    );
  }

  IconData _iconFor(NotificationSoundPreference preference) {
    return switch (preference) {
      NotificationSoundPreference.siteSignal =>
        Icons.notifications_active_outlined,
      NotificationSoundPreference.brightChime => Icons.wb_sunny_outlined,
      NotificationSoundPreference.softPulse => Icons.graphic_eq_rounded,
      NotificationSoundPreference.beacon => Icons.cell_tower_rounded,
      NotificationSoundPreference.system => Icons.computer_rounded,
      NotificationSoundPreference.silent => Icons.notifications_off_outlined,
    };
  }
}

class _PrimaryColorPicker extends StatelessWidget {
  const _PrimaryColorPicker({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final color = AppAccentColor.fromValue(controller.primaryColorValue);
    final preset = AppAccentColor.presetFor(color);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: const ValueKey('primary-color-control'),
        borderRadius: BorderRadius.circular(AppDimensions.r8),
        onTap: () {
          unawaited(
            showDialog<void>(
              context: context,
              builder: (context) => AccentColorDialog(
                initialColor: color,
                onChanged: (nextColor) => unawaited(
                  controller.setPrimaryColorValue(nextColor.toARGB32()),
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.s4,
            vertical: AppDimensions.s8,
          ),
          child: Row(
            children: [
              TonalIconBadge(
                icon: Icons.palette_outlined,
                color: color,
                size: AppDimensions.s32,
              ),
              const SizedBox(width: AppDimensions.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Primary color',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppDimensions.s2),
                    Text(
                      '${preset?.name ?? 'Custom'} · #${AppAccentColor.hex(color)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: AppDimensions.s28,
                height: AppDimensions.s28,
                decoration: ShapeDecoration(
                  color: color,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.s8),
              Icon(
                Icons.chevron_right_rounded,
                size: AppDimensions.iconSm,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppDimensions.s2),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppDimensions.s12),
        child,
      ],
    );
  }
}

class _BehaviorRow extends StatelessWidget {
  const _BehaviorRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.s16,
        vertical: AppDimensions.s12,
      ),
      child: Row(
        children: [
          TonalIconBadge(
            icon: icon,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: AppDimensions.s32,
          ),
          const SizedBox(width: AppDimensions.s12),
          Expanded(child: Text(title)),
          const SizedBox(width: AppDimensions.s12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
