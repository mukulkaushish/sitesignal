import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_signal/core/theme/app_accent_color.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';
import 'package:site_signal/features/monitoring/presentation/widgets/monitor_ui.dart';

/// Desktop-first accent editor adapted from digii-mobile's one-seed theme
/// model. It uses only Flutter primitives, keeping the packaged app small.
class AccentColorDialog extends StatefulWidget {
  const AccentColorDialog({
    required this.initialColor,
    required this.onChanged,
    super.key,
  });

  final Color initialColor;
  final ValueChanged<Color> onChanged;

  @override
  State<AccentColorDialog> createState() => _AccentColorDialogState();
}

class _AccentColorDialogState extends State<AccentColorDialog> {
  late HSVColor _candidate;
  late final TextEditingController _hexController;

  Color get _color => _candidate.toColor();

  @override
  void initState() {
    super.initState();
    _candidate = HSVColor.fromColor(widget.initialColor);
    _hexController = TextEditingController(
      text: AppAccentColor.hex(widget.initialColor),
    );
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _selectColor(Color color) {
    setState(() {
      _candidate = HSVColor.fromColor(color);
      _syncHex(color);
    });
    widget.onChanged(color);
  }

  void _previewHsv(HSVColor color) {
    setState(() {
      _candidate = color;
      _syncHex(color.toColor());
    });
  }

  void _commitCandidate() => widget.onChanged(_color);

  void _onHexChanged(String input) {
    final color = AppAccentColor.parseHex(input);
    if (color == null) {
      setState(() {});
      return;
    }
    setState(() => _candidate = HSVColor.fromColor(color));
    widget.onChanged(color);
  }

  void _syncHex(Color color) {
    final selection = _hexController.selection;
    _hexController.text = AppAccentColor.hex(color);
    if (selection.isValid && selection.end <= _hexController.text.length) {
      _hexController.selection = selection;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final maxHeight = (viewport.height - AppDimensions.s48).clamp(360.0, 680.0);
    final preset = AppAccentColor.presetFor(_color);
    final readable = AppAccentColor.readableOnBothSurfaces(_color);

    return Dialog(
      insetPadding: const EdgeInsets.all(AppDimensions.s24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDimensions.s20,
                AppDimensions.s16,
                AppDimensions.s12,
                AppDimensions.s12,
              ),
              child: Row(
                children: [
                  TonalIconBadge(icon: Icons.palette_outlined, color: _color),
                  const SizedBox(width: AppDimensions.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Primary color',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppDimensions.s2),
                        Text(
                          preset?.name ??
                              'Custom · #${AppAccentColor.hex(_color)}',
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
                  IconButton(
                    tooltip: 'Close',
                    onPressed: Navigator.of(context).pop,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.s20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AccentPreview(color: _color),
                    const SizedBox(height: AppDimensions.s20),
                    const _SectionLabel(
                      icon: Icons.grid_view_outlined,
                      label: 'Curated colors',
                    ),
                    const SizedBox(height: AppDimensions.s10),
                    Wrap(
                      spacing: AppDimensions.s8,
                      runSpacing: AppDimensions.s8,
                      children: [
                        for (final option in AppAccentColor.presets)
                          _ColorSwatch(
                            preset: option,
                            selected:
                                option.color.toARGB32() == _color.toARGB32(),
                            onTap: () => _selectColor(option.color),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppDimensions.s20),
                    const _SectionLabel(
                      icon: Icons.tune_rounded,
                      label: 'Custom color',
                    ),
                    const SizedBox(height: AppDimensions.s10),
                    _SaturationValuePicker(
                      hsv: _candidate,
                      onChanged: _previewHsv,
                      onChangeEnd: _commitCandidate,
                    ),
                    const SizedBox(height: AppDimensions.s10),
                    _HuePicker(
                      hue: _candidate.hue,
                      onChanged: (hue) => _previewHsv(_candidate.withHue(hue)),
                      onChangeEnd: _commitCandidate,
                    ),
                    const SizedBox(height: AppDimensions.s12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('accent-color-hex-field'),
                            controller: _hexController,
                            maxLength: 6,
                            inputFormatters: <TextInputFormatter>[
                              FilteringTextInputFormatter.allow(
                                RegExp('[0-9a-fA-F]'),
                              ),
                            ],
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: 'Hex color',
                              prefixText: '#',
                              counterText: '',
                              errorText:
                                  _hexController.text.isEmpty ||
                                      AppAccentColor.parseHex(
                                            _hexController.text,
                                          ) !=
                                          null
                                  ? null
                                  : 'Use 6 hex characters',
                            ),
                            onChanged: _onHexChanged,
                            onSubmitted: (_) => _commitCandidate(),
                          ),
                        ),
                        const SizedBox(width: AppDimensions.s10),
                        SizedBox(
                          height: AppDimensions.buttonHeight,
                          child: TextButton.icon(
                            onPressed:
                                _color.toARGB32() ==
                                    AppAccentColor.defaultColor.toARGB32()
                                ? null
                                : () =>
                                      _selectColor(AppAccentColor.defaultColor),
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Reset'),
                          ),
                        ),
                      ],
                    ),
                    if (!readable) ...[
                      const SizedBox(height: AppDimensions.s10),
                      const _ContrastNotice(),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppDimensions.s12),
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: const ValueKey('accent-color-done'),
                  onPressed: Navigator.of(context).pop,
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccentPreview extends StatelessWidget {
  const _AccentPreview({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final foreground = AppAccentColor.onColor(color);
    return SectionCard(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      side: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: 0.65),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppDimensions.s16,
        runSpacing: AppDimensions.s12,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.r12),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDimensions.s16,
                vertical: AppDimensions.s10,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_rounded,
                    size: AppDimensions.iconSm,
                    color: foreground,
                  ),
                  const SizedBox(width: AppDimensions.s6),
                  Text(
                    'Primary action',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ),
          AccentChip(
            label: 'Selected',
            accent: color,
            icon: Icons.auto_awesome_rounded,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_outlined, color: color),
              const SizedBox(width: AppDimensions.s12),
              Icon(Icons.monitor_heart_outlined, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppAccentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final checkColor = AppAccentColor.onColor(preset.color);
    return Tooltip(
      message: preset.name,
      child: Semantics(
        label: '${preset.name} primary color',
        selected: selected,
        button: true,
        child: InkResponse(
          key: ValueKey('accent-color-${AppAccentColor.hex(preset.color)}'),
          onTap: onTap,
          radius: AppDimensions.s24,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppDimensions.animationFast,
                width: AppDimensions.s40,
                height: AppDimensions.s40,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  shape: CircleBorder(
                    side: BorderSide(
                      color: selected
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
                child: Container(
                  width: AppDimensions.s28,
                  height: AppDimensions.s28,
                  decoration: ShapeDecoration(
                    color: preset.color,
                    shape: const CircleBorder(),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          size: AppDimensions.iconXs,
                          color: checkColor,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: AppDimensions.iconSm,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: AppDimensions.s8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SaturationValuePicker extends StatelessWidget {
  const _SaturationValuePicker({
    required this.hsv,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final VoidCallback onChangeEnd;

  void _update(Offset position, Size size) {
    final saturation = (position.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - (position.dy / size.height)).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(saturation).withValue(value));
  }

  void _adjust({double saturation = 0, double value = 0}) {
    onChanged(
      hsv
          .withSaturation((hsv.saturation + saturation).clamp(0.0, 1.0))
          .withValue((hsv.value + value).clamp(0.0, 1.0)),
    );
    onChangeEnd();
  }

  @override
  Widget build(BuildContext context) {
    final hueColor = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    return Semantics(
      label: 'Color saturation and brightness',
      focusable: true,
      value:
          '${(hsv.saturation * 100).round()}% saturation, '
          '${(hsv.value * 100).round()}% brightness',
      increasedValue:
          '${((hsv.saturation + 0.05).clamp(0.0, 1.0) * 100).round()}% saturation',
      decreasedValue:
          '${((hsv.saturation - 0.05).clamp(0.0, 1.0) * 100).round()}% saturation',
      onIncrease: () => _adjust(saturation: 0.05),
      onDecrease: () => _adjust(saturation: -0.05),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _adjust(saturation: -0.05),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _adjust(saturation: 0.05),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              _adjust(value: 0.05),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              _adjust(value: -0.05),
        },
        child: Focus(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppDimensions.r12),
            child: SizedBox(
              height: 128,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        _update(details.localPosition, size),
                    onTapUp: (_) => onChangeEnd(),
                    onPanStart: (details) =>
                        _update(details.localPosition, size),
                    onPanUpdate: (details) =>
                        _update(details.localPosition, size),
                    onPanEnd: (_) => onChangeEnd(),
                    child: Stack(
                      children: [
                        Positioned.fill(child: ColoredBox(color: hueColor)),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: <Color>[
                                  Colors.white,
                                  Color(0x00FFFFFF),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  Color(0x00000000),
                                  Colors.black,
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: (hsv.saturation * size.width - 9).clamp(
                            0.0,
                            size.width - 18,
                          ),
                          top: ((1 - hsv.value) * size.height - 9).clamp(
                            0.0,
                            size.height - 18,
                          ),
                          child: _PickerThumb(color: hsv.toColor()),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HuePicker extends StatelessWidget {
  const _HuePicker({
    required this.hue,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double hue;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  static final List<Color> _hues = <Color>[
    for (var hue = 0; hue <= 360; hue += 60)
      HSVColor.fromAHSV(1, hue.toDouble(), 1, 1).toColor(),
  ];

  void _update(double dx, double width) {
    onChanged((dx / width * 360).clamp(0.0, 360.0));
  }

  void _adjust(double delta) {
    onChanged((hue + delta).clamp(0.0, 360.0));
    onChangeEnd();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Color hue',
      focusable: true,
      value: '${hue.round()} degrees',
      increasedValue: '${(hue + 5).clamp(0.0, 360.0).round()} degrees',
      decreasedValue: '${(hue - 5).clamp(0.0, 360.0).round()} degrees',
      onIncrease: () => _adjust(5),
      onDecrease: () => _adjust(-5),
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _adjust(-5),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _adjust(5),
        },
        child: Focus(
          child: SizedBox(
            height: AppDimensions.s48,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) =>
                      _update(details.localPosition.dx, width),
                  onTapUp: (_) => onChangeEnd(),
                  onPanStart: (details) =>
                      _update(details.localPosition.dx, width),
                  onPanUpdate: (details) =>
                      _update(details.localPosition.dx, width),
                  onPanEnd: (_) => onChangeEnd(),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Positioned.fill(
                        top: AppDimensions.s4,
                        bottom: AppDimensions.s4,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            gradient: LinearGradient(colors: _hues),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (hue / 360 * width - 9).clamp(0.0, width - 18),
                        child: _PickerThumb(
                          color: HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerThumb extends StatelessWidget {
  const _PickerThumb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x40000000), blurRadius: 3),
        ],
      ),
    );
  }
}

class _ContrastNotice extends StatelessWidget {
  const _ContrastNotice();

  @override
  Widget build(BuildContext context) {
    final warning = Theme.of(context).colorScheme.tertiary;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: warning.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.r8),
          side: BorderSide(color: warning.withValues(alpha: 0.28)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppDimensions.s10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.contrast_rounded,
              size: AppDimensions.iconSm,
              color: warning,
            ),
            const SizedBox(width: AppDimensions.s8),
            Expanded(
              child: Text(
                'This color may be difficult to see on either the light or '
                'dark background. Try a stronger mid-tone.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
