import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/archive_store.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/event_stats.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Store store;
  late JournalController journal;
  var failItemWrites = false;
  final day = DateTime.utc(2026, 11, 4);

  Event record(
    String id,
    String title, {
    String? itemId,
    List<String> tags = const [],
    DateTime? start,
    DateTime? end,
  }) => Event(
    id,
    title,
    tags,
    start ?? day.add(const Duration(hours: 9)),
    end ?? day.add(const Duration(hours: 10)),
    '',
    itemId,
  );

  setUp(() async {
    failItemWrites = false;
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('project-items-');
    store = await Store.open(
      directory,
      writer: (file, bytes) async {
        if (failItemWrites && file.path.endsWith('items.json')) {
          throw const FileSystemException('items write denied');
        }
        await AtomicFile.write(file, bytes);
      },
    );
    journal = JournalController(store, day: day, clock: () => day);
  });

  tearDown(() async {
    journal.dispose();
    await directory.delete(recursive: true);
  });

  test('a record keeps its project and every tag through the CSV', () async {
    await store.saveItem(const Item(id: 'job', name: '跳槽'));
    final event = record('e', '调研', itemId: 'job', tags: ['work', 'life']);
    await store.saveEvent(event);

    final reopened = await Store.open(directory);
    expect(reopened.events['e']!.itemId, 'job');
    expect(reopened.events['e']!.tagIds, ['work', 'life']);
    expect(reopened.ownerName(reopened.events['e']!), '跳槽 · 主业 · 生活');
  });

  test('a child inherits tags and may drop one explicitly', () {
    final items = {
      'job': const Item(id: 'job', name: '跳槽', tagIds: ['work']),
      'resume': const Item(
        id: 'resume',
        name: '改简历',
        parentId: 'job',
        tagIds: ['life'],
      ),
      'interview': const Item(
        id: 'interview',
        name: '面试',
        parentId: 'job',
        excludedTagIds: ['work'],
      ),
    };
    expect(itemEffectiveTagIds(items, 'resume'), ['work', 'life']);
    expect(itemEffectiveTagIds(items, 'interview'), isEmpty);
  });

  test('overlapping records count once on the project page', () {
    final items = {
      'job': const Item(id: 'job', name: '跳槽'),
      'a': const Item(id: 'a', name: '研究', parentId: 'job'),
      'b': const Item(id: 'b', name: '整理', parentId: 'job'),
    };
    final events = [
      record(
        'a',
        '研究',
        itemId: 'a',
        start: day.add(const Duration(hours: 9)),
        end: day.add(const Duration(hours: 11)),
      ),
      record(
        'b',
        '整理',
        itemId: 'b',
        start: day.add(const Duration(hours: 10)),
        end: day.add(const Duration(hours: 12)),
      ),
    ];
    expect(itemDurations(items, events)['job'], const Duration(hours: 3));
    expect(
      itemDurations(items, events, splitOverlap: true)['job'],
      durationIn(StatsWindow.days(day, day), events),
    );
  });

  test('choosing an item adds its tags without dropping manual ones', () async {
    await store.saveTag('求职', null).then((tag) {
      return store.saveItem(Item(id: 'job', name: '跳槽', tagIds: [tag.id]));
    });
    await store.saveEvent(record('e', '调研', tags: ['work']));

    await journal.setEventItem(['e'], 'job');

    expect(store.events['e']!.itemId, 'job');
    expect(store.events['e']!.tagIds, contains('work'));
    expect(store.events['e']!.tagIds.length, 2);
  });

  test('item-only records retain their last classification', () async {
    await store.saveItem(const Item(id: 'resume', name: '改简历'));
    await store.saveEvent(record('e', '改简历', itemId: 'resume'));
    await expectLater(
      journal.editCell('e', EventColumn.tag, null),
      throwsFormatException,
    );
    expect(store.events['e']!.itemId, 'resume');
  });

  test(
    'deleting the only classification requires reclassifying its records',
    () async {
      await store.saveItem(const Item(id: 'p', name: '计划'));
      await store.saveEvent(record('e', '学习', itemId: 'p'));
      await expectLater(journal.deleteItem('p'), throwsFormatException);
      expect(store.items.containsKey('p'), isTrue);
      expect(store.events['e']!.itemId, 'p');
      await journal.setEventTags(['e'], ['work']);
      await journal.deleteItem('p');
      expect(store.events['e']!.tagIds, ['work']);
      expect(store.events['e']!.itemId, isNull);
    },
  );

  test('undo after deleting a project no longer fails', () async {
    await store.saveItem(const Item(id: 'job', name: '跳槽'));
    await store.saveEvent(record('e', '第一版简历', itemId: 'job', tags: ['work']));
    await journal.editCell('e', EventColumn.title, '第二版简历');
    await journal.deleteItem('job');

    expect(await journal.undo(), isTrue);
    expect(store.events['e']!.title, '第一版简历');
    expect(store.events['e']!.itemId, isNull);
    // The same snapshot can be undone again without a stale reference.
    expect(await journal.redo(), isTrue);
    expect(await journal.undo(), isTrue);
  });

  test(
    'deleting an item restores the records when the tree write fails',
    () async {
      await store.saveItem(const Item(id: 'job', name: '跳槽'));
      await store.saveItem(
        const Item(id: 'resume', name: '改简历', parentId: 'job'),
      );
      await store.saveEvent(record('e', '修改项目经历', itemId: 'resume'));

      failItemWrites = true;
      await expectLater(
        journal.deleteItem('resume'),
        throwsA(isA<FileSystemException>()),
      );
      failItemWrites = false;

      expect(store.events['e']!.itemId, 'resume');
      final reopened = await Store.open(directory);
      expect(reopened.events['e']!.itemId, 'resume');
      expect(reopened.items.containsKey('resume'), isTrue);
    },
  );

  test('an archive keeps the project tree and the record owner', () async {
    await store.saveItem(const Item(id: 'job', name: '跳槽', tagIds: ['work']));
    await store.saveEvent(
      Event(
        'e',
        '研究',
        ['life'],
        DateTime.utc(2026, 11, 1),
        DateTime.utc(2026, 11, 3),
        '',
        'job',
      ),
    );
    final archive = await ArchiveStore.open(directory);
    await archive.capture(store, day);

    final reopened = await ArchiveStore.open(directory);
    expect(reopened.items['job']!.tagIds, ['work']);
    expect(reopened.events['e']!.itemId, 'job');
    expect(reopened.events['e']!.tagIds, ['life']);
  });

  test(
    'batch moves replace tags and inherit the destination item tags',
    () async {
      await store.saveItem(const Item(id: 'job', name: '跳槽', tagIds: ['work']));
      await store.saveEvent(record('e', '研究', tags: ['life']));

      await journal.moveEventsTo(['e'], (id: 'work', isItem: false));
      expect(store.events['e']!.tagIds, ['work']);
      expect(store.events['e']!.itemId, isNull);

      await journal.setEventTags(['e'], ['life']);
      await journal.moveEventsTo(['e'], (id: 'job', isItem: true));
      expect(store.events['e']!.itemId, 'job');
      expect(store.events['e']!.tagIds, ['work']);
    },
  );

  test('a status change is kept in the item trail', () async {
    await journal.saveItem(const Item(id: 'job', name: '跳槽'));
    await journal.saveItem(
      const Item(
        id: 'job',
        name: '跳槽',
        status: ItemStatus.dropped,
        outcome: '方向不合适',
      ),
    );
    final saved = store.items['job']!;
    expect(saved.log.length, 2);
    expect(saved.log.first.kind, 'created');
    expect(saved.log.last.kind, 'status');
    expect(saved.log.last.text, '待办 → 已取消：方向不合适');
  });
}
