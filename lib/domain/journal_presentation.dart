import 'appearance.dart';
import 'journal_view_preferences.dart';
import 'model.dart';

TagDisplay effectiveTagDisplay(
  Map<String, Tag> tags,
  String? id,
  Map<String, TagDisplay> overrides,
) {
  final seen = <String>{};
  while (id != null && seen.add(id)) {
    final display = overrides[id];
    if (display != null) return display;
    id = tags[id]?.parentId;
  }
  return TagDisplay.normal;
}

bool isUnfilledGap(Event event) =>
    event.isUndefined &&
    (event.title.trim().isEmpty || event.title.trim() == '未定义') &&
    event.notes.trim().isEmpty;

/// One filter shared by the timeline and table; accounting uses full records.
class JournalPresentation {
  const JournalPresentation({
    required this.tags,
    this.tagDisplays = const {},
    this.view = JournalViewPreferences.focused,
    this.autoUndefined = true,
    this.revealedIds = const {},
  });

  final Map<String, Tag> tags;
  final Map<String, TagDisplay> tagDisplays;
  final JournalViewPreferences view;
  final bool autoUndefined;
  final Set<String> revealedIds;

  bool isRoutine(Event event) =>
      effectiveTagDisplay(tags, event.tagId, tagDisplays) == TagDisplay.routine;

  bool includes(Event event) {
    if (event.isUndefined && !autoUndefined) return false;
    if (revealedIds.contains(event.id)) return true;
    if (event.tagId == null && !view.showUnclassified) return false;
    if (event.isUndefined) {
      return view.preset == JournalViewPreset.fullDay || !isUnfilledGap(event);
    }
    return view.preset == JournalViewPreset.fullDay || !isRoutine(event);
  }

  bool get foldsEmptyTime => view.foldsEmptyTime;
}
