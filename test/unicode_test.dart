import 'package:daymark/domain/unicode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('case folding preserves legacy Unicode sibling identity', () {
    for (final pair in [
      ('Straße', 'STRASSE'),
      ('Σςσ', 'σσσ'),
      ('İ', 'i\u0307'),
      ('ﬃ', 'ffi'),
      ('Ꭰ', 'ꭰ'),
    ]) {
      expect(caseFold(pair.$1), caseFold(pair.$2));
    }
    expect(caseFold('中文😀'), '中文😀');
  });

  test(
    'string order compares code points including supplementary characters',
    () {
      expect(compareUnicode('\ue000', '😀'), lessThan(0));
      expect(compareUnicode('同', '同一'), lessThan(0));
      expect(compareUnicode('😀', '😀'), 0);
    },
  );

  test('Python repr handles quotes, controls and nonprintable Unicode', () {
    expect(pythonStringRepr("it's"), '"it\'s"');
    expect(pythonStringRepr('"\'\\\t\n\r'), "'\"\\'\\\\\\t\\n\\r'");
    expect(
      pythonStringRepr('\x00\b\x7f\u00a0\u200b\ue000\u{e0001}'),
      r"'\x00\x08\x7f\xa0\u200b\ue000\U000e0001'",
    );
    expect(pythonStringRepr('中文😀'), "'中文😀'");
  });
}
