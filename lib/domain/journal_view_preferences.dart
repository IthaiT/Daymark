enum JournalViewPreset { focused, fullDay }

/// Display choices do not change recording policy or stored events.
class JournalViewPreferences {
  const JournalViewPreferences({
    this.preset = JournalViewPreset.focused,
    this.showUnclassified = true,
  });

  static const focused = JournalViewPreferences();
  static const fullDay = JournalViewPreferences(
    preset: JournalViewPreset.fullDay,
  );

  final JournalViewPreset preset;
  final bool showUnclassified;
  bool get foldsEmptyTime => preset == JournalViewPreset.focused;

  JournalViewPreferences copyWith({
    JournalViewPreset? preset,
    bool? showUnclassified,
  }) => JournalViewPreferences(
    preset: preset ?? this.preset,
    showUnclassified: showUnclassified ?? this.showUnclassified,
  );

  Map<String, Object> toJson() => {
    'preset': preset.name,
    'show_unclassified': showUnclassified,
  };

  factory JournalViewPreferences.fromJson(Object? value) {
    if (value is! Map<String, Object?>) return focused;
    // Legacy custom choices follow routine visibility, including the old
    // full-day choice when automatic gap generation was disabled.
    var preset = value['show_routine'] == true
        ? JournalViewPreset.fullDay
        : JournalViewPreset.focused;
    for (final item in JournalViewPreset.values) {
      if (value['preset'] == item.name) preset = item;
    }
    return JournalViewPreferences(
      preset: preset,
      showUnclassified: value['show_unclassified'] is bool
          ? value['show_unclassified']! as bool
          : true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is JournalViewPreferences &&
      preset == other.preset &&
      showUnclassified == other.showUnclassified;

  @override
  int get hashCode => Object.hash(preset, showUnclassified);
}
