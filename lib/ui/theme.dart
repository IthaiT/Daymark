import 'package:flutter/material.dart';
import '../data/store.dart';
import '../domain/appearance.dart';
import '../domain/model.dart';
import '../domain/journal_presentation.dart';
import '../domain/tag_colors.dart';
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
  Map<String, TagDisplay> tagDisplays = const {},
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
    extensions: [
      DaymarkColors.fromScheme(scheme),
      TagColorTheme(tagColors, displays: tagDisplays),
    ],
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
  TagColor.brown => '棕色',
};

MaterialColor tagColorSwatch(TagColor color) => switch (color) {
  TagColor.teal => Colors.teal,
  TagColor.amber => Colors.amber,
  TagColor.purple => Colors.deepPurple,
  TagColor.orange => Colors.orange,
  TagColor.cyan => Colors.cyan,
  TagColor.pink => Colors.pink,
  TagColor.blue => Colors.blue,
  TagColor.brown => Colors.brown,
};

Map<String, TagColor> tagColorOverrides(BuildContext context) =>
    Theme.of(context).extension<TagColorTheme>()?.overrides ??
    const <String, TagColor>{};

Map<String, TagDisplay> tagDisplayOverrides(BuildContext context) =>
    Theme.of(context).extension<TagColorTheme>()?.displays ?? const {};

/// Fallback for callers without persisted appearance preferences.
TagColor rootTagColor(
  Store store,
  String rootId,
  Map<String, TagColor> overrides,
) => assignRootColors(store.tags.values, overrides)[rootId] ?? TagColor.blue;

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

/// Shared ordinary-event and tag-chip colors, including routine backgrounds.
(Color, Color) tagEventColorsFor(
  Store store,
  String? tagId,
  Map<String, TagColor> overrides, {
  bool selected = false,
  Map<String, TagDisplay> tagDisplays = const {},
}) {
  if (effectiveTagDisplay(store.tags, tagId, tagDisplays) ==
      TagDisplay.routine) {
    return (Colors.grey[selected ? 300 : 200]!, Colors.grey[800]!);
  }
  if (tagId == null) {
    return (Colors.blueGrey[selected ? 100 : 50]!, Colors.blueGrey[800]!);
  }
  final family = tagFamilyFor(store, tagId, overrides);
  return tagSurfaceColors(
    family,
    tagDotFor(store, tagId, overrides),
    opacity: selected ? .40 : .28,
  );
}

(Color, Color) tagEventColors(
  BuildContext context,
  Store store,
  String? tagId,
) => tagEventColorsFor(
  store,
  tagId,
  tagColorOverrides(context),
  tagDisplays: tagDisplayOverrides(context),
);

/// Derived gaps use their neutral style; ordinary records share tag colors.
(Color, Color) eventColorsFor(
  Store store,
  Event event,
  Map<String, TagColor> overrides, {
  bool selected = false,
  Map<String, TagDisplay> tagDisplays = const {},
}) {
  if (event.isUndefined &&
      effectiveTagDisplay(store.tags, event.tagId, tagDisplays) !=
          TagDisplay.routine) {
    return (
      Colors.grey[selected
          ? 200
          : isUnfilledGap(event)
          ? 50
          : 100]!,
      Colors.grey[800]!,
    );
  }
  return tagEventColorsFor(
    store,
    event.tagId,
    overrides,
    selected: selected,
    tagDisplays: tagDisplays,
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
  tagDisplays: tagDisplayOverrides(context),
);

/// Accent color for the dot marking a tag in the sidebar.
Color tagDotFor(Store store, String? tagId, Map<String, TagColor> overrides) {
  final family = tagFamilyFor(store, tagId, overrides);
  return family[tagId == null ? 600 : _rootStep(family)]!;
}

Color tagDot(BuildContext context, Store store, String? tagId) =>
    effectiveTagDisplay(store.tags, tagId, tagDisplayOverrides(context)) ==
        TagDisplay.routine
    ? Colors.grey[600]!
    : tagDotFor(store, tagId, tagColorOverrides(context));
