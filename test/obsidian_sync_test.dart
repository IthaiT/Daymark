import 'dart:convert';
import 'dart:io';

import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/obsidian_sync.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
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
      expect(annotated, contains('<!-- daymark:'));
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
}
