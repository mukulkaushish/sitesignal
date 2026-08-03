import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';
import 'package:site_signal/core/theme/app_semantic_colors.dart';
import 'package:site_signal/core/widgets/site_signal_logo.dart';
import 'package:site_signal/features/monitoring/domain/entities/favicon_image.dart';
import 'package:site_signal/features/monitoring/domain/entities/monitor_fleet_summary.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/desktop_bridge.dart';
import 'package:site_signal/features/monitoring/domain/services/internet_connectivity.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/monitor_dialog.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/monitor_ui.dart';

class OverviewView extends StatelessWidget {
  const OverviewView({
    required this.controller,
    required this.summary,
    required this.onAddSite,
    super.key,
  });

  final MonitorController controller;
  final MonitorFleetSummary summary;
  final VoidCallback onAddSite;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = AppDimensions.centeredHorizontalPadding(
          constraints.maxWidth,
          AppDimensions.contentMaxWidth,
        );
        return ListView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            AppDimensions.s20,
            horizontalPadding,
            AppDimensions.s40,
          ),
          children: [
            if (controller.errorMessage case final error?) ...[
              _ErrorBanner(message: error, onDismiss: controller.dismissError),
              const SizedBox(height: AppDimensions.s16),
            ],
            if (controller.isOffline) ...[
              _ConnectivityBanner(controller: controller),
              const SizedBox(height: AppDimensions.s16),
            ],
            if (controller.notificationPermission ==
                    NotificationPermission.notDetermined ||
                controller.notificationPermission ==
                    NotificationPermission.denied) ...[
              _NotificationBanner(controller: controller),
              const SizedBox(height: AppDimensions.s16),
            ],
            _SummaryGrid(controller: controller, summary: summary),
            const SizedBox(height: AppDimensions.s28),
            LayoutBuilder(
              builder: (context, headingConstraints) {
                final heading = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Monitored websites',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      summary.totalCount == 0
                          ? 'Add a base URL to begin monitoring.'
                          : '${summary.enabledCount} active of '
                                '${summary.totalCount} configured',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
                final addButton = FilledButton.icon(
                  onPressed: onAddSite,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add website'),
                );
                if (headingConstraints.maxWidth < 500 ||
                    MediaQuery.textScalerOf(context).scale(16) > 22) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      heading,
                      const SizedBox(height: AppDimensions.s12),
                      Align(alignment: Alignment.centerLeft, child: addButton),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: AppDimensions.s12),
                    addButton,
                  ],
                );
              },
            ),
            const SizedBox(height: AppDimensions.s16),
            if (controller.sites.isEmpty)
              _EmptyState(onAddSite: onAddSite)
            else
              for (final site in controller.sites) ...[
                _MonitorCard(controller: controller, site: site),
                const SizedBox(height: AppDimensions.s12),
              ],
          ],
        );
      },
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.controller, required this.summary});

  final MonitorController controller;
  final MonitorFleetSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppDimensions.s12;
        final columns = constraints.maxWidth >= 660
            ? 3
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: width,
              child: _SummaryCard(
                icon: Icons.monitor_heart_outlined,
                label: 'Healthy',
                value: summary.healthyCount.toString(),
                detail: controller.paused
                    ? 'Monitoring paused'
                    : '${summary.enabledCount} active monitors',
                color: context.semanticColors.success,
              ),
            ),
            SizedBox(
              width: width,
              child: _SummaryCard(
                icon: Icons.warning_amber_rounded,
                label: 'Down',
                value: summary.downCount.toString(),
                detail: summary.downCount == 0
                    ? 'No current incidents'
                    : 'Needs attention',
                color: summary.downCount > 0
                    ? context.semanticColors.error
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(
              width: width,
              child: _SummaryCard(
                icon: Icons.sync_rounded,
                label: 'Activity',
                value: controller.isCheckingAny
                    ? 'Checking'
                    : summary.unknownCount > 0
                    ? '${summary.unknownCount} pending'
                    : 'Current',
                detail: controller.paused
                    ? 'Resume to run checks'
                    : 'Checks run automatically',
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      color: color.withValues(alpha: AppDimensions.accentFillHero),
      side: BorderSide(
        color: color.withValues(alpha: AppDimensions.accentBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TonalIconBadge(icon: icon, color: color, size: AppDimensions.s32),
              const SizedBox(width: AppDimensions.s8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.s12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppDimensions.s2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MonitorCard extends StatelessWidget {
  const _MonitorCard({required this.controller, required this.site});

  final MonitorController controller;
  final SiteMonitor site;

  @override
  Widget build(BuildContext context) {
    final isChecking = controller.isChecking(site.id);
    final statusColor = !site.enabled || controller.paused
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : isChecking
        ? Theme.of(context).colorScheme.primary
        : healthColor(context, site.status);

    return Semantics(
      container: true,
      label: '${site.name}, ${site.enabled ? site.status.label : 'disabled'}',
      child: SectionCard(
        radius: AppDimensions.r16,
        padding: EdgeInsets.zero,
        side: BorderSide(
          color: statusColor.withValues(
            alpha: site.status == HealthStatus.down ? 0.34 : 0.14,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.s14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              final header = _MonitorHeader(
                controller: controller,
                site: site,
                statusColor: statusColor,
                isChecking: isChecking,
                showStatus: compact,
              );
              final details = _MonitorDetails(site: site);
              final actions = _MonitorActions(
                controller: controller,
                site: site,
                isChecking: isChecking,
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: AppDimensions.s14),
                    details,
                    const SizedBox(height: AppDimensions.s10),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: header),
                      const SizedBox(width: AppDimensions.s12),
                      _MonitorStatusChip(
                        key: ValueKey('monitor-status-${site.id}'),
                        controller: controller,
                        site: site,
                        statusColor: statusColor,
                        isChecking: isChecking,
                      ),
                      const SizedBox(width: AppDimensions.s8),
                      actions,
                    ],
                  ),
                  const SizedBox(height: AppDimensions.s14),
                  details,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MonitorHeader extends StatelessWidget {
  const _MonitorHeader({
    required this.controller,
    required this.site,
    required this.statusColor,
    required this.isChecking,
    required this.showStatus,
  });

  final MonitorController controller;
  final SiteMonitor site;
  final Color statusColor;
  final bool isChecking;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final endpoint = site.probeUrl == null
        ? 'Finding health endpoint'
        : site.probeLabel;
    final showHost = site.name.trim().toLowerCase() != site.host.toLowerCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SiteFavicon(site: site, controller: controller),
        const SizedBox(width: AppDimensions.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (showStatus) ...[
                    const SizedBox(width: AppDimensions.s8),
                    _MonitorStatusChip(
                      key: ValueKey('monitor-status-${site.id}'),
                      controller: controller,
                      site: site,
                      statusColor: statusColor,
                      isChecking: isChecking,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppDimensions.s4),
              Row(
                children: [
                  if (showHost) ...[
                    Flexible(
                      child: Text(
                        site.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.s6,
                      ),
                      child: Text(
                        '·',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: AppDimensions.iconXs,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: AppDimensions.s4),
                        Flexible(
                          child: Text(
                            endpoint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isChecking) ...[
                const SizedBox(height: AppDimensions.s6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimensions.r4),
                  child: LinearProgressIndicator(
                    minHeight: AppDimensions.s2,
                    color: statusColor,
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MonitorStatusChip extends StatelessWidget {
  const _MonitorStatusChip({
    required this.controller,
    required this.site,
    required this.statusColor,
    required this.isChecking,
    super.key,
  });

  final MonitorController controller;
  final SiteMonitor site;
  final Color statusColor;
  final bool isChecking;

  @override
  Widget build(BuildContext context) {
    final statusLabel = !site.enabled
        ? 'Disabled'
        : controller.paused
        ? 'Paused'
        : isChecking
        ? 'Checking'
        : site.status.label;
    final statusIcon = !site.enabled || controller.paused
        ? Icons.pause_circle_outline_rounded
        : isChecking
        ? Icons.sync_rounded
        : switch (site.status) {
            HealthStatus.up => Icons.check_circle_outline_rounded,
            HealthStatus.down => Icons.error_outline_rounded,
            HealthStatus.unknown => Icons.schedule_rounded,
          };

    return AccentChip(
      label: statusLabel,
      accent: statusColor,
      icon: statusIcon,
    );
  }
}

class _MonitorDetails extends StatelessWidget {
  const _MonitorDetails({required this.site});

  final SiteMonitor site;

  @override
  Widget build(BuildContext context) {
    final latest = site.latestCheck;
    final failure = latest == null || latest.error == null
        ? null
        : HealthFailureCopy.fromRecord(latest);
    final responseTimeMs = latest?.responseTimeMs;
    final metrics = <({IconData icon, String label, String value})>[
      (
        icon: Icons.speed_rounded,
        label: 'Response',
        value: responseTimeMs == null ? '—' : '$responseTimeMs ms',
      ),
      (
        icon: Icons.query_stats_rounded,
        label: 'Recorded uptime',
        value: formatUptime(site.uptimePercent),
      ),
      (
        icon: Icons.schedule_rounded,
        label: 'Last check',
        value: formatRelativeTime(latest?.checkedAt),
      ),
      (
        icon: Icons.autorenew_rounded,
        label: 'Schedule',
        value: 'Every ${formatInterval(site.intervalSeconds)}',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failure != null) ...[
          _HealthIssuePanel(failure: failure),
          const SizedBox(height: AppDimensions.s10),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = AppDimensions.s8;
            if (constraints.maxWidth < 560) {
              final width = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppDimensions.s8,
                        ),
                        child: _Metric(
                          icon: metric.icon,
                          label: metric.label,
                          value: metric.value,
                        ),
                      ),
                    ),
                ],
              );
            }
            return Row(
              children: [
                for (var index = 0; index < metrics.length; index++) ...[
                  Expanded(
                    child: _Metric(
                      icon: metrics[index].icon,
                      label: metrics[index].label,
                      value: metrics[index].value,
                    ),
                  ),
                  if (index != metrics.length - 1)
                    Container(
                      width: 1,
                      height: AppDimensions.s32,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.42),
                    ),
                ],
              ],
            );
          },
        ),
        if (site.history.length > 1) ...[
          const SizedBox(height: AppDimensions.s10),
          AvailabilityBar(records: site.history),
        ],
      ],
    );
  }
}

class _HealthIssuePanel extends StatelessWidget {
  const _HealthIssuePanel({required this.failure});

  final HealthFailureCopy failure;

  @override
  Widget build(BuildContext context) {
    final detail = failure.detail;
    return Semantics(
      container: true,
      label: ['Health check issue', failure.summary, ?detail].join('. '),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.semanticColors.error.withValues(
            alpha: AppDimensions.accentFillHero,
          ),
          borderRadius: BorderRadius.circular(AppDimensions.r8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.s10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.priority_high_rounded,
                color: context.semanticColors.error,
                size: AppDimensions.iconSm,
              ),
              const SizedBox(width: AppDimensions.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      failure.summary,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(height: AppDimensions.s2),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteFavicon extends StatefulWidget {
  const _SiteFavicon({required this.site, required this.controller});

  final SiteMonitor site;
  final MonitorController controller;

  @override
  State<_SiteFavicon> createState() => _SiteFaviconState();
}

class _SiteFaviconState extends State<_SiteFavicon> {
  FaviconImage? _scheduledInvalidation;

  @override
  void didUpdateWidget(covariant _SiteFavicon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site.id != widget.site.id ||
        oldWidget.controller != widget.controller) {
      _scheduledInvalidation = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Text(
      _siteInitials(widget.site),
      key: ValueKey('site-favicon-fallback-${widget.site.id}'),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    );
    final favicon = widget.controller.faviconForSite(widget.site.id);
    if (!identical(_scheduledInvalidation, favicon)) {
      _scheduledInvalidation = null;
    }
    final Widget content;
    if (favicon == null) {
      content = fallback;
    } else {
      content = Padding(
        padding: const EdgeInsets.all(AppDimensions.s8),
        child: Image.memory(
          favicon.pngBytes,
          key: ValueKey('site-favicon-image-${widget.site.id}'),
          width: AppDimensions.iconSm,
          height: AppDimensions.iconSm,
          cacheWidth:
              (AppDimensions.iconSm * MediaQuery.devicePixelRatioOf(context))
                  .round(),
          cacheHeight:
              (AppDimensions.iconSm * MediaQuery.devicePixelRatioOf(context))
                  .round(),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) {
            _scheduleInvalidation(favicon);
            return fallback;
          },
        ),
      );
    }
    return Container(
      width: AppDimensions.s40,
      height: AppDimensions.s40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppDimensions.r12),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  void _scheduleInvalidation(FaviconImage image) {
    if (identical(_scheduledInvalidation, image)) {
      return;
    }
    _scheduledInvalidation = image;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.controller.invalidateFavicon(widget.site.id, image);
    });
  }
}

String _siteInitials(SiteMonitor site) {
  final label = site.name.trim().isEmpty ? site.host.trim() : site.name.trim();
  final words = label
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) {
    return '?';
  }
  if (words.length == 1) {
    return String.fromCharCodes(words.single.runes.take(2)).toUpperCase();
  }
  return '${String.fromCharCode(words.first.runes.first)}'
          '${String.fromCharCode(words.last.runes.first)}'
      .toUpperCase();
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.s4),
      child: Row(
        children: [
          Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
            size: AppDimensions.iconSm,
          ),
          const SizedBox(width: AppDimensions.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppDimensions.s2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _MonitorAction { toggle, edit, delete }

class _MonitorActions extends StatelessWidget {
  const _MonitorActions({
    required this.controller,
    required this.site,
    required this.isChecking,
  });

  final MonitorController controller;
  final SiteMonitor site;
  final bool isChecking;

  Future<void> _handleAction(
    BuildContext context,
    _MonitorAction action,
  ) async {
    switch (action) {
      case _MonitorAction.toggle:
        await controller.setSiteEnabled(site.id, !site.enabled);
      case _MonitorAction.edit:
        await showMonitorDialog(context, controller: controller, site: site);
      case _MonitorAction.delete:
        final confirmed = await confirmAction(
          context,
          title: 'Remove monitor?',
          message:
              '${site.name} and its ${site.history.length} history '
              'record${site.history.length == 1 ? '' : 's'} will be removed.',
          confirmLabel: 'Remove',
        );
        if (confirmed) {
          await controller.removeSite(site.id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Open ${site.host}',
          child: IconButton(
            key: ValueKey('open-site-${site.id}'),
            onPressed: () => unawaited(controller.openSite(site)),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ),
        Tooltip(
          message: 'Check now',
          child: IconButton(
            onPressed: isChecking
                ? null
                : () => unawaited(controller.checkSite(site.id)),
            icon: isChecking
                ? const SizedBox.square(
                    dimension: AppDimensions.iconSm,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ),
        PopupMenuButton<_MonitorAction>(
          tooltip: 'More actions',
          onSelected: (action) => unawaited(_handleAction(context, action)),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _MonitorAction.toggle,
              child: ListTile(
                leading: Icon(
                  site.enabled
                      ? Icons.pause_circle_outline_rounded
                      : Icons.play_circle_outline_rounded,
                ),
                title: Text(site.enabled ? 'Disable' : 'Enable'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: _MonitorAction.edit,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Edit'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: _MonitorAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline_rounded),
                title: Text('Remove'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class AvailabilityBar extends StatelessWidget {
  const AvailabilityBar({required this.records, super.key});

  final List<CheckRecord> records;

  @override
  Widget build(BuildContext context) {
    final visible = records.take(30).toList().reversed.toList();
    return Semantics(
      label:
          '${visible.length} recorded status '
          'change${visible.length == 1 ? '' : 's'}',
      child: SizedBox(
        height: AppDimensions.s6,
        child: Row(
          children: [
            for (var index = 0; index < visible.length; index++) ...[
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: healthColor(context, visible[index].status),
                    borderRadius: BorderRadius.circular(AppDimensions.r4),
                  ),
                ),
              ),
              if (index != visible.length - 1)
                const SizedBox(width: AppDimensions.s2),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddSite});

  final VoidCallback onAddSite;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      radius: AppDimensions.r16,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppDimensions.s40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                const SiteSignalLogo(size: AppDimensions.s64),
                const SizedBox(height: AppDimensions.s16),
                Text(
                  'Know before your users do',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimensions.s8),
                Text(
                  'Add only the website base URL. SiteSignal discovers a common '
                  'health endpoint, checks it on schedule, and alerts on '
                  'outage or recovery.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppDimensions.s20),
                FilledButton.icon(
                  onPressed: onAddSite,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add first website'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return NoticeBanner(
      icon: Icons.error_outline_rounded,
      title: 'SiteSignal needs attention',
      message: message,
      accent: context.semanticColors.error,
      action: onDismiss,
      actionLabel: 'Dismiss',
    );
  }
}

class _ConnectivityBanner extends StatelessWidget {
  const _ConnectivityBanner({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final noNetwork =
        controller.connectivityAssessment.issue == ConnectivityIssue.noNetwork;
    return NoticeBanner(
      icon: noNetwork ? Icons.signal_wifi_off_rounded : Icons.cloud_off_rounded,
      title: noNetwork ? 'No network connection' : 'No internet access',
      message: 'Checks paused. Site statuses remain unchanged.',
      accent: context.semanticColors.warning,
      action: () => unawaited(controller.recheckConnectivity()),
      actionLabel: 'Retry',
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({required this.controller});

  final MonitorController controller;

  @override
  Widget build(BuildContext context) {
    final denied =
        controller.notificationPermission == NotificationPermission.denied;
    return NoticeBanner(
      icon: Icons.notifications_active_outlined,
      title: denied
          ? 'Notifications are disabled'
          : 'Enable incident notifications',
      message: denied
          ? 'Allow SiteSignal in system notification settings to receive outage '
                'and recovery alerts.'
          : 'SiteSignal alerts only when a site changes from up to down, or '
                'recovers.',
      accent: Theme.of(context).colorScheme.primary,
      action: denied || controller.isRequestingNotificationPermission
          ? null
          : () => unawaited(controller.requestNotifications()),
      actionLabel: denied ? null : 'Enable',
    );
  }
}
