import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/monitor_ui.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/popover_select_field.dart';

class HistoryView extends StatefulWidget {
  const HistoryView({required this.controller, super.key});

  final MonitorController controller;

  @override
  State<HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<HistoryView> {
  static const _allSites = '__all__';
  String _selectedSiteId = _allSites;
  _HistoryRange _selectedRange = _HistoryRange.today;

  @override
  Widget build(BuildContext context) {
    final sites = widget.controller.sites;
    final now = DateTime.now();
    final siteIds = sites.map((site) => site.id).toSet();
    final selectedId = siteIds.contains(_selectedSiteId)
        ? _selectedSiteId
        : _allSites;
    final entries =
        <_HistoryEntry>[
          for (final site in sites)
            if (selectedId == _allSites || selectedId == site.id)
              for (final record in site.history)
                if (_selectedRange.includes(record.checkedAt, now))
                  _HistoryEntry(site: site, record: record),
        ]..sort(
          (first, second) =>
              second.record.checkedAt.compareTo(first.record.checkedAt),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final phone = constraints.maxWidth < 560;
        final horizontalPadding = AppDimensions.centeredHorizontalPadding(
          constraints.maxWidth,
          AppDimensions.contentMaxWidth,
        );
        final countLabel =
            '${entries.length} recorded status '
            'change${entries.length == 1 ? '' : 's'} · '
            '${_selectedRange.label}';
        final siteFilter = PopoverSelectField<String>(
          key: const ValueKey('history-site-filter'),
          value: selectedId,
          labelText: 'Website',
          prefixIcon: Icons.filter_list_rounded,
          options: <PopoverSelectOption<String>>[
            const PopoverSelectOption<String>(
              value: _allSites,
              label: 'All websites',
              icon: Icons.language_rounded,
            ),
            for (final site in sites)
              PopoverSelectOption<String>(
                value: site.id,
                label: site.name,
                icon: Icons.public_rounded,
              ),
          ],
          onSelected: (value) => setState(() => _selectedSiteId = value),
        );
        final rangeFilter = PopoverSelectField<_HistoryRange>(
          key: const ValueKey('history-range-filter'),
          value: _selectedRange,
          labelText: 'Date range',
          prefixIcon: Icons.calendar_today_outlined,
          options: <PopoverSelectOption<_HistoryRange>>[
            for (final range in _HistoryRange.values)
              PopoverSelectOption<_HistoryRange>(
                value: range,
                label: range.label,
                icon: range.icon,
              ),
          ],
          onSelected: (value) => setState(() => _selectedRange = value),
        );
        final hasAnyHistory = sites.any((site) => site.history.isNotEmpty);
        final clearButton = OutlinedButton.icon(
          onPressed: hasAnyHistory ? () => _clearHistory(context) : null,
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Clear history'),
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            AppDimensions.s20,
            horizontalPadding,
            AppDimensions.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact) ...[
                Text(
                  countLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppDimensions.s12),
                if (phone) ...[
                  siteFilter,
                  const SizedBox(height: AppDimensions.s8),
                  rangeFilter,
                ] else
                  Row(
                    children: [
                      Expanded(child: siteFilter),
                      const SizedBox(width: AppDimensions.s8),
                      Expanded(child: rangeFilter),
                    ],
                  ),
                const SizedBox(height: AppDimensions.s8),
                Align(alignment: Alignment.centerRight, child: clearButton),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        countLabel,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(width: 220, child: siteFilter),
                    const SizedBox(width: AppDimensions.s8),
                    SizedBox(width: 170, child: rangeFilter),
                    const SizedBox(width: AppDimensions.s8),
                    clearButton,
                  ],
                ),
              const SizedBox(height: AppDimensions.s16),
              Expanded(
                child: entries.isEmpty
                    ? _EmptyHistory(range: _selectedRange)
                    : ListView.separated(
                        itemCount: entries.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppDimensions.s8),
                        itemBuilder: (context, index) =>
                            _HistoryRow(entry: entries[index]),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _clearHistory(BuildContext context) async {
    final confirmed = await confirmAction(
      context,
      title: 'Clear all history?',
      message:
          'All recorded status changes will be removed. Monitoring and the '
          'current site status will continue unchanged.',
      confirmLabel: 'Clear history',
    );
    if (confirmed && context.mounted) {
      await widget.controller.clearHistory();
    }
  }
}

enum _HistoryRange {
  today('Today'),
  yesterday('Yesterday'),
  threeDays('3 days'),
  sevenDays('7 days'),
  all('All');

  const _HistoryRange(this.label);

  final String label;

  IconData get icon => switch (this) {
    _HistoryRange.today => Icons.today_rounded,
    _HistoryRange.yesterday => Icons.history_rounded,
    _HistoryRange.threeDays => Icons.date_range_rounded,
    _HistoryRange.sevenDays => Icons.calendar_view_week_rounded,
    _HistoryRange.all => Icons.all_inclusive_rounded,
  };

  bool includes(DateTime checkedAt, DateTime now) {
    if (this == _HistoryRange.all) {
      return true;
    }
    final localTimestamp = checkedAt.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final (start, end) = switch (this) {
      _HistoryRange.today => (today, tomorrow),
      _HistoryRange.yesterday => (
        DateTime(now.year, now.month, now.day - 1),
        today,
      ),
      _HistoryRange.threeDays => (
        DateTime(now.year, now.month, now.day - 2),
        tomorrow,
      ),
      _HistoryRange.sevenDays => (
        DateTime(now.year, now.month, now.day - 6),
        tomorrow,
      ),
      _HistoryRange.all => throw StateError('All dates have no bounds.'),
    };
    return !localTimestamp.isBefore(start) && localTimestamp.isBefore(end);
  }

  String get emptyTitle => switch (this) {
    _HistoryRange.today => 'No status changes today',
    _HistoryRange.yesterday => 'No status changes yesterday',
    _HistoryRange.threeDays => 'No changes in the last 3 days',
    _HistoryRange.sevenDays => 'No changes in the last 7 days',
    _HistoryRange.all => 'No status changes recorded',
  };
}

class _HistoryEntry {
  const _HistoryEntry({required this.site, required this.record});

  final SiteMonitor site;
  final CheckRecord record;
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final _HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final record = entry.record;
    final color = healthColor(context, record.status);
    final failure = record.error == null
        ? null
        : HealthFailureCopy.fromRecord(record);
    return SectionCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.s16,
        vertical: AppDimensions.s12,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final identity = Row(
            children: [
              TonalIconBadge(
                icon: record.status == HealthStatus.up
                    ? Icons.check_rounded
                    : Icons.close_rounded,
                color: color,
              ),
              const SizedBox(width: AppDimensions.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (failure == null)
                      Text(
                        '${entry.site.host} · ${_probeLabel(record)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else ...[
                      Text(
                        failure.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (failure.detail case final detail?)
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          );
          final values = <Widget>[
            _HistoryValue(
              label: 'Status',
              value: record.statusCode?.toString() ?? record.status.label,
            ),
            _HistoryValue(
              label: 'Response',
              value: record.responseTimeMs == null
                  ? '—'
                  : '${record.responseTimeMs} ms',
            ),
            _HistoryValue(
              label: 'Changed',
              value: formatTimestamp(record.checkedAt),
              width: 150,
            ),
          ];
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: AppDimensions.s12),
                const Divider(height: 1),
                const SizedBox(height: AppDimensions.s10),
                Wrap(
                  spacing: AppDimensions.s8,
                  runSpacing: AppDimensions.s8,
                  children: values,
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 2, child: identity),
              const SizedBox(width: AppDimensions.s16),
              ...values,
            ],
          );
        },
      ),
    );
  }

  String _probeLabel(CheckRecord record) {
    final uri = Uri.tryParse(record.checkedUrl);
    if (uri == null || uri.path.isEmpty || uri.path == '/') {
      return 'base';
    }
    return uri.path;
  }
}

class _HistoryValue extends StatelessWidget {
  const _HistoryValue({
    required this.label,
    required this.value,
    this.width = 100,
  });

  final String label;
  final String value;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
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
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.range});

  final _HistoryRange range;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: AppDimensions.iconXl,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppDimensions.s12),
            Text(
              range.emptyTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppDimensions.s6),
            Text(
              range == _HistoryRange.all
                  ? 'The initial result and future outage or recovery '
                        'transitions will appear here. Repeated checks are '
                        'intentionally omitted.'
                  : 'Choose another date range to see older status changes.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
