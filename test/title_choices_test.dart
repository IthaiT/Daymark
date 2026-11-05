import 'dart:io';

import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/ui/pickers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Store store;
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('title-choices-');
    store = await Store.open(directory);
    await store.saveItem(const Item(id: 'job', name: '跳槽'));
    await store.saveItem(
      const Item(id: 'resume', name: '改简历', parentId: 'job'),
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('exact matches rank before prefixes and substrings', () async {
    await store.saveItem(const Item(id: 'cv', name: '简历'));
    final titles = titleChoices(store, '简历').map((c) => c.title).toList();
    expect(titles.first, '简历');
    expect(titles, contains('改简历'));
  });

  test('a tag and an item with the same name are both offered', () async {
    await store.saveTag('跳槽', null);
    final choices = titleChoices(store, '跳槽');
    expect(choices.map((choice) => choice.owner.isItem).toSet(), {true, false});
  });

  test('an empty query offers nothing', () {
    expect(titleChoices(store, '  '), isEmpty);
  });

  test('the subtitle names the parent path', () {
    final choice = titleChoices(store, '改简历').single;
    expect(choice.subtitle, '跳槽');
    expect(choice.owner, (id: 'resume', isItem: true));
  });
}
