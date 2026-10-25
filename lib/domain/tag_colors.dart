import 'appearance.dart';
import 'model.dart';

const defaultRootColors = {
  'work': TagColor.blue,
  'side': TagColor.purple,
  'explore': TagColor.teal,
  'life': TagColor.orange,
};

const suggestedTagColors = [
  TagColor.blue,
  TagColor.teal,
  TagColor.purple,
  TagColor.pink,
  TagColor.orange,
  TagColor.brown,
  TagColor.amber,
  TagColor.cyan,
];

/// Suggest only the new identity's colour; existing assignments never move.
TagColor suggestTagColor(
  Iterable<Tag> tags,
  Map<String, TagColor> assigned, {
  String? exceptId,
}) {
  final active = tags.map((tag) => tag.id).toSet()..remove(exceptId);
  final used = {
    for (final entry in assigned.entries)
      if (active.contains(entry.key)) entry.value,
    for (final tag in tags)
      if (tag.id != exceptId &&
          tag.parentId == null &&
          assigned[tag.id] == null)
        ?defaultRootColors[tag.id],
  };
  for (final color in suggestedTagColors) {
    if (!used.contains(color)) return color;
  }
  final counts = {
    for (final color in suggestedTagColors)
      color: assigned.entries
          .where((entry) => active.contains(entry.key) && entry.value == color)
          .length,
  };
  return suggestedTagColors.reduce((a, b) => counts[a]! <= counts[b]! ? a : b);
}

Map<String, TagColor> assignRootColors(
  Iterable<Tag> tags,
  Map<String, TagColor> assigned,
) {
  final all = tags.toList();
  final result = {...assigned};
  for (final tag in all) {
    final color = defaultRootColors[tag.id];
    if (tag.parentId == null && color != null) {
      result.putIfAbsent(tag.id, () => color);
    }
  }
  for (final tag in all) {
    if (tag.parentId == null && !result.containsKey(tag.id)) {
      result[tag.id] = suggestTagColor(all, result, exceptId: tag.id);
    }
  }
  return Map.unmodifiable(result);
}
