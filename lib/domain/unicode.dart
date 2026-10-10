part 'unicode_data.dart';

(int, int, int, int)? _range(int rune, List<(int, int, int, int)> ranges) {
  var left = 0;
  var right = ranges.length - 1;
  while (left <= right) {
    final middle = (left + right) ~/ 2;
    final range = ranges[middle];
    if (rune < range.$1) {
      right = middle - 1;
    } else if (rune > range.$2) {
      left = middle + 1;
    } else {
      return (rune - range.$1) % range.$3 == 0 ? range : null;
    }
  }
  return null;
}

/// Preserve the original Unicode-aware sibling validation and tree order.
String caseFold(String value) => value.runes.map((rune) {
  final exception = _caseFoldSingles[rune];
  if (exception != null) return exception;
  final range = _range(rune, _caseFoldRanges);
  return String.fromCharCode(rune + (range?.$4 ?? 0));
}).join();

/// Python compares Unicode code points, whereas Dart compares UTF-16 units.
int compareUnicode(String left, String right) {
  final a = left.runes.iterator;
  final b = right.runes.iterator;
  while (true) {
    final hasA = a.moveNext();
    final hasB = b.moveNext();
    if (!hasA || !hasB) return (hasA ? 1 : 0) - (hasB ? 1 : 0);
    final result = a.current.compareTo(b.current);
    if (result != 0) return result;
  }
}

/// Exact Python string repr is part of the persisted UUIDv5 gap identity.
String pythonStringRepr(String value) {
  final quote = value.contains("'") && !value.contains('"') ? '"' : "'";
  final result = StringBuffer(quote);
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (char == quote || char == r'\') {
      result.write('\\$char');
    } else if (rune == 9 || rune == 10 || rune == 13) {
      result.write({9: r'\t', 10: r'\n', 13: r'\r'}[rune]);
    } else if (_range(rune, _nonPrintableRanges) != null) {
      final width = rune <= 0xff
          ? 2
          : rune <= 0xffff
          ? 4
          : 8;
      final prefix = width == 2
          ? r'\x'
          : width == 4
          ? r'\u'
          : r'\U';
      result.write('$prefix${rune.toRadixString(16).padLeft(width, '0')}');
    } else {
      result.write(char);
    }
  }
  return '$result$quote';
}
