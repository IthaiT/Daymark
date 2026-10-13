import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/model.dart';

/// Indigo-seeded Material 3 light theme: the accent, surfaces, menus and
/// dialogs all derive from one seed color.
ThemeData daymarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Colors.indigo,
    brightness: Brightness.light,
  );
  OutlineInputBorder inputBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: color),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.light,
    fontFamily: 'Microsoft YaHei UI',
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: scheme.surfaceContainerLow,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: inputBorder(scheme.outlineVariant),
      enabledBorder: inputBorder(scheme.outlineVariant),
      focusedBorder: inputBorder(scheme.primary),
    ),
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(7),
    ),
  );
}

/// Quiet neutral surfaces and a teal accent for the desktop ledger workspace.
ThemeData ledgerTheme(ThemeData base) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.light,
      ).copyWith(
        surface: Colors.white,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: Colors.grey[50],
        surfaceContainer: Colors.grey[100],
        surfaceContainerHigh: Colors.grey[200],
        surfaceContainerHighest: Colors.grey[300],
        outlineVariant: Colors.grey[200],
        onSurface: Colors.grey[900],
        onSurfaceVariant: Colors.grey[700],
      );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide.none,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surfaceContainerLow,
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: scheme.surfaceContainerLow,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: shape,
        foregroundColor: scheme.onSurfaceVariant,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: WidgetStatePropertyAll(shape),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.secondaryContainer
              : scheme.surfaceContainerLow,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

// Anchored family hues, far more than 30° apart on the color wheel: the hue
// expresses the root family, the lightness expresses the member within it.
const _families = [Colors.blue, Colors.deepPurple, Colors.teal, Colors.orange];
const _familyDefaults = {'work': 0, 'side': 1, 'explore': 2, 'life': 3};

// Lightness steps handed out to family members in sidebar (tree) order so
// adjacent siblings always differ; the root itself keeps the middle 500 step.
const _steps = [400, 600, 300, 700, 500, 800];
// Pastel fill and strong ink per step; large timeline areas stay muted while
// the ink carries enough contrast for chips, dots and text.
const _inkPairs = {
  300: (100, 600),
  400: (100, 700),
  500: (100, 800),
  600: (200, 800),
  700: (300, 900),
  800: (300, 900),
};

MaterialColor _familyFor(Store store, String? tagId) {
  if (tagId == null) return Colors.blueGrey;
  final root = store.ancestors(tagId).first.id;
  final index =
      _familyDefaults[root] ??
      root.codeUnits.fold(0, (hash, unit) => (hash * 31 + unit) & 0x7fffffff) %
          _families.length;
  return _families[index];
}

int _stepFor(Store store, String? tagId) {
  if (tagId == null) return 600;
  final root = store.ancestors(tagId).first.id;
  var index = 0;
  for (final tag in store.orderedTags()) {
    if (store.ancestors(tag.id).first.id != root) continue;
    if (tag.id == tagId) break;
    index++;
  }
  return index == 0 ? 500 : _steps[(index - 1) % _steps.length];
}

/// Background and foreground pair that keeps tagged events readable on any
/// surface; use the foreground for text drawn on the background.
(Color, Color) eventColors(Store store, Event event, {bool selected = false}) {
  if (event.tagId == null) {
    return (Colors.blueGrey[selected ? 200 : 100]!, Colors.blueGrey[800]!);
  }
  final family = _familyFor(store, event.tagId);
  final (fill, ink) = _inkPairs[_stepFor(store, event.tagId)]!;
  return (
    family[selected ? (fill >= 300 ? 300 : fill + 100) : fill]!,
    family[ink]!,
  );
}

/// Accent color for the dot marking a tag in the sidebar.
Color tagDot(Store store, String? tagId) =>
    _familyFor(store, tagId)[_stepFor(store, tagId)]!;
