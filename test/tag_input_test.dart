import 'dart:io';

import 'package:daymark/data/store.dart';
import 'package:daymark/ui/tag_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Store store;
  late String chore;
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('tag-input-');
    store = await Store.open(directory, writer: (_, _) async {});
    chore = (await store.saveTag('chore', null)).id;
  });
  tearDown(() => directory.delete(recursive: true));

  test(
    'spaces separate exact tags and leave only the last term for search',
    () {
      final input = parseTagInput(store, '  主业  CHORE');
      expect(input.valid, isTrue);
      expect(input.prefix, ['work']);
      expect(input.query, 'CHORE');
      expect(input.tagIds, unorderedEquals(['work', chore]));
      final partial = parseTagInput(store, '主业 cho');
      expect(partial.valid, isFalse);
      expect(partial.prefix, ['work']);
      expect(partial.query, 'cho');
      expect(parseTagInput(store, '主业 chore ').query, '');
      expect(parseTagInput(store, '').tagIds, isEmpty);
    },
  );

  test(
    'paths, spaced names and Unicode folding retain the original IDs',
    () async {
      final repeated = await store.saveTag('重复', 'work');
      await store.saveTag('重复', 'life');
      final spaced = await store.saveTag('deep work', null);
      final folded = await store.saveTag('Straße', null);
      expect(parseTagInput(store, '重复').valid, isFalse);
      final text = tagInputText(store, [repeated.id, spaced.id, folded.id]);
      expect(text, '主业 / 重复 deep work Straße');
      final input = parseTagInput(
        store,
        text.replaceFirst('Straße', 'STRASSE'),
      );
      expect(input.valid, isTrue);
      expect(
        input.tagIds,
        unorderedEquals([repeated.id, spaced.id, folded.id]),
      );
    },
  );

  test('unknown intermediate terms cannot silently discard text', () {
    final input = parseTagInput(store, '主业 unknown chore');
    expect(input.valid, isFalse);
    expect(input.query, 'unknown chore');
    expect(input.tagIds, ['work']);
  });
}
