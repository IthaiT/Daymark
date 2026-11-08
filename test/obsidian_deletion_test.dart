import 'dart:convert';
import 'dart:io';

import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/obsidian_sync.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Directory vault;
  late Store store;
  var failItems = false;
  const sync = ObsidianSync();

  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('obsidian-deletion-');
    vault = await Directory('${directory.path}/vault').create();
    failItems = false;
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
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Item named(String name) =>
      store.items.values.singleWhere((n) => n.name == name);
  Event record(String id, String itemId, {bool incomplete = false}) => Event(
    id,
    '保留记录',
    ['work'],
    DateTime.utc(2026, 11, 8, 9),
    incomplete ? null : DateTime.utc(2026, 11, 8, 10),
    '原备注',
    itemId,
  );

  test(
    'deleting task lines and files removes unreferenced nodes in all states',
    () async {
      final file = File('${vault.path}/A.md');
      await file.writeAsString('- [ ] 待办\n- [/] 暂停\n- [-] 取消\n- [x] 完成\n');
      await store.saveItem(const Item(id: 'local', name: '本地事项'));
      await sync.synchronize(store, vault);
      final root = named('A');
      final content = await file.readAsString();
      await file.writeAsString(
        content.split('\n').where((l) => !l.startsWith('- [')).join('\n'),
      );
      await sync.synchronize(store, vault);
      expect(store.items.keys.toSet(), {'local', root.id});
      expect(store.deletedObsidianReferences, isEmpty);
      await file.delete();
      await sync.synchronize(store, vault);
      expect(store.items.keys, ['local']);
      final reopened = await Store.open(store.directory);
      expect(reopened.items, store.items);
      final snapshot =
          jsonDecode(
                await File(
                  '${store.directory.path}/tree-backups/latest.json',
                ).readAsString(),
              )
              as Map;
      expect((snapshot['items'] as List).length, 1);
    },
  );

  test(
    'only directly referenced deleted nodes survive, with original attributes and tags',
    () async {
      final file = File('${vault.path}/A.md');
      await file.writeAsString(
        '---\ntags: [主业]\n---\n- [/] 父事项 #副业\n  - [x] 有记录 | 描述 | 结果 #自有\n  - [-] 无记录\n',
      );
      await sync.synchronize(store, vault);
      final root = named('A');
      final child = named('有记录');
      final tags = store.effectiveItemTagIds(child.id);
      final records = [
        record('root-record', root.id),
        record('child-record', child.id, incomplete: true),
      ];
      await store.replaceEvents({for (final event in records) event.id: event});
      await store.saveItem(
        Item(id: 'local', name: '本地子事项', parentId: named('父事项').id),
      );
      await file.delete();
      await sync.synchronize(store, vault);
      expect(store.items.keys.toSet(), {root.id, child.id, 'local'});
      expect(store.items[child.id]!.parentId, root.id);
      expect(store.items[child.id]!.status, ItemStatus.done);
      expect(store.items[child.id]!.objective, '描述');
      expect(store.items[child.id]!.outcome, '结果');
      expect(store.items[child.id]!.source!.raw, child.source!.raw);
      expect(store.items[child.id]!.source!.missing, true);
      expect(store.items[root.id]!.status, ItemStatus.active);
      expect(store.items[root.id]!.isTodo, false);
      expect(store.effectiveItemTagIds(child.id), tags);
      expect(store.effectiveItemTagIds('local').map(store.tagName).toSet(), {
        '主业',
        '副业',
      });
      expect(store.items['local']!.parentId, root.id);
      expect(store.deletedObsidianReferences, {root.id: 1, child.id: 1});
      final reopened = await Store.open(store.directory);
      expect(reopened.items, store.items);
      expect(reopened.events, {for (final event in records) event.id: event});
      // Clearing the last saved references allows the next sync to remove old tombstones.
      await store.replaceEvents({});
      await sync.synchronize(store, vault);
      expect(store.items.keys, ['local']);
      expect(store.items['local']!.parentId, isNull);
      expect(store.effectiveItemTagIds('local').map(store.tagName).toSet(), {
        '主业',
        '副业',
      });
      expect(store.deletedObsidianReferences, isEmpty);
    },
  );

  test(
    'cutting tasks into another note and deleting the old note preserves records without warnings',
    () async {
      final a = File('${vault.path}/A.md');
      final b = File('${vault.path}/B.md');
      await a.writeAsString('- [ ] 父事项\n  - [ ] 子事项 | 描述\n');
      await b.writeAsString('');
      await sync.synchronize(store, vault);
      final oldRoot = named('A').id;
      final parent = named('父事项');
      final child = named('子事项');
      final event = record('e', child.id);
      await store.saveEvent(event);
      final lines = (await a.readAsString())
          .split('\n')
          .where((l) => l.contains('- ['))
          .join('\n');
      await b.writeAsString('${await b.readAsString()}\n$lines\n');
      await a.delete();
      await sync.synchronize(store, vault);
      expect(store.items.containsKey(oldRoot), false);
      expect(store.items[parent.id]!.parentId, named('B').id);
      expect(store.items[child.id]!.parentId, parent.id);
      expect(store.items[child.id]!.source!.path, 'B.md');
      expect(store.items[child.id]!.source!.missing, false);
      expect(store.events['e'], event);
      expect(store.deletedObsidianReferences, isEmpty);
      expect((await Store.open(store.directory)).events['e'], event);
    },
  );

  test(
    'a referenced deleted task is detached from an unreferenced file and recovers by ID',
    () async {
      final file = File('${vault.path}/A.md');
      await file.writeAsString('---\ntags: [主业]\n---\n- [ ] 任务 | 描述\n');
      await sync.synchronize(store, vault);
      final task = named('任务');
      final content = await file.readAsString();
      final event = record('e', task.id);
      await store.saveEvent(event);
      await file.delete();
      await sync.synchronize(store, vault);
      expect(store.items.keys, [task.id]);
      expect(store.items[task.id]!.parentId, isNull);
      expect(store.effectiveItemTagIds(task.id), ['work']);
      expect(store.items[task.id]!.status, ItemStatus.active);
      expect(store.deletedObsidianReferences, {task.id: 1});
      await File('${vault.path}/恢复.md').writeAsString(content);
      await sync.synchronize(store, vault);
      expect(store.items[task.id]!.source!.missing, false);
      expect(store.items[task.id]!.parentId, named('恢复').id);
      expect(store.items[task.id]!.isTodo, true);
      expect(store.events['e'], event);
      expect(store.deletedObsidianReferences, isEmpty);
    },
  );

  test(
    'a failed deletion write retains disk, records and the previous complete snapshot',
    () async {
      final file = File('${vault.path}/A.md');
      await file.writeAsString('- [ ] 有记录\n- [ ] 无记录\n');
      await sync.synchronize(store, vault);
      final event = record('e', named('有记录').id);
      await store.saveEvent(event);
      final oldItems = store.items;
      final snapshot = File('${store.directory.path}/tree-backups/latest.json');
      final oldSnapshot = await snapshot.readAsBytes();
      await file.delete();
      failItems = true;
      await expectLater(
        sync.synchronize(store, vault),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.items, oldItems);
      expect(store.events['e'], event);
      expect(await snapshot.readAsBytes(), oldSnapshot);
      expect((await Store.open(store.directory)).items, oldItems);
      failItems = false;
      await sync.synchronize(store, vault);
      expect(store.items.keys, [event.itemId]);
      expect(store.events['e'], event);
    },
  );
}
