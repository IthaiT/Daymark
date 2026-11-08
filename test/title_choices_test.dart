import 'dart:io';

import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/ui/pickers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Store store;
  final today = DateTime.utc(2026, 11, 8);
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('title-choices-');
    store = await Store.open(directory, clock: () => today);
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

  test('a tag never appears in the name-column suggestions', () async {
    await store.saveTag('跳槽', null);
    final choices = titleChoices(store, '跳槽');
    expect(choices.map((choice) => choice.owner.isItem).toSet(), {true});
  });

  test(
    'todo and recent done items match while paused and cancelled stay hidden',
    () async {
      await store.saveItem(
        const Item(id: 'paused', name: '暂停简历', status: ItemStatus.paused),
      );
      await store.saveItem(
        const Item(
          id: 'done',
          name: '完成简历',
          status: ItemStatus.done,
          outcome: '完成',
        ),
      );
      await store.saveItem(
        const Item(
          id: 'cancel',
          name: '取消简历',
          status: ItemStatus.dropped,
          outcome: '取消',
        ),
      );
      expect(titleChoices(store, '简').map((c) => c.owner.id).toSet(), {
        'resume',
        'done',
      });
      expect(titleChoices(store, '完成').single.completed, true);
      expect(store.itemIdForTitle('暂停简历'), isNull);
    },
  );

  test('an empty query offers nothing', () {
    expect(titleChoices(store, '  '), isEmpty);
  });

  test('the subtitle names the parent path', () {
    final choice = titleChoices(store, '改简历').single;
    expect(choice.subtitle, '跳槽');
    expect(choice.owner, (id: 'resume', isItem: true));
  });

  test(
    'matching parents expose each descendant once in tree order and relative depth',
    () async {
      await store.saveItem(const Item(id: 'feat', name: 'feat'));
      await store.saveItem(
        const Item(id: 'feature', name: '实现记录事项化的功能', parentId: 'feat'),
      );
      await store.saveItem(
        const Item(
          id: 'parse',
          name: '独立软件侧解析 obsidian markdown 内容',
          parentId: 'feature',
        ),
      );
      final choices = titleChoices(store, 'FEAT');
      expect(choices.map((c) => c.owner.id), ['feat', 'feature', 'parse']);
      expect(choices.map((c) => c.depth), [0, 1, 2]);
      expect(choices.last.subtitle, 'feat / 实现记录事项化的功能');
      expect(titleChoices(store, 'feat / 实现').map((c) => c.owner.id), [
        'feature',
        'parse',
      ]);
      expect(titleChoices(store, 'feat / 实现').map((c) => c.depth), [0, 1]);
    },
  );

  test(
    'expired, paused and cancelled parents still provide paths for eligible children',
    () async {
      for (final status in [
        ItemStatus.done,
        ItemStatus.paused,
        ItemStatus.dropped,
      ]) {
        final id = status.name;
        await store.saveItem(
          Item(
            id: id,
            name: '旧项目$id',
            status: status,
            completedOn: today.subtract(const Duration(days: 7)),
            source: const ItemSource(
              directory: 'vault',
              path: 'A.md',
              kind: 'task',
              order: 0,
              raw: '',
            ),
          ),
        );
        await store.saveItem(Item(id: '$id-child', name: '仍可记录', parentId: id));
        expect(titleChoices(store, '旧项目$id').map((c) => c.owner.id), [
          '$id-child',
        ]);
        expect(titleChoices(store, '旧项目$id').single.depth, 1);
      }
    },
  );

  test(
    'long subtrees are not cut off at eight candidates and have stable identities',
    () async {
      for (var index = 0; index < 20; index++) {
        await store.saveItem(
          Item(
            id: 'child-$index',
            name: '子事项${index.toString().padLeft(2, '0')}',
            parentId: 'job',
          ),
        );
      }
      final choices = titleChoices(store, '跳槽');
      expect(choices.length, 22);
      expect(choices.map((c) => c.owner.id).toSet().length, choices.length);
      expect(titleChoices(store, '跳槽', limit: 3).length, 3);
    },
  );
}
