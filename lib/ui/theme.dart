import 'package:flutter/material.dart';
import '../data/store.dart';
import '../domain/appearance.dart';
import '../domain/model.dart';
import 'tag_visual.dart';
import 'theme_tokens.dart';
import 'workspace_style.dart';

String paletteText(AppPalette palette) => switch (palette) {
  AppPalette.pine => '松石',
  AppPalette.indigo => '靛蓝',
  AppPalette.sand => '暖沙',
  AppPalette.rose => '玫瑰',
  AppPalette.slate => '石板',
};

MaterialColor paletteSwatch(AppPalette palette) => switch (palette) {
  AppPalette.pine => Colors.teal,
  AppPalette.indigo => Colors.indigo,
  AppPalette.sand => Colors.brown,
  AppPalette.rose => Colors.pink,
  AppPalette.slate => Colors.blueGrey,
};

/// Shared Material 3 theme for time recording, the ledger and all dialogs.
ThemeData daymarkTheme({AppPalette palette = AppPalette.slate}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: paletteSwatch(palette),
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    brightness: Brightness.light,
  ).copyWith(surface: Colors.white, surfaceContainerLowest: Colors.white);
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(WorkspaceStyle.controlRadius),
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(WorkspaceStyle.controlRadius),
    borderSide: BorderSide.none,
  );
  TextStyle text(double size, {FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: 1.45,
        letterSpacing: 0,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    extensions: [DaymarkColors.fromScheme(scheme)],
    brightness: Brightness.light,
    fontFamily: 'Noto Sans SC',
    fontFamilyFallback: const ['Segoe UI', 'Microsoft YaHei UI'],
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: scheme.surfaceContainerLow,
    textTheme: TextTheme(
      bodyLarge: text(16),
      bodyMedium: text(14),
      bodySmall: text(12),
      titleLarge: text(20, weight: FontWeight.w600),
      titleMedium: text(16, weight: FontWeight.w600),
      titleSmall: text(14, weight: FontWeight.w500),
      labelLarge: text(14, weight: FontWeight.w500),
      labelMedium: text(12, weight: FontWeight.w500),
      labelSmall: text(12),
      headlineSmall: text(24, weight: FontWeight.w600),
      headlineMedium: text(28, weight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WorkspaceStyle.panelRadius),
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
    scrollbarTheme: const ScrollbarThemeData(
      thickness: WidgetStatePropertyAll(7),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .4),
      thickness: 1,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLowest,
      shape: shape,
      textStyle: text(14),
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
MaterialColor tagFamily(Store store, String? tagId) {
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
  final family = tagFamily(store, event.tagId);
  return tagSurfaceColors(
    family,
    tagDot(store, event.tagId),
    opacity: selected ? .34 : .20,
  );
}

/// Accent color for the dot marking a tag in the sidebar.
Color tagDot(Store store, String? tagId) =>
    tagFamily(store, tagId)[_stepFor(store, tagId)]!;
