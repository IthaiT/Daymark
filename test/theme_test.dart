import 'dart:io';

import 'package:daymark/data/store.dart';
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

  test(
    'seven tag hues keep the original roots and inherit overrides',
    () async {
      final directory = await Directory(
        '.test-artifacts',
      ).createTemp('tag-color-');
      addTearDown(() => directory.delete(recursive: true));
      final store = await Store.open(directory);

      expect(TagColor.values.length, 7);
      expect(TagColor.values.map(tagColorSwatch).toSet().length, 7);
      expect(tagFamilyFor(store, 'work', const {}), Colors.blue);
      expect(tagFamilyFor(store, 'side', const {}), Colors.deepPurple);
      expect(tagFamilyFor(store, 'explore', const {}), Colors.teal);
      expect(tagFamilyFor(store, 'life', const {}), Colors.orange);
      expect(tagFamilyFor(store, 'linux', const {}), Colors.blue);

      expect(
        tagFamilyFor(store, 'work', const {'work': TagColor.pink}),
        Colors.pink,
      );
      expect(
        tagFamilyFor(store, 'linux', const {'work': TagColor.pink}),
        Colors.pink,
      );
      // The closest ancestor wins over a further one.
      expect(
        tagFamilyFor(store, 'linux', const {
          'work': TagColor.pink,
          'embedded': TagColor.amber,
        }),
        Colors.amber,
      );
      expect(
        tagFamilyFor(store, 'linux', const {'linux': TagColor.teal}),
        Colors.teal,
      );
      expect(tagFamilyFor(store, null, const {}), Colors.blueGrey);

      expect(tagDotFor(store, 'work', const {}), Colors.blue[500]);
      // Cyan uses a darker anchor so it stays apart from blue at 10px.
      expect(
        tagDotFor(store, 'explore', const {'explore': TagColor.cyan}),
        Colors.cyan[600],
      );
    },
  );

  test('root tags take free hues before any colour repeats', () async {
    final directory = await Directory(
      '.test-artifacts',
    ).createTemp('root-colours-');
    addTearDown(() => directory.delete(recursive: true));
    final store = await Store.open(directory);
    List<Color> rootColors() => [
      for (final tag in store.tags.values)
        if (tag.parentId == null) tagFamilyFor(store, tag.id, const {}),
    ];
    final presets = {
      Colors.blue,
      Colors.deepPurple,
      Colors.teal,
      Colors.orange,
    };

    // Moving a child out to the root list must not reuse a preset hue.
    final sleep = await store.saveTag('睡觉', null);
    expect(rootColors().toSet().length, 5);
    expect(presets.contains(tagFamilyFor(store, sleep.id, const {})), isFalse);
    await store.saveTag('睡眠', null, id: 'rest');
    expect(rootColors().toSet().length, 6);
    expect(presets.contains(tagFamilyFor(store, 'rest', const {})), isFalse);

    // Seven roots still keep seven different hues.
    await store.saveTag('学习', null);
    expect(rootColors().toSet().length, 7);
    // The eighth root has to repeat, but must not disturb the seven above.
    final before = rootColors();
    await store.saveTag('健康', null);
    final after = rootColors();
    expect(after.toSet().length, 7);
    expect(after.take(8).toSet().length, 7);
    expect(after.take(7).toSet().length, 7);
    expect(before.toSet().length, 7);
    // The four original roots keep their familiar colours.
    expect(tagFamilyFor(store, 'work', const {}), Colors.blue);
    expect(tagFamilyFor(store, 'side', const {}), Colors.deepPurple);
    expect(tagFamilyFor(store, 'explore', const {}), Colors.teal);
    expect(tagFamilyFor(store, 'life', const {}), Colors.orange);
  });
}
