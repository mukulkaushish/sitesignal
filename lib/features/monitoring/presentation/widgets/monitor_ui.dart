import 'package:flutter/material.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';
import 'package:site_signal/core/theme/app_semantic_colors.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Color healthColor(BuildContext context, HealthStatus status) {
  return switch (status) {
    HealthStatus.up => context.semanticColors.success,
    HealthStatus.down => context.semanticColors.error,
    HealthStatus.unknown => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

String formatInterval(int seconds) {
  if (seconds < 60) {
    return '${seconds}s';
  }
  if (seconds < 3600) {
    return '${seconds ~/ 60}m';
  }
  return '${seconds ~/ 3600}h';
}

String formatRelativeTime(DateTime? dateTime, {DateTime? now}) {
  if (dateTime == null) {
    return 'Never';
  }
  final current = (now ?? DateTime.now()).toUtc();
  final difference = current.difference(dateTime.toUtc());
  if (difference.isNegative || difference.inSeconds < 5) {
    return 'Just now';
  }
  if (difference.inSeconds < 60) {
    return '${difference.inSeconds} sec ago';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes} min ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours} hr ago';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
  }
  return formatTimestamp(dateTime, now: current);
}

String formatTimestamp(DateTime dateTime, {DateTime? now}) {
  final local = dateTime.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final calendarDay = DateTime(local.year, local.month, local.day);
  final today = DateTime(current.year, current.month, current.day);
  final dayDifference = today.difference(calendarDay).inDays;
  final dayLabel = switch (dayDifference) {
    0 => 'Today',
    1 => 'Yesterday',
    _ when local.year == current.year =>
      '${_monthNames[local.month - 1]} ${local.day}',
    _ => '${_monthNames[local.month - 1]} ${local.day}, ${local.year}',
  };
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = _twoDigits(local.minute);
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$dayLabel, $hour:$minute $period';
}

const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatUptime(double? uptime) {
  if (uptime == null) {
    return '—';
  }
  if (uptime == 100) {
    return '100%';
  }
  return '${uptime.toStringAsFixed(1)}%';
}

/// Presentation copy for a failed check.
///
/// New checks carry structured context. The legacy mappings keep existing
/// databases from showing the old internal probe dump while the first fresh
/// check is still pending.
class HealthFailureCopy {
  const HealthFailureCopy({required this.summary, this.detail});

  factory HealthFailureCopy.fromRecord(CheckRecord record) {
    final rawSummary = record.error?.trim();
    final storedDetail = record.failureDetail?.trim();
    if (rawSummary == null || rawSummary.isEmpty) {
      return HealthFailureCopy(
        summary: 'Health check failed',
        detail: storedDetail?.isEmpty == false ? storedDetail : null,
      );
    }

    final normalized = rawSummary.toLowerCase();
    if (normalized.contains('html placeholder titled "loading') ||
        normalized.contains('page is stuck on “loading')) {
      return HealthFailureCopy(
        summary: 'Page is stuck on “Loading…”',
        detail: storedDetail?.isEmpty == false
            ? storedDetail
            : 'The server answered with HTTP 200, but returned only a loading '
                  'shell. The base URL and common health endpoints were '
                  'checked; none was healthy.',
      );
    }

    if (normalized.startsWith('no healthy response from automatic probes')) {
      final statusCode = RegExp(
        r'(?:base returned\s+)?(?:returned\s+)?http\s+(\d{3})',
        caseSensitive: false,
      ).firstMatch(rawSummary)?.group(1);
      return HealthFailureCopy(
        summary: statusCode == null
            ? 'No healthy endpoint responded'
            : 'Server returned HTTP $statusCode',
        detail: storedDetail?.isEmpty == false
            ? storedDetail
            : 'SiteSignal checked the base URL and common health endpoints; '
                  'none returned a healthy response.',
      );
    }

    if (normalized.startsWith('timed out')) {
      return HealthFailureCopy(
        summary: 'Request timed out',
        detail: storedDetail?.isEmpty == false
            ? storedDetail
            : 'The server did not respond before the check timed out.',
      );
    }

    if (RegExp(r'^http \d{3}$', caseSensitive: false).hasMatch(rawSummary)) {
      final code = rawSummary.split(' ').last;
      return HealthFailureCopy(
        summary: 'Server returned HTTP $code',
        detail: storedDetail?.isEmpty == false
            ? storedDetail
            : 'The endpoint did not return a successful 2xx response.',
      );
    }

    return HealthFailureCopy(
      summary: rawSummary,
      detail: storedDetail?.isEmpty == false ? storedDetail : null,
    );
  }

  final String summary;
  final String? detail;
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppDimensions.s16),
    this.radius = AppDimensions.r12,
    this.color,
    this.side,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final BorderSide? side;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side:
          side ??
          BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
    );
    final body = Padding(padding: padding, child: child);
    if (onTap case final handler?) {
      return Material(
        color: color ?? colorScheme.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: handler, child: body),
      );
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: color ?? colorScheme.surface,
        shape: shape,
      ),
      child: body,
    );
  }
}

class TonalIconBadge extends StatelessWidget {
  const TonalIconBadge({
    required this.icon,
    required this.color,
    this.size = AppDimensions.s40,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.r12),
        ),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, color: color, size: AppDimensions.iconSm),
      ),
    );
  }
}

class AccentChip extends StatelessWidget {
  const AccentChip({
    required this.label,
    required this.accent,
    this.icon,
    super.key,
  });

  final String label;
  final Color accent;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: accent.withValues(alpha: AppDimensions.accentFillChip),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.r6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.s8,
          vertical: AppDimensions.s4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon case final glyph?) ...[
              Icon(glyph, size: AppDimensions.iconXs, color: accent),
              const SizedBox(width: AppDimensions.s4),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
    this.action,
    this.actionLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color accent;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final actionHandler = action;
    final label = actionLabel;
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TonalIconBadge(icon: icon, color: accent),
        const SizedBox(width: AppDimensions.s12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppDimensions.s2),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return SectionCard(
      radius: AppDimensions.r16,
      color: accent.withValues(alpha: AppDimensions.accentFillHero),
      side: BorderSide(
        color: accent.withValues(alpha: AppDimensions.accentBorderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final usesStackedAction =
              constraints.maxWidth < 480 ||
              MediaQuery.textScalerOf(context).scale(16) > 22;
          if (actionHandler == null || label == null) {
            return content;
          }
          if (usesStackedAction) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: AppDimensions.s8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: actionHandler,
                    child: Text(label),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: content),
              const SizedBox(width: AppDimensions.s12),
              TextButton(onPressed: actionHandler, child: Text(label)),
            ],
          );
        },
      ),
    );
  }
}
