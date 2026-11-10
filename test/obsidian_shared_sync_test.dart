import 'dart:io';

import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/obsidian_sync.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/obsidian.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/obsidian_ids.dart';

void main() {
  late Directory directory;
  late Directory vault;
  late Store store;
  var failItems = false;
  var now = DateTime.utc(2026, 11, 10, 18);
  const sync = ObsidianSync();
  final shared = obsidianId(2);
  final inline = '- [ ] 共享 #研发 $shared\n  - [ ] 内联子事项 ${obsidianId(3)}\n';
  String project(String body) =>
      '---\ndaymark-id: "${obsidianId(1)}"\ntags: [主业]\n---\n$body';
  String sharedNote(String body) =>
      '---\ndaymark-id: "$shared"\nparent: "[[项目]]"\ntags: [研发]\n---\n$body';
  File file(String name) => File('${vault.path}/$name.md');
  Event record(String id, String itemId, int hour) => Event(
    id,
    '原始标题',
    ['work'],
    DateTime.utc(2026, 11, 10, hour),
    DateTime.utc(2026, 11, 10, hour + 1),
    '原始备注',
    itemId,
  );

  setUp(() async {
    failItems = false;
    now = DateTime.utc(2026, 11, 10, 18);
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('shared-obsidian-');
    vault = await Directory('${directory.path}/vault').create();
    store = await Store.open(
      Directory('${directory.path}/journal'),
      clock: () => now,
      backupTrees: true,
      writer: (destination, bytes) async {
        if (failItems && destination.path.endsWith('items.json')) {
          throw const FileSystemException('模拟写入失败');
        }
        await AtomicFile.write(destination, bytes);
      },
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> importShared() async {
    await file('项目').writeAsString(project(inline));
    await file(
      '共享',
    ).writeAsString(sharedNote('- [ ] 文件子事项 ${obsidianId(4)}\n'));
    await sync.synchronize(store, vault);
  }

  test(
    'shared nodes persist once, inherit tags and never double-count saved time',
    () async {
      await importShared();
      final records = [
        record('parent', shared, 9),
        record('inline', obsidianId(3), 10),
        record('note', obsidianId(4), 11),
      ];
      for (final event in records) {
        await store.saveEvent(event);
      }
      final reopened = await Store.open(store.directory);
      expect(reopened.items.length, 4);
      expect(
        reopened.items.values.where((item) => item.name == '共享').length,
        1,
      );
      for (final id in [shared, obsidianId(3), obsidianId(4)]) {
        expect(reopened.effectiveItemTagIds(id).map(reopened.tagName).toSet(), {
          '主业',
          '研发',
        });
      }
      for (final split in [false, true]) {
        final totals = itemDurations(
          reopened.items,
          reopened.events.values,
          splitOverlap: split,
        );
        expect(totals[shared], const Duration(hours: 3));
        expect(totals[obsidianId(1)], const Duration(hours: 3));
      }
      for (final event in records) {
        expect(reopened.events[event.id], event);
      }
    },
  );

  test(
    'removing one occurrence keeps the identity; removing all retains referenced nodes only',
    () async {
      await importShared();
      final records = [
        record('parent', shared, 9),
        record('inline', obsidianId(3), 10),
        record('note', obsidianId(4), 11),
      ];
      for (final event in records) {
        await store.saveEvent(event);
      }
      await file('项目').writeAsString(project(''));
      await sync.synchronize(store, vault);
      expect(store.items[shared]!.source!.missing, false);
      expect(store.items[obsidianId(3)]!.source!.missing, true);
      expect(store.items[obsidianId(4)]!.source!.missing, false);
      expect(store.deletedObsidianReferences, {obsidianId(3): 1});

      await file('共享').delete();
      await sync.synchronize(store, vault);
      expect(store.deletedObsidianReferences, {
        shared: 1,
        obsidianId(3): 1,
        obsidianId(4): 1,
      });
      for (final event in records) {
        expect(store.events[event.id], event);
      }

      await file(
        '项目',
      ).writeAsString(project('$inline  - [ ] 文件子事项 ${obsidianId(4)}\n'));
      await sync.synchronize(store, vault);
      expect(store.deletedObsidianReferences, isEmpty);
      expect(store.items[shared]!.source!.kind, 'task');
      for (final child in [3, 4]) {
        expect(store.items[obsidianId(child)]!.parentId, shared);
        expect(store.items[obsidianId(child)]!.source!.missing, false);
      }
      for (final event in records) {
        expect(store.events[event.id], event);
      }
    },
  );

  test(
    'losing the preferred note location falls back to a surviving inline occurrence',
    () async {
      await importShared();
      final event = record('parent', shared, 9);
      await store.saveEvent(event);
      await file('共享').delete();
      await sync.synchronize(store, vault);
      expect(store.items[shared]!.source!.kind, 'task');
      expect(store.items[shared]!.source!.path, '项目.md');
      expect(store.items[shared]!.source!.missing, false);
      expect(store.items.containsKey(obsidianId(4)), false);
      expect(store.items[obsidianId(3)]!.parentId, shared);
      expect(store.events[event.id], event);
      expect((await Store.open(store.directory)).items, store.items);
    },
  );

  test(
    'a conflicting occurrence aborts before any annotation, tag or saved record changes',
    () async {
      await importShared();
      final event = record('parent', shared, 9);
      await store.saveEvent(event);
      final priorItems = store.items;
      final itemBytes = await store.itemsFile.readAsBytes();
      final eventBytes = await store.eventsFile.readAsBytes();
      final tagBytes = await store.tagsFile.readAsBytes();
      final changed = project(inline.replaceFirst('共享 #研发', '共享 | 不同描述 #研发'));
      await file('项目').writeAsString(changed);
      await file('新增').writeAsString('- [ ] 未写入身份 #新标签\n');
      final note = await file('共享').readAsString();
      await expectLater(
        sync.synchronize(store, vault),
        throwsA(
          isA<ObsidianDuplicateIdException>().having(
            (error) => error.message,
            'field',
            contains('差异：描述'),
          ),
        ),
      );
      expect(await file('项目').readAsString(), changed);
      expect(await file('共享').readAsString(), note);
      expect(await file('新增').readAsString(), '- [ ] 未写入身份 #新标签\n');
      expect(await store.itemsFile.readAsBytes(), itemBytes);
      expect(await store.eventsFile.readAsBytes(), eventBytes);
      expect(await store.tagsFile.readAsBytes(), tagBytes);
      expect(store.items, priorItems);
      expect(store.events[event.id], event);
    },
  );

  test(
    'completion is observed once for a merged ID and does not refresh after source changes',
    () async {
      final row = '- [ ] 完成事项 $shared\n';
      await file('项目').writeAsString(project('$row$row'));
      await sync.synchronize(store, vault);
      await file(
        '项目',
      ).writeAsString(project('$row$row'.replaceAll('[ ]', '[x]')));
      await sync.synchronize(store, vault);
      expect(store.items[shared]!.completedOn, DateTime.utc(2026, 11, 10));
      now = DateTime.utc(2026, 11, 11, 18);
      await file('项目').writeAsString(project(row.replaceFirst('[ ]', '[x]')));
      await sync.synchronize(store, vault);
      expect(store.items[shared]!.completedOn, DateTime.utc(2026, 11, 10));
      expect(store.items.length, 2);
    },
  );

  test(
    'a failed merged write retains history and retries with the same generated child identity',
    () async {
      await file('项目').writeAsString(project(inline));
      await sync.synchronize(store, vault);
      final event = record('parent', shared, 9);
      await store.saveEvent(event);
      final before = store.items;
      await file(
        '项目',
      ).writeAsString(project('$inline- [ ] 共享 #研发 $shared\n  - [ ] 新子事项\n'));
      failItems = true;
      await expectLater(
        sync.synchronize(store, vault),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.items, before);
      expect(store.events[event.id], event);
      final annotated = await file('项目').readAsString();
      expect(
        annotated,
        contains(RegExp(r'新子事项 \^daymark-obsidian-[0-9a-f-]+')),
      );
      failItems = false;
      await sync.synchronize(store, vault);
      expect(await file('项目').readAsString(), annotated);
      expect(store.items.length, 4);
      expect(
        store.items.values.singleWhere((item) => item.name == '新子事项').parentId,
        shared,
      );
      expect(store.events[event.id], event);
    },
  );
}
