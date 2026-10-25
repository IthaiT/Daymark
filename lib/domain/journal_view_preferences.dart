enum JournalViewPreset { focused, fullDay, custom }

/// Display choices do not change recording policy or stored events.
class JournalViewPreferences {
  const JournalViewPreferences({
    this.showRoutine = false,
    this.showUndefined = false,
  });

  static const focused = JournalViewPreferences();
  static const fullDay = JournalViewPreferences(
    showRoutine: true,
    showUndefined: true,
  );

  final bool showRoutine;
  final bool showUndefined;

  JournalViewPreset preset({required bool autoUndefined}) {
    if (!showRoutine && (!autoUndefined || !showUndefined)) {
      return JournalViewPreset.focused;
    }
    if (showRoutine && (!autoUndefined || showUndefined)) {
      return JournalViewPreset.fullDay;
    }
    return JournalViewPreset.custom;
  }

  bool foldsEmptyTime({required bool autoUndefined}) =>
      !showRoutine || autoUndefined && !showUndefined;

  JournalViewPreferences copyWith({bool? showRoutine, bool? showUndefined}) =>
      JournalViewPreferences(
        showRoutine: showRoutine ?? this.showRoutine,
        showUndefined: showUndefined ?? this.showUndefined,
      );

  Map<String, Object> toJson() => {
    'show_routine': showRoutine,
    'show_undefined': showUndefined,
  };

  factory JournalViewPreferences.fromJson(Object? value) {
    if (value is! Map<String, Object?>) return focused;
    return JournalViewPreferences(
      showRoutine: value['show_routine'] is bool
          ? value['show_routine']! as bool
          : false,
      showUndefined: value['show_undefined'] is bool
          ? value['show_undefined']! as bool
          : false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is JournalViewPreferences &&
      showRoutine == other.showRoutine &&
      showUndefined == other.showUndefined;

  @override
  int get hashCode => Object.hash(showRoutine, showUndefined);
}
