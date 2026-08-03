import 'package:flutter/material.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';
import 'package:site_signal/features/updates/domain/entities/app_update.dart';

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    required this.update,
    required this.onViewRelease,
    super.key,
  });

  final AppUpdate update;
  final VoidCallback onViewRelease;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'SiteSignal ${update.version} is available',
      child: ColoredBox(
        color: colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.s16,
            vertical: AppDimensions.s10,
          ),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt_rounded,
                color: colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: AppDimensions.s12),
              Expanded(
                child: Text(
                  'SiteSignal ${update.version} is available. Updating is recommended.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppDimensions.s12),
              FilledButton.tonal(
                key: const ValueKey('view-available-update'),
                onPressed: onViewRelease,
                child: const Text('View update'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
