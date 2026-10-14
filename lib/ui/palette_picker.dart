import 'package:flutter/material.dart';

import '../domain/appearance.dart';
import 'theme.dart';

class PalettePicker extends StatelessWidget {
  const PalettePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AppPalette selected;
  final ValueChanged<AppPalette>? onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget label(AppPalette palette) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: paletteSwatch(palette).shade600,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(paletteText(palette)),
        ],
      );
      if (constraints.maxWidth < 370) {
        return Align(
          alignment: Alignment.centerRight,
          child: PopupMenuButton<AppPalette>(
            key: const ValueKey('palette-menu'),
            tooltip: '切换配色',
            enabled: onChanged != null,
            onSelected: onChanged,
            itemBuilder: (_) => [
              for (final palette in AppPalette.values)
                CheckedPopupMenuItem(
                  value: palette,
                  checked: palette == selected,
                  child: label(palette),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: label(selected),
            ),
          ),
        );
      }
      final scheme = Theme.of(context).colorScheme;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final palette in AppPalette.values)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: TextButton(
                key: ValueKey('palette-${palette.name}'),
                onPressed: onChanged == null ? null : () => onChanged!(palette),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  foregroundColor: palette == selected
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                  backgroundColor: palette == selected
                      ? scheme.secondaryContainer
                      : null,
                  textStyle: Theme.of(context).textTheme.bodySmall,
                ),
                child: Semantics(
                  selected: palette == selected,
                  label: '切换到${paletteText(palette)}配色',
                  excludeSemantics: true,
                  child: label(palette),
                ),
              ),
            ),
        ],
      );
    },
  );
}
