import 'package:daymark/domain/appearance.dart';
import 'package:daymark/domain/ledger.dart';
import 'package:daymark/ui/ledger_category_style.dart';
import 'package:daymark/ui/tag_visual.dart';
import 'package:daymark/ui/theme.dart';
import 'package:daymark/ui/theme_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color first, Color second) {
  final a = first.computeLuminance() + .05;
  final b = second.computeLuminance() + .05;
  return a > b ? a / b : b / a;
}

void main() {
  test('all presets keep Material text and financial amounts readable', () {
    final primaryColors = <Color>{};
    for (final palette in AppPalette.values) {
      final theme = daymarkTheme(palette: palette);
      final scheme = theme.colorScheme;
      final colors = theme.extension<DaymarkColors>()!;
      primaryColors.add(scheme.primary);
      for (final (fill, ink) in [
        (scheme.primary, scheme.onPrimary),
        (scheme.secondaryContainer, scheme.onSecondaryContainer),
        (scheme.surface, scheme.onSurface),
        (scheme.surfaceContainerLow, scheme.onSurfaceVariant),
        (scheme.surface, colors.income),
        (scheme.surface, colors.expense),
      ]) {
        expect(contrast(fill, ink), greaterThanOrEqualTo(4.5));
      }
    }
    expect(primaryColors.length, AppPalette.values.length);
  });

  test(
    'theme-aware category badges preserve contrast and category identity',
    () {
      for (final palette in AppPalette.values) {
        final colors = daymarkTheme(
          palette: palette,
        ).extension<DaymarkColors>()!;
        final accents = <Color>{};
        for (final family in CategoryColor.values) {
          final swatch = categorySwatch(family);
          final accent = colors.categoryAccent(swatch.shade300);
          accents.add(accent);
          final (fill, ink) = tagSurfaceColors(
            swatch,
            accent,
            surface: colors.badgeSurface,
            fallbackInk: colors.badgeFallbackInk,
          );
          expect(contrast(fill, ink), greaterThanOrEqualTo(4.5));
        }
        expect(accents.length, CategoryColor.values.length);
      }
    },
  );
}
