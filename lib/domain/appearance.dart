enum AppPalette { pine, indigo, sand, rose, slate }

/// Appearance preferences are separate from journal and ledger data.
class AppAppearance {
  const AppAppearance({this.palette = AppPalette.slate});

  final AppPalette palette;

  AppAppearance withPalette(AppPalette value) => AppAppearance(palette: value);

  Map<String, Object> toJson() => {'version': 1, 'palette': palette.name};

  factory AppAppearance.fromJson(Object? value) {
    if (value is! Map<String, Object?> || value['version'] != 1) {
      throw const FormatException('配色设置格式不正确。');
    }
    for (final palette in AppPalette.values) {
      if (value['palette'] == palette.name) {
        return AppAppearance(palette: palette);
      }
    }
    throw const FormatException('配色设置包含未知主题。');
  }
}
