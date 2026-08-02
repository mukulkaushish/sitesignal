import 'package:flutter/material.dart';
import 'package:site_signal/core/theme/app_dimensions.dart';

class PopoverSelectOption<T> {
  const PopoverSelectOption({
    required this.value,
    required this.label,
    this.icon,
    this.description,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? description;
}

/// A form-style selector whose menu uses the app's popover surface and rows.
class PopoverSelectField<T> extends StatefulWidget {
  const PopoverSelectField({
    required this.value,
    required this.options,
    required this.onSelected,
    required this.labelText,
    required this.prefixIcon,
    this.enabled = true,
    this.menuMaxHeight = 320,
    super.key,
  });

  final T value;
  final List<PopoverSelectOption<T>> options;
  final ValueChanged<T> onSelected;
  final String labelText;
  final IconData prefixIcon;
  final bool enabled;
  final double menuMaxHeight;

  @override
  State<PopoverSelectField<T>> createState() => _PopoverSelectFieldState<T>();
}

class _PopoverSelectFieldState<T> extends State<PopoverSelectField<T>> {
  bool _menuOpen = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.options.firstWhere(
      (option) => option.value == widget.value,
      orElse: () => widget.options.first,
    );

    final labelStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
    );
    final descriptionStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final menuWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 280.0;
        return PopupMenuButton<T>(
          enabled: widget.enabled,
          initialValue: widget.value,
          tooltip: 'Choose ${widget.labelText.toLowerCase()}',
          position: PopupMenuPosition.under,
          offset: const Offset(0, AppDimensions.s4),
          constraints: BoxConstraints(
            minWidth: menuWidth,
            maxWidth: menuWidth,
            maxHeight: widget.menuMaxHeight,
          ),
          borderRadius: BorderRadius.circular(AppDimensions.r12),
          clipBehavior: Clip.antiAlias,
          onOpened: () => _setMenuOpen(true),
          onCanceled: () => _setMenuOpen(false),
          onSelected: (value) {
            _setMenuOpen(false);
            widget.onSelected(value);
          },
          itemBuilder: (context) => [
            for (final option in widget.options)
              PopupMenuItem<T>(
                value: option.value,
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: option.icon == null ? null : Icon(option.icon),
                    title: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle,
                    ),
                    subtitle: switch (option.description) {
                      final description? => Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: descriptionStyle,
                      ),
                      null => null,
                    },
                    trailing: option.value == widget.value
                        ? Icon(
                            Icons.check_rounded,
                            size: AppDimensions.iconSm,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
          ],
          child: InputDecorator(
            isEmpty: false,
            isFocused: _menuOpen,
            decoration: InputDecoration(
              labelText: widget.labelText,
              isDense: true,
              enabled: widget.enabled,
              prefixIcon: Icon(widget.prefixIcon),
              suffixIcon: AnimatedRotation(
                turns: _menuOpen ? 0.5 : 0,
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppDimensions.animationFast,
                curve: AppDimensions.easeStandard,
                child: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
            ),
            child: Text(
              selected.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          ),
        );
      },
    );
  }

  void _setMenuOpen(bool open) {
    if (mounted && _menuOpen != open) {
      setState(() => _menuOpen = open);
    }
  }
}
