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

// Material's published swatches; descendants share their root's color.
const _palettes = [
  Colors.blue,
  Colors.deepPurple,
  Colors.amber,
  Colors.red,
  Colors.orange,
  Colors.cyan,
  Colors.pink,
];
const _defaults = {'work': 0, 'side': 1, 'explore': 2, 'life': 4};

MaterialColor _paletteFor(Store store, String? tagId) {
  if (tagId == null) return Colors.blueGrey;
  final root = store.ancestors(tagId).first.id;
  final index =
      _defaults[root] ??
      root.codeUnits.fold(0, (hash, unit) => (hash * 31 + unit) & 0x7fffffff) %
          _palettes.length;
  return _palettes[index];
}

/// Background and foreground pair that keeps tagged events readable on any
/// surface; use the foreground for text drawn on the background.
(Color, Color) eventColors(Store store, Event event, {bool selected = false}) {
  final palette = _paletteFor(store, event.tagId);
  return (palette[selected ? 200 : 100]!, palette[800]!);
}

/// Accent color for the dot marking a tag in the sidebar.
Color tagDot(Store store, String? tagId) => _paletteFor(store, tagId)[600]!;
