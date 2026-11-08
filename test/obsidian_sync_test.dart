import 'dart:convert';
import 'dart:io';

import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/obsidian_sync.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Directory vault;
  late Store store;
  var failItems = false;
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('obsidian-sync-');
    vault = await Directory('${directory.path}/vault').create();
    store = await Store.open(
      Directory('${directory.path}/data'),
      backupTrees: true,
      writer: (file, bytes) async {
        if (failItems && file.path.endsWith('items.json')) {
          throw const FileSystemException('denied');
        }
        await AtomicFile.write(file, bytes);
      },
    );
    failItems = false;
  });
  tearDown(() async {
    failItems = false;
    await directory.delete(recursive: true);
  });
  test(
    'renames, moves and removals preserve record IDs and all tags',
    () async {
      final a = File('${vault.path}/A.md');
      final b = File('${vault.path}/B.md');
      await a.writeAsString('---\ntags: [主业, 新标签]\n---\n- [ ] 任务 | 描述\n');
      await b.writeAsString('---\nparent: "[[A]]"\ntags: [副业]\n---\n');
      const sync = ObsidianSync();
      await sync.synchronize(store, vault);
      final task = store.items.values.singleWhere((n) => n.name == '任务');
      final aId = store.items.values.singleWhere((n) => n.name == 'A').id;
      expect(store.effectiveItemTagIds(task.id).map(store.tagName), [
        '主业',
        '新标签',
      ]);
      final event = Event(
        'e',
        '旧名称',
        ['work', 'side'],
        DateTime.utc(2026, 11, 8, 9),
        DateTime.utc(2026, 11, 8, 10),
        '备注',
        task.id,
      );
      await store.saveEvent(event);
      final original = await a.readAsString();
      final line = original.split('\n').singleWhere((l) => l.startsWith('- ['));
      await a.writeAsString(original.replaceAll('$line\n', ''));
      await b.writeAsString(
        '${await b.readAsString()}${line.replaceFirst('任务', '新名称')}\n',
      );
      await a.rename('${vault.path}/重命名.md');
      await b.writeAsString(
        (await b.readAsString()).replaceAll('[[A]]', '[[重命名]]'),
      );
      await sync.synchronize(store, vault);
      expect(store.items[aId]!.name, '重命名');
      expect(store.items[task.id]!.name, '新名称');
      expect(store.effectiveItemTagIds(task.id).map(store.tagName), [
        '主业',
        '新标签',
        '副业',
      ]);
      expect(store.events['e'], event);
      await b.delete();
      await sync.synchronize(store, vault);
      expect(store.items[task.id]!.source!.missing, true);
      expect(store.items[task.id]!.isTodo, false);
      final reopened = await Store.open(store.directory);
      expect(reopened.items[task.id]!.name, '新名称');
      expect(reopened.events['e'], event);
      final snapshot =
          jsonDecode(
                await File(
                  '${store.directory.path}/tree-backups/latest.json',
                ).readAsString(),
              )
              as Map;
      expect(
        ((snapshot['events'] as List<Object?>).single!
            as Map<String, Object?>)['item_id'],
        task.id,
      );
      expect((snapshot['items'] as List).length, store.items.length);
    },
  );
  test(
    'duplicate IDs fail before any source is annotated or data replaced',
    () async {
      final a = File('${vault.path}/A.md');
      final source =
          '- [ ] one <!-- daymark:same -->\n- [ ] two <!-- daymark:same -->';
      await a.writeAsString(source);
      await expectLater(
        const ObsidianSync().synchronize(store, vault),
        throwsFormatException,
      );
      expect(await a.readAsString(), source);
      expect(store.items, isEmpty);
    },
  );
  test(
    'failed tree write can retry IDs without changing prior records or tags',
    () async {
      final a = File('${vault.path}/A.md');
      await a.writeAsString('---\ntags: [新标签]\n---\n- [ ] 任务');
      final previousTags = store.tags;
      failItems = true;
      await expectLater(
        const ObsidianSync().synchronize(store, vault),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.items, isEmpty);
      expect(store.tags, previousTags);
      final annotated = await a.readAsString();
      expect(annotated, contains('^daymark-obsidian-'));
      failItems = false;
      await const ObsidianSync().synchronize(store, vault);
      expect(await a.readAsString(), annotated);
      expect(store.items.length, 2);
      expect((await Store.open(store.directory)).items, store.items);
    },
  );
  test(
    'a source write failure leaves the complete stored tree untouched',
    () async {
      final a = File('${vault.path}/A.md');
      await a.writeAsString('- [ ] 任务');
      final sync = ObsidianSync(
        writer: (_, bytes) async => throw const FileSystemException('denied'),
      );
      await expectLater(
        sync.synchronize(store, vault),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.items, isEmpty);
      expect(await a.readAsString(), '- [ ] 任务');
      expect(
        await Directory(
          '${store.directory.path}/obsidian-originals',
        ).list().length,
        1,
      );
    },
  );
  test(
    'task tags combine with file and parent task tags without rewriting history',
    () async {
      final file = File('${vault.path}/A.md');
      await file.writeAsString(
        '---\ntags: [主业]\n---\n- [ ] 父事项 #研发\n  - [ ] 子事项 | 描述 #客户 | 结果 #自有\n',
      );
      await const ObsidianSync().synchronize(store, vault);
      final task = store.items.values.singleWhere((n) => n.name == '子事项');
      expect(store.effectiveItemTagIds(task.id).map(store.tagName).toSet(), {
        '主业',
        '研发',
        '客户',
        '自有',
      });
      expect(task.tagIds.map(store.tagName).toSet(), {'客户', '自有'});
      expect(task.objective, '描述');
    },
  );
  test('existing block aliases survive reload and a cross-file cut', () async {
    final a = File('${vault.path}/A.md');
    final b = File('${vault.path}/B.md');
    await a.writeAsString(
      '<!-- daymark-file:file-a -->\n- [ ] 旧事项 ^custom-link <!-- daymark:historical-id -->\n',
    );
    await b.writeAsString('');
    const sync = ObsidianSync();
    await sync.synchronize(store, vault);
    final old = store.items['historical-id']!;
    expect(await a.readAsString(), isNot(contains('<!-- daymark')));
    final content = await a.readAsString();
    final line = content.split('\n').singleWhere((s) => s.startsWith('- ['));
    await a.writeAsString(content.replaceFirst('$line\n', ''));
    await b.writeAsString(
      '${await b.readAsString()}\n${line.replaceFirst('旧事项', '新事项')}\n',
    );
    final reopened = await Store.open(store.directory, backupTrees: true);
    await sync.synchronize(reopened, vault);
    expect(reopened.items[old.id]!.name, '新事项');
    expect(reopened.items[old.id]!.source!.path, 'B.md');
    expect(reopened.items[old.id]!.source!.missing, false);
  });

  test(
    'note ID migration preserves project and task records after restart and rename',
    () async {
      final path = await vault.resolveSymbolicLinks();
      final file = File('$path/A.md');
      const original =
          '---\ntags: [主业]\n---\n- [ ] 任务 ^daymark-task-a\n\n^daymark-file-file-a\n';
      await file.writeAsString(original);
      await store.saveItem(
        Item(
          id: 'file-a',
          name: 'A',
          tagIds: ['work'],
          source: ItemSource(
            directory: path,
            path: 'A.md',
            kind: 'file',
            order: 0,
            raw: original,
          ),
        ),
      );
      await store.saveItem(
        Item(
          id: 'task-a',
          name: '任务',
          parentId: 'file-a',
          source: ItemSource(
            directory: path,
            path: 'A.md',
            kind: 'task',
            order: 0,
            raw: '- [ ] 任务 ^daymark-task-a',
          ),
        ),
      );
      final projectRecord = Event(
        'project-record',
        '原笔记记录',
        'work',
        DateTime.utc(2026, 11, 8, 8),
        DateTime.utc(2026, 11, 8, 9),
        '保留备注',
        'file-a',
      );
      final taskRecord = Event(
        'task-record',
        '原任务记录',
        'side',
        DateTime.utc(2026, 11, 8, 9),
        DateTime.utc(2026, 11, 8, 10),
        '',
        'task-a',
      );
      await store.saveEvent(projectRecord);
      await store.saveEvent(taskRecord);
      const sync = ObsidianSync();
      await sync.synchronize(store, vault);
      final migrated = await file.readAsString();
      expect(migrated, contains('daymark-id: "file-a"'));
      expect(migrated, isNot(contains('^daymark-file-')));
      expect(migrated, contains('- [ ] 任务 ^daymark-task-a'));
      final originals = await Directory(
        '${store.directory.path}/obsidian-originals',
      ).list().toList();
      final backup =
          jsonDecode(await (originals.single as File).readAsString()) as Map;
      expect((backup['documents'] as Map)['A.md'], original);
      await file.rename('$path/重命名.md');
      final reopened = await Store.open(store.directory, backupTrees: true);
      await sync.synchronize(reopened, vault);
      expect(reopened.items['file-a']!.name, '重命名');
      expect(reopened.items['file-a']!.source!.path, '重命名.md');
      expect(reopened.items['file-a']!.source!.missing, false);
      expect(reopened.items['task-a']!.parentId, 'file-a');
      expect(reopened.events['project-record'], projectRecord);
      expect(reopened.events['task-record'], taskRecord);
      expect(await File('$path/重命名.md').readAsString(), migrated);
      final snapshot =
          jsonDecode(
                await File(
                  '${store.directory.path}/tree-backups/latest.json',
                ).readAsString(),
              )
              as Map;
      final snapshotEvents = snapshot['events'] as List;
      expect(snapshotEvents.map((e) => (e as Map)['item_id']).toSet(), {
        'file-a',
        'task-a',
      });
    },
  );

  test(
    'conflicting note properties fail before any file or stored data changes',
    () async {
      final a = File('${vault.path}/A.md');
      final b = File('${vault.path}/B.md');
      await a.writeAsString('- [ ] 已有任务');
      const sync = ObsidianSync();
      await sync.synchronize(store, vault);
      final oldItems = store.items;
      final oldTags = store.tags;
      final originalA = await a.readAsString();
      const conflict =
          '---\ndaymark-id: property-id\n---\n- [ ] 不应写入\n^daymark-file-other-id\n';
      await b.writeAsString(conflict);
      await expectLater(sync.synchronize(store, vault), throwsFormatException);
      expect(await a.readAsString(), originalA);
      expect(await b.readAsString(), conflict);
      expect(store.items, oldItems);
      expect(store.tags, oldTags);
      expect((await Store.open(store.directory)).items, oldItems);
    },
  );
}
