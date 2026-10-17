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
ThemeData daymarkTheme({
  AppPalette palette = AppPalette.slate,
  Map<String, TagColor> tagColors = const {},
}) {
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
    extensions: [DaymarkColors.fromScheme(scheme), TagColorTheme(tagColors)],
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

String tagColorText(TagColor color) => switch (color) {
  TagColor.teal => '青绿',
  TagColor.amber => '金色',
  TagColor.purple => '紫色',
  TagColor.orange => '橙色',
  TagColor.cyan => '青色',
  TagColor.pink => '粉色',
  TagColor.blue => '蓝色',
};

MaterialColor tagColorSwatch(TagColor color) => switch (color) {
  TagColor.teal => Colors.teal,
  TagColor.amber => Colors.amber,
  TagColor.purple => Colors.deepPurple,
  TagColor.orange => Colors.orange,
  TagColor.cyan => Colors.cyan,
  TagColor.pink => Colors.pink,
  TagColor.blue => Colors.blue,
};

/// Keeps the four original root tags on their familiar colours.
const _tagDefaults = {
  'work': TagColor.blue,
  'side': TagColor.purple,
  'explore': TagColor.teal,
  'life': TagColor.orange,
};

// Anchored family hues, far apart on the color wheel: the hue expresses the
// root family, the lightness expresses the member within it.
// Lightness steps are handed out in sidebar (tree) order so adjacent siblings
// always differ; the root keeps its family's anchor step.
const _steps = [400, 600, 300, 700, 500, 800];

Map<String, TagColor> tagColorOverrides(BuildContext context) =>
    Theme.of(context).extension<TagColorTheme>()?.overrides ??
    const <String, TagColor>{};

int _tagHash(String id) =>
    id.codeUnits.fold(0, (sum, unit) => (sum * 31 + unit) & 0x7fffffff);

/// A root hue that no other root already uses, until all seven are taken.
///
/// Roots are walked in creation order, which a move does not change, so moving
/// a child tag out to the root list only picks a free hue instead of recolouring
/// its siblings. Beyond seven roots the hash repeats, as no free hue is left.
TagColor rootTagColor(
  Store store,
  String rootId,
  Map<String, TagColor> overrides,
) {
  // Reserve every explicit or preset root colour first so an automatic tag can
  // never take a hue that a later root already claims.
  final fixed = <String, TagColor>{};
  for (final tag in store.tags.values) {
    if (tag.parentId != null) continue;
    final color = overrides[tag.id] ?? _tagDefaults[tag.id];
    if (color != null) fixed[tag.id] = color;
  }
  final preset = fixed[rootId];
  if (preset != null) return preset;

  final used = {...fixed.values};
  for (final tag in store.tags.values) {
    if (tag.parentId != null || fixed.containsKey(tag.id)) continue;
    if (used.length >= TagColor.values.length) {
      final repeated =
          TagColor.values[_tagHash(tag.id) % TagColor.values.length];
      if (tag.id == rootId) return repeated;
      continue;
    }
    var index = _tagHash(tag.id) % TagColor.values.length;
    while (used.contains(TagColor.values[index])) {
      index = (index + 1) % TagColor.values.length;
    }
    final color = TagColor.values[index];
    if (tag.id == rootId) return color;
    used.add(color);
  }
  return TagColor.values[_tagHash(rootId) % TagColor.values.length];
}

/// The nearest explicit override wins, then the root tag's automatic hue.
MaterialColor tagFamilyFor(
  Store store,
  String? tagId,
  Map<String, TagColor> overrides,
) {
  if (tagId == null) return Colors.blueGrey;
  final path = store.ancestors(tagId);
  for (final tag in path.reversed) {
    final color = overrides[tag.id];
    if (color != null) return tagColorSwatch(color);
  }
  return tagColorSwatch(rootTagColor(store, path.first.id, overrides));
}

MaterialColor tagFamily(BuildContext context, Store store, String? tagId) =>
    tagFamilyFor(store, tagId, tagColorOverrides(context));

/// Cyan uses a darker anchor so it stays distinct from blue at 10px.
int _rootStep(MaterialColor family) => family == Colors.cyan ? 600 : 500;

int _stepFor(Store store, String? tagId, MaterialColor family) {
  if (tagId == null) return 600;
  final root = store.ancestors(tagId).first.id;
  var index = 0;
  for (final tag in store.orderedTags()) {
    if (store.ancestors(tag.id).first.id != root) continue;
    if (tag.id == tagId) break;
    index++;
  }
  return index == 0 ? _rootStep(family) : _steps[(index - 1) % _steps.length];
}

/// Background and foreground pair that keeps tagged events readable on any
/// surface; use the foreground for text drawn on the background.
(Color, Color) eventColorsFor(
  Store store,
  Event event,
  Map<String, TagColor> overrides, {
  bool selected = false,
}) {
  if (event.tagId == null) {
    return (Colors.blueGrey[selected ? 200 : 100]!, Colors.blueGrey[800]!);
  }
  final family = tagFamilyFor(store, event.tagId, overrides);
  return tagSurfaceColors(
    family,
    tagDotFor(store, event.tagId, overrides),
    opacity: selected ? .34 : .20,
  );
}

(Color, Color) eventColors(
  BuildContext context,
  Store store,
  Event event, {
  bool selected = false,
}) => eventColorsFor(
  store,
  event,
  tagColorOverrides(context),
  selected: selected,
);

/// Accent color for the dot marking a tag in the sidebar.
Color tagDotFor(Store store, String? tagId, Map<String, TagColor> overrides) {
  final family = tagFamilyFor(store, tagId, overrides);
  return family[_stepFor(store, tagId, family)]!;
}

Color tagDot(BuildContext context, Store store, String? tagId) =>
    tagDotFor(store, tagId, tagColorOverrides(context));
