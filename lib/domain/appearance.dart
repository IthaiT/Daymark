enum AppPalette { pine, indigo, sand, rose, slate }

/// Selectable tag hues, listed in the order used for automatic assignment.
///
/// Seven anchored hues stay distinguishable as 10px dots, including for
/// red-green colour blindness; more hues would need an icon or a label.
enum TagColor { teal, amber, purple, orange, cyan, pink, blue }

/// Appearance preferences are separate from journal and ledger data.
class AppAppearance {
  const AppAppearance({
    this.palette = AppPalette.slate,
    this.tagColors = const {},
  });

  final AppPalette palette;

  /// Explicit overrides; tags without an entry keep their automatic colour.
  final Map<String, TagColor> tagColors;

  AppAppearance withPalette(AppPalette value) =>
      AppAppearance(palette: value, tagColors: tagColors);

  AppAppearance withTagColor(String id, TagColor? color) {
    final next = {...tagColors};
    if (color == null) {
      next.remove(id);
    } else {
      next[id] = color;
    }
    return AppAppearance(palette: palette, tagColors: Map.unmodifiable(next));
  }

  Map<String, Object> toJson() => {
    'version': 1,
    'palette': palette.name,
    if (tagColors.isNotEmpty)
      'tag_colors': {
        for (final entry in tagColors.entries) entry.key: entry.value.name,
      },
  };

  factory AppAppearance.fromJson(Object? value) {
    if (value is! Map<String, Object?> || value['version'] != 1) {
      throw const FormatException('配色设置格式不正确。');
    }
    AppPalette? palette;
    for (final item in AppPalette.values) {
      if (value['palette'] == item.name) palette = item;
    }
    if (palette == null) {
      throw const FormatException('配色设置包含未知主题。');
    }
    // Unknown ids or colour names are ignored so a newer file still opens.
    final tagColors = <String, TagColor>{};
    final raw = value['tag_colors'];
    if (raw is Map<String, Object?>) {
      for (final entry in raw.entries) {
        for (final color in TagColor.values) {
          if (entry.value == color.name) tagColors[entry.key] = color;
        }
      }
    }
    return AppAppearance(
      palette: palette,
      tagColors: Map.unmodifiable(tagColors),
    );
  }
}
