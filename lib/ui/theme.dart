import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/model.dart';

ThemeData daymarkTheme() => ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  fontFamily: 'Microsoft YaHei UI',
  visualDensity: VisualDensity.compact,
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  ),
  scrollbarTheme: const ScrollbarThemeData(
    thickness: WidgetStatePropertyAll(7),
  ),
);

// Material's published swatches; descendants share their root's color.
Color eventColor(Store store, Event event, {bool selected = false}) {
  if (event.tagId == null) {
    return selected ? Colors.grey.shade300 : Colors.grey.shade100;
  }
  final root = store.ancestors(event.tagId).first.id;
  const palettes = [
    Colors.blue,
    Colors.deepPurple,
    Colors.amber,
    Colors.red,
    Colors.orange,
    Colors.cyan,
    Colors.pink,
  ];
  const defaults = {'work': 0, 'side': 1, 'explore': 2, 'life': 4};
  final index =
      defaults[root] ??
      root.codeUnits.fold(0, (hash, unit) => (hash * 31 + unit) & 0x7fffffff) %
          palettes.length;
  return palettes[index][selected ? 100 : 50]!;
}
