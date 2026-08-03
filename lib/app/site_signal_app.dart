import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_signal/core/theme/app_accent_color.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';
import 'package:site_signal/core/theme/app_semantic_colors.dart';
import 'package:site_signal/core/theme/app_theme.dart';
import 'package:site_signal/core/theme/app_theme_preference.dart';
import 'package:site_signal/core/widgets/site_signal_logo.dart';
import 'package:site_signal/features/monitoring/domain/entities/monitor_fleet_summary.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';
import 'package:site_signal/features/monitoring/presentation/pages/history_view.dart';
import 'package:site_signal/features/monitoring/presentation/pages/overview_view.dart';
import 'package:site_signal/features/monitoring/presentation/pages/settings_view.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/monitor_dialog.dart';
import 'package:site_signal/features/updates/presentation/widgets/update_banner.dart';

class SiteSignalApp extends StatefulWidget {
  const SiteSignalApp({
    required this.controller,
    required this.applicationVersion,
    this.initialSection = DashboardSection.overview,
    super.key,
  });

  final MonitorController controller;
  final String applicationVersion;
  final DashboardSection initialSection;

  @override
  State<SiteSignalApp> createState() => _SiteSignalAppState();
}

class _SiteSignalAppState extends State<SiteSignalApp>
    with WidgetsBindingObserver {
  late AppThemePreference _themePreference;
  late int _primaryColorValue;
  late ThemeData _lightTheme;
  late ThemeData _darkTheme;

  @override
  void initState() {
    super.initState();
    _themePreference = widget.controller.themePreference;
    _primaryColorValue = widget.controller.primaryColorValue;
    _rebuildThemes();
    widget.controller.addListener(_handleControllerChange);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant SiteSignalApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller.removeListener(_handleControllerChange);
    widget.controller.addListener(_handleControllerChange);
    _themePreference = widget.controller.themePreference;
    _primaryColorValue = widget.controller.primaryColorValue;
    _rebuildThemes();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.handleAppResumed());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_handleControllerChange);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SiteSignal',
      debugShowCheckedModeBanner: false,
      themeMode: _themePreference.themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      builder: (context, child) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          key: const ValueKey('system-ui-overlay-style'),
          value: SystemUiOverlayStyle(
            statusBarColor: theme.scaffoldBackgroundColor,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            statusBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            systemStatusBarContrastEnforced: false,
            systemNavigationBarColor: theme.colorScheme.surface,
            systemNavigationBarDividerColor: theme.dividerColor,
            systemNavigationBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: DashboardShell(
        controller: widget.controller,
        applicationVersion: widget.applicationVersion,
        initialSection: widget.initialSection,
      ),
    );
  }

  void _handleControllerChange() {
    final nextPreference = widget.controller.themePreference;
    final nextColorValue = widget.controller.primaryColorValue;
    if (nextPreference == _themePreference &&
        nextColorValue == _primaryColorValue) {
      return;
    }
    setState(() {
      _themePreference = nextPreference;
      if (nextColorValue != _primaryColorValue) {
        _primaryColorValue = nextColorValue;
        _rebuildThemes();
      }
    });
  }

  void _rebuildThemes() {
    final primary = AppAccentColor.fromValue(_primaryColorValue);
    _lightTheme = AppTheme.build(Brightness.light, seed: primary);
    _darkTheme = AppTheme.build(Brightness.dark, seed: primary);
  }
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({
    required this.controller,
    required this.applicationVersion,
    this.initialSection = DashboardSection.overview,
    super.key,
  });

  final MonitorController controller;
  final String applicationVersion;
  final DashboardSection initialSection;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  late int _selectedIndex;

  static const _destinations = DashboardSection.values;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialSection.index;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (!widget.controller.initialized) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SiteSignalLogo(size: AppDimensions.s64),
                  const SizedBox(height: AppDimensions.s16),
                  Text(
                    'Starting SiteSignal…',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppDimensions.s12),
                  const SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                ],
              ),
            ),
          );
        }

        final summary = widget.controller.fleetSummary;
        return LayoutBuilder(
          builder: (context, constraints) {
            final useSidebar =
                constraints.maxWidth >= AppDimensions.breakpointSidebar;
            final selectedDestination = _destinations[_selectedIndex];
            final content = ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                children: [
                  _TopBar(
                    controller: widget.controller,
                    summary: summary,
                    title: selectedDestination.label,
                    onAddSite: selectedDestination == DashboardSection.overview
                        ? _showAddSite
                        : null,
                  ),
                  const Divider(height: 1),
                  if (widget.controller.availableUpdate case final update?)
                    UpdateBanner(
                      update: update,
                      onViewRelease: () =>
                          unawaited(widget.controller.openAvailableUpdate()),
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: <Widget>[
                        for (final destination in _destinations)
                          destination.buildPage(
                            controller: widget.controller,
                            summary: summary,
                            onAddSite: _showAddSite,
                            applicationVersion: widget.applicationVersion,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );

            if (useSidebar) {
              return Scaffold(
                body: SafeArea(
                  child: Row(
                    children: [
                      _Sidebar(
                        controller: widget.controller,
                        summary: summary,
                        destinations: _destinations,
                        selectedIndex: _selectedIndex,
                        onSelected: (index) =>
                            setState(() => _selectedIndex = index),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                      Expanded(child: content),
                    ],
                  ),
                ),
              );
            }

            return Scaffold(
              body: SafeArea(bottom: false, child: content),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) =>
                    setState(() => _selectedIndex = index),
                destinations: [
                  for (final destination in _destinations)
                    NavigationDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: destination.label,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAddSite() {
    unawaited(showMonitorDialog(context, controller: widget.controller));
  }
}

enum DashboardSection {
  overview(
    label: 'Overview',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
  ),
  history(
    label: 'History',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history_rounded,
  ),
  settings(
    label: 'Settings',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune_rounded,
  );

  const DashboardSection({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  Widget buildPage({
    required MonitorController controller,
    required MonitorFleetSummary summary,
    required VoidCallback onAddSite,
    required String applicationVersion,
  }) {
    return switch (this) {
      DashboardSection.overview => OverviewView(
        controller: controller,
        summary: summary,
        onAddSite: onAddSite,
      ),
      DashboardSection.history => HistoryView(controller: controller),
      DashboardSection.settings => SettingsView(
        controller: controller,
        applicationVersion: applicationVersion,
      ),
    };
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.summary,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final MonitorController controller;
  final MonitorFleetSummary summary;
  final List<DashboardSection> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusText = controller.paused
        ? 'Monitoring paused'
        : switch (summary.state) {
            MonitorFleetState.down => '${summary.downCount} down',
            MonitorFleetState.noEnabledSites => 'No monitors',
            MonitorFleetState.checking => 'Checking monitors',
            MonitorFleetState.healthy => 'All systems normal',
          };
    final statusColor = controller.paused
        ? colorScheme.onSurfaceVariant
        : summary.state == MonitorFleetState.down
        ? context.semanticColors.error
        : context.semanticColors.success;

    return Container(
      width: 224,
      color: colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(
        AppDimensions.s16,
        AppDimensions.s24,
        AppDimensions.s16,
        AppDimensions.s18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimensions.s8),
            child: Row(
              children: [
                const SiteSignalLogo(size: 40),
                const SizedBox(width: AppDimensions.s12),
                Expanded(
                  child: Text(
                    'SiteSignal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.s28),
          for (var index = 0; index < destinations.length; index++) ...[
            _SidebarDestination(
              destination: destinations[index],
              selected: selectedIndex == index,
              onTap: () => onSelected(index),
            ),
            const SizedBox(height: AppDimensions.s4),
          ],
          const Spacer(),
          DecoratedBox(
            decoration: ShapeDecoration(
              color: statusColor.withValues(
                alpha: AppDimensions.accentFillHero,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.r12),
                side: BorderSide(
                  color: statusColor.withValues(
                    alpha: AppDimensions.accentBorderSubtle,
                  ),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppDimensions.s12),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.s8),
                  Expanded(
                    child: Text(
                      statusText,
                      maxLines: 2,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarDestination extends StatelessWidget {
  const _SidebarDestination({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final DashboardSection destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppDimensions.r12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDimensions.r12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.s12,
            vertical: AppDimensions.s10,
          ),
          child: Row(
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: AppDimensions.iconSm,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppDimensions.s12),
              Text(
                destination.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.summary,
    required this.title,
    required this.onAddSite,
  });

  final MonitorController controller;
  final MonitorFleetSummary summary;
  final String title;
  final VoidCallback? onAddSite;

  @override
  Widget build(BuildContext context) {
    final compactActions =
        MediaQuery.sizeOf(context).width < 600 ||
        MediaQuery.textScalerOf(context).scale(16) > 22;
    return ColoredBox(
      key: const ValueKey('dashboard-top-bar'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.s24,
            vertical: AppDimensions.s10,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (controller.paused)
                Padding(
                  padding: const EdgeInsets.only(right: AppDimensions.s8),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.r6),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.s8,
                        vertical: AppDimensions.s4,
                      ),
                      child: Text(
                        'Paused',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              Tooltip(
                message: 'Check all now',
                child: IconButton(
                  onPressed:
                      summary.enabledCount == 0 || controller.isCheckingAny
                      ? null
                      : () => unawaited(controller.checkAll()),
                  icon: controller.isCheckingAny
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ),
              if (onAddSite != null) ...[
                const SizedBox(width: AppDimensions.s4),
                if (compactActions)
                  Tooltip(
                    message: 'Add website',
                    child: IconButton.filled(
                      onPressed: onAddSite,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: onAddSite,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
