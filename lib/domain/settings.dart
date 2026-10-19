/// Timeline drag steps offered in settings, in minutes.
const dragGranularities = <int>[1, 5, 10, 15, 30, 60];

String dragGranularityText(int minutes) =>
    minutes == 60 ? '1 小时' : '$minutes 分钟';

/// Recording preferences, kept separate from journal and ledger records.
class AppSettings {
  const AppSettings({
    this.autoUndefined = true,
    this.dragMinutes = 1,
    this.splitOverlap = false,
  }) : assert(dragMinutes > 0);

  /// Whether the empty spans between events become derived “未定义” records.
  final bool autoUndefined;

  /// Step used when dragging or resizing an event on the timeline.
  final int dragMinutes;

  /// Whether statistics share an instant between concurrently running events.
  ///
  /// When enabled, four parallel events covering the same four hours report
  /// one hour each instead of four hours each. Off by default so existing
  /// totals stay unchanged.
  final bool splitOverlap;

  AppSettings copyWith({
    bool? autoUndefined,
    int? dragMinutes,
    bool? splitOverlap,
  }) => AppSettings(
    autoUndefined: autoUndefined ?? this.autoUndefined,
    dragMinutes: dragMinutes ?? this.dragMinutes,
    splitOverlap: splitOverlap ?? this.splitOverlap,
  );

  Map<String, Object> toJson() => {
    'version': 1,
    'auto_undefined': autoUndefined,
    'drag_minutes': dragMinutes,
    'split_overlap': splitOverlap,
  };

  factory AppSettings.fromJson(Object? value) {
    if (value is! Map<String, Object?> || value['version'] != 1) {
      throw const FormatException('记录设置格式不正确。');
    }
    // Unknown or missing values fall back, so a newer file still opens.
    final auto = value['auto_undefined'];
    final minutes = value['drag_minutes'];
    final split = value['split_overlap'];
    return AppSettings(
      autoUndefined: auto is bool ? auto : true,
      dragMinutes: minutes is int && dragGranularities.contains(minutes)
          ? minutes
          : 1,
      splitOverlap: split is bool ? split : false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.autoUndefined == autoUndefined &&
      other.dragMinutes == dragMinutes &&
      other.splitOverlap == splitOverlap;

  @override
  int get hashCode => Object.hash(autoUndefined, dragMinutes, splitOverlap);
}
