import 'package:flutter/material.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';
import 'package:site_signal/core/theme/app_semantic_colors.dart';
import 'package:site_signal/features/monitoring/domain/entities/site_monitor.dart';
import 'package:site_signal/features/monitoring/domain/services/monitoring_policy.dart';
import 'package:site_signal/features/monitoring/presentation/controllers/monitor_controller.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/monitor_ui.dart';

Future<void> showMonitorDialog(
  BuildContext context, {
  required MonitorController controller,
  SiteMonitor? site,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => MonitorDialog(controller: controller, site: site),
  );
}

class MonitorDialog extends StatefulWidget {
  const MonitorDialog({required this.controller, this.site, super.key});

  final MonitorController controller;
  final SiteMonitor? site;

  @override
  State<MonitorDialog> createState() => _MonitorDialogState();
}

class _MonitorDialogState extends State<MonitorDialog> {
  static const _intervals = <int>[
    MonitoringPolicy.minimumIntervalSeconds,
    30,
    MonitoringPolicy.defaultIntervalSeconds,
    300,
    900,
    1800,
    3600,
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late int _intervalSeconds;
  bool _saving = false;
  String? _submitError;

  bool get _isEditing => widget.site != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.site?.name ?? '');
    _urlController = TextEditingController(text: widget.site?.baseUrl ?? '');
    _intervalSeconds = widget.site?.intervalSeconds ?? 60;
    if (!_intervals.contains(_intervalSeconds)) {
      _intervalSeconds = 60;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _submitError = null;
    });

    try {
      final site = widget.site;
      if (site != null) {
        await widget.controller.updateSite(
          id: site.id,
          name: _nameController.text,
          baseUrl: _urlController.text,
          intervalSeconds: _intervalSeconds,
        );
      } else {
        await widget.controller.addSite(
          name: _nameController.text,
          baseUrl: _urlController.text,
          intervalSeconds: _intervalSeconds,
        );
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _submitError =
              error.message?.toString() ?? 'Could not save the site.';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _submitError = 'Could not save the site: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppDimensions.s24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.s24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TonalIconBadge(
                      icon: _isEditing
                          ? Icons.edit_rounded
                          : Icons.add_link_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppDimensions.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing ? 'Edit monitor' : 'Add a website',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'SiteSignal discovers a health endpoint automatically.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.s24),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Production API',
                    helperText:
                        'Optional — the host name is used if left blank.',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(height: AppDimensions.s16),
                TextFormField(
                  key: const ValueKey('monitor-url-field'),
                  controller: _urlController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://example.com',
                    helperText:
                        'Enter only the origin. Common health paths are tried '
                        'automatically.',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  validator: (value) =>
                      SiteMonitor.validateBaseUrl(value ?? ''),
                ),
                const SizedBox(height: AppDimensions.s16),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: AppDimensions.iconSm,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppDimensions.s8),
                    Text(
                      'Check frequency',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppDimensions.s4),
                Text(
                  'How often should SiteSignal test this website?',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppDimensions.s10),
                Wrap(
                  spacing: AppDimensions.s8,
                  runSpacing: AppDimensions.s8,
                  children: [
                    for (final interval in _intervals)
                      ChoiceChip(
                        key: ValueKey('monitor-interval-$interval'),
                        label: Text(formatInterval(interval)),
                        selected: _intervalSeconds == interval,
                        showCheckmark: true,
                        onSelected: _saving
                            ? null
                            : (selected) {
                                if (selected) {
                                  setState(() => _intervalSeconds = interval);
                                }
                              },
                      ),
                  ],
                ),
                const SizedBox(height: AppDimensions.s12),
                SectionCard(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.25),
                  ),
                  padding: const EdgeInsets.all(AppDimensions.s12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.route_outlined,
                        size: AppDimensions.iconSm,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: AppDimensions.s8),
                      Expanded(
                        child: Text(
                          'Automatic discovery tries the base URL, /health, '
                          '/healthz, /livez, /readyz, /api/health, '
                          '/actuator/health, and /status.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_submitError case final submitError?) ...[
                  const SizedBox(height: AppDimensions.s12),
                  SectionCard(
                    color: context.semanticColors.error.withValues(alpha: 0.08),
                    side: BorderSide(
                      color: context.semanticColors.error.withValues(
                        alpha: 0.25,
                      ),
                    ),
                    padding: const EdgeInsets.all(AppDimensions.s12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: AppDimensions.iconSm,
                          color: context.semanticColors.error,
                        ),
                        const SizedBox(width: AppDimensions.s8),
                        Expanded(child: Text(submitError)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppDimensions.s20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppDimensions.s8),
                    FilledButton.icon(
                      key: const ValueKey('save-monitor-button'),
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: AppDimensions.s16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _isEditing
                                  ? Icons.check_rounded
                                  : Icons.add_rounded,
                            ),
                      label: Text(_isEditing ? 'Save changes' : 'Add monitor'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
