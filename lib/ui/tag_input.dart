import '../data/store.dart';
import '../domain/model.dart';
import '../domain/unicode.dart';

/// Complete tags before the last search term, plus the exact value if valid.
class TagInput {
  const TagInput(this.prefix, this.query, this.tagIds, this.valid);
  final List<String> prefix;
  final String query;
  final List<String> tagIds;
  final bool valid;
}

String _words(String text) => text.trim().split(RegExp(r'\s+')).join(' ');

/// Use paths for repeated names so reopening the editor retains stable IDs.
String tagInputText(Store store, List<String> ids) => ids
    .map((id) {
      final name = store.tagName(id);
      final repeated = store.tags.values.where(
        (tag) => caseFold(_words(tag.name)) == caseFold(_words(name)),
      );
      return repeated.length > 1
          ? store.ancestors(id).map((tag) => tag.name).join(' / ')
          : name;
    })
    .join(' ');

/// Read a whitespace-separated list. Longest exact names/paths win, allowing
/// existing names with spaces and full paths to remain editable.
TagInput parseTagInput(Store store, String text) {
  final remainingWords = _words(text);
  if (remainingWords.isEmpty) return const TagInput([], '', [], true);
  var remaining = remainingWords;
  final prefix = <String>[];
  final labels = <(String, String)>[
    for (final tag in store.tags.values) ...[
      (caseFold(_words(tag.name)), tag.id),
      (
        caseFold(
          _words(store.ancestors(tag.id).map((t) => t.name).join(' / ')),
        ),
        tag.id,
      ),
    ],
  ];
  while (remaining.isNotEmpty) {
    // Match word boundaries before case folding: Unicode folding can change
    // string length, so its offsets must never index the original input.
    final words = remaining.split(' ');
    String? matchedId;
    var matchedLength = 0;
    for (var count = words.length; count > 0; count--) {
      final part = words.take(count).join(' ');
      final needle = caseFold(part);
      final matches = {
        for (final (label, id) in labels)
          if (label == needle) id,
      };
      if (matches.isEmpty) continue;
      if (matches.length == 1) {
        matchedId = matches.single;
        matchedLength = part.length;
      }
      break;
    }
    if (matchedId == null) {
      return TagInput(prefix, remaining, normalizeTagIds(prefix), false);
    }
    final ids = normalizeTagIds([...prefix, matchedId]);
    if (matchedLength == remaining.length) {
      return RegExp(r'\s$').hasMatch(text)
          ? TagInput(ids, '', ids, true)
          : TagInput(prefix, remaining, ids, true);
    }
    prefix.add(matchedId);
    remaining = remaining.substring(matchedLength).trimLeft();
  }
  return TagInput(prefix, '', normalizeTagIds(prefix), true);
}
