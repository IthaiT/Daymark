import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/archive_store.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Store store;
  late JournalController journal;
  var failWrites = false;
  final day = DateTime.utc(2026, 10, 7);
  Event event(String id, {DateTime? end}) => Event(
    id,
    '历史事件',
    ['linux', 'life'],
    day.add(const Duration(hours: 23, seconds: 17)),
    end,
    '原备注',
  );

  setUp(() async {
    failWrites = false;
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('organizer-');
    store = await Store.open(
      directory,
      writer: (file, bytes) async {
        if (failWrites) throw const FileSystemException('模拟写入失败');
        await AtomicFile.write(file, bytes);
      },
    );
    await store.saveItem(
      const Item(id: 'parent', name: '父事项', tagIds: ['work', 'life']),
    );
    await store.saveItem(
      Item(
        id: 'target',
        name: '已完成事项',
        parentId: 'parent',
        status: ItemStatus.done,
        endedOn: day,
        excludedTagIds: const ['life'],
      ),
    );
    await store.replaceEvents({
      'cross': event(
        'cross',
        end: day.add(const Duration(days: 1, hours: 1, seconds: 39)),
      ),
      'incomplete': event('incomplete'),
    });
    journal = JournalController(
      store,
      day: day,
      clock: () => day.add(const Duration(days: 3)),
    );
  });

  tearDown(() async {
    journal.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'archived cross-midnight and incomplete records move losslessly with undo',
    () async {
      final archive = await ArchiveStore.open(directory);
      await archive.capture(store, day.add(const Duration(days: 3)));
      journal.dispose();
      journal = JournalController(store, archive: archive, day: day);
      final before = {...store.events};
      await journal.moveEventsTo(
        ['cross', 'incomplete', 'cross'],
        (id: 'target', isItem: true),
      );
      for (final id in before.keys) {
        expect(
          store.events[id],
          before[id]!.copyWith(itemId: 'target', tagIds: ['work']),
        );
      }
      expect(
        (await Store.open(directory)).events['cross'],
        store.events['cross'],
      );
      await journal.undo();
      for (final id in before.keys) {
        expect(store.events[id], before[id]);
      }
      await journal.redo();
      expect(store.events['cross']!.itemId, 'target');
      await journal.moveEventsTo(['cross'], (id: 'life', isItem: false));
      expect(store.events['cross']!.tagIds, ['life']);
      expect(store.events['cross']!.itemId, 'target');
    },
  );

  test('failed batch writes preserve disk, memory and undo history', () async {
    final before = {...store.events};
    final bytes = await store.eventsFile.readAsBytes();
    failWrites = true;
    await expectLater(
      journal.moveEventsTo(before.keys, (id: 'target', isItem: true)),
      throwsA(isA<FileSystemException>()),
    );
    expect(store.events, before);
    expect(await store.eventsFile.readAsBytes(), bytes);
    expect(journal.history.canUndo, isFalse);
    failWrites = false;
    await journal.moveEventsTo(before.keys, (id: 'target', isItem: true));
    expect(store.events['cross']!.itemId, 'target');
  });

  test(
    'cleanup protects events, item exclusions, drafts and their ancestors',
    () async {
      final empty = await journal.saveTag('空分支', null);
      final leaf = await journal.saveTag('空叶子', empty.id);
      final draftTag = await journal.saveTag('草稿使用', null);
      final draft = await journal.addDraft();
      await journal.editCell(draft, EventColumn.tag, (
        id: draftTag.id,
        isItem: false,
      ));
      expect(journal.unusedTagIds, containsAll([empty.id, leaf.id]));
      expect(journal.unusedTagIds, isNot(contains('work')));
      expect(journal.unusedTagIds, isNot(contains('life')));
      expect(journal.unusedTagIds, isNot(contains(draftTag.id)));
      failWrites = true;
      await expectLater(
        journal.deleteUnusedTags({empty.id, leaf.id}),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.tags, contains(leaf.id));
      failWrites = false;
      await journal.deleteUnusedTags({empty.id, leaf.id});
      expect(store.tags, isNot(contains(empty.id)));
      expect((await Store.open(directory)).tags, isNot(contains(leaf.id)));
      await expectLater(
        journal.deleteUnusedTags({'life'}),
        throwsFormatException,
      );
    },
  );
}
