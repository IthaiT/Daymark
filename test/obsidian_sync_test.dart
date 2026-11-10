import 'dart:convert';
import 'dart:io';

import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/obsidian_sync.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/item.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/obsidian_ids.dart';

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
      final source = '- [ ] one ${obsidianId(99)}\n- [ ] two ${obsidianId(99)}';
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
  for (final changeCopy in [false, true]) {
    test(
      'copying an ID across notes fails atomically (changed: $changeCopy), then deleting the source preserves history',
      () async {
        final a = File('${vault.path}/A.md');
        final b = File('${vault.path}/B.md');
        await a.writeAsString('- [ ] 任务 | 描述 | 结果\n');
        await b.writeAsString('目标文件\n');
        const sync = ObsidianSync();
        await sync.synchronize(store, vault);
        final task = store.items.values.singleWhere((n) => n.name == '任务');
        final record = Event(
          'copied-record',
          '原有时间记录',
          ['work'],
          DateTime.utc(2026, 11, 10, 9),
          DateTime.utc(2026, 11, 10, 10),
          '保留原备注',
          task.id,
        );
        await store.saveEvent(record);
        final originalA = await a.readAsString();
        final taskLine = originalA
            .split('\n')
            .singleWhere((line) => line.startsWith('- [ ]'));
        final copiedLine = changeCopy
            ? taskLine.replaceFirst('任务', '修改后的任务')
            : taskLine;
        final copiedB = '${await b.readAsString()}$copiedLine\n';
        await b.writeAsString(copiedB);
        final itemsFile = File('${store.directory.path}/items.json');
        final persistedItems = await itemsFile.readAsBytes();
        final priorItems = Map<String, Item>.of(store.items);
        await expectLater(
          sync.synchronize(store, vault),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'duplicate identity message',
              contains('重复事项 ID'),
            ),
          ),
        );
        expect(await a.readAsString(), originalA);
        expect(await b.readAsString(), copiedB);
        expect(await itemsFile.readAsBytes(), persistedItems);
        expect(store.items, priorItems);
        expect(store.events[record.id], record);
        final unchanged = await Store.open(store.directory);
        expect(unchanged.items, priorItems);
        expect(unchanged.events[record.id], record);

        // Copy + delete is a move with the same ID, independent of clipboard state.
        await a.writeAsString(originalA.replaceFirst('$taskLine\n', ''));
        await sync.synchronize(store, vault);
        expect(store.items[task.id]!.source!.path, 'B.md');
        expect(store.items[task.id]!.source!.missing, false);
        expect(store.items[task.id]!.name, changeCopy ? '修改后的任务' : '任务');
        expect(store.events[record.id], record);
      },
    );
  }
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
  test(
    'note to task to note uses one unchanged ID across restart and saved records',
    () async {
      final jobFile = File('${vault.path}/跳槽.md');
      final workFile = File('${vault.path}/主业.md');
      await jobFile.writeAsString(
        '---\ntags: [副业]\n---\n- [ ] 修改简历 | 描述 | 结果\n',
      );
      await workFile.writeAsString('---\ntags: [主业]\n---\n');
      const sync = ObsidianSync();
      await sync.synchronize(store, vault);
      final job = store.items.values.singleWhere((n) => n.name == '跳槽');
      final resume = store.items.values.singleWhere((n) => n.name == '修改简历');
      final work = store.items.values.singleWhere((n) => n.name == '主业');
      final originalWork = await workFile.readAsString();
      expect(await jobFile.readAsString(), contains('daymark-id: "${job.id}"'));
      expect(resume.source!.raw, endsWith(resume.id));
      final records = {
        'job': Event(
          'job',
          '跳槽记录',
          ['work'],
          DateTime.utc(2026, 11, 8, 9),
          DateTime.utc(2026, 11, 8, 10),
          '原备注',
          job.id,
        ),
        'resume': Event(
          'resume',
          '简历记录',
          ['side'],
          DateTime.utc(2026, 11, 8, 10),
          DateTime.utc(2026, 11, 8, 11),
          '',
          resume.id,
        ),
      };
      await store.replaceEvents(records);
      // The user copies the note property's complete value directly onto the new line.
      await workFile.writeAsString(
        '$originalWork\n- [ ] 跳槽 #副业 ${job.id}\n    ${resume.source!.raw}\n',
      );
      await jobFile.delete();
      final reopened = await Store.open(store.directory, backupTrees: true);
      await sync.synchronize(reopened, vault);
      expect(reopened.items.length, 3);
      expect(reopened.items[job.id]!.source!.kind, 'task');
      expect(reopened.items[job.id]!.parentId, work.id);
      expect(reopened.items[resume.id]!.parentId, job.id);
      expect(reopened.items[resume.id]!.objective, '描述');
      expect(reopened.items[resume.id]!.outcome, '结果');
      expect(reopened.items[resume.id]!.source!.path, '主业.md');
      expect(reopened.deletedObsidianReferences, isEmpty);
      expect(reopened.events, records);
      final snapshot =
          jsonDecode(
                await File(
                  '${store.directory.path}/tree-backups/latest.json',
                ).readAsString(),
              )
              as Map;
      expect(
        (snapshot['events'] as List).map((e) => (e as Map)['item_id']).toSet(),
        {job.id, resume.id},
      );
      // The reverse operation copies the same task ID into a new note's property.
      await workFile.writeAsString(originalWork);
      await File('${vault.path}/换工作.md').writeAsString(
        '---\ndaymark-id: "${job.id}"\ntags: [副业]\n---\n${resume.source!.raw}\n',
      );
      final split = await Store.open(store.directory, backupTrees: true);
      await sync.synchronize(split, vault);
      expect(split.items[job.id]!.name, '换工作');
      expect(split.items[job.id]!.source!.kind, 'file');
      expect(split.items[job.id]!.parentId, isNull);
      expect(split.items[resume.id]!.parentId, job.id);
      expect(split.items[resume.id]!.source!.path, '换工作.md');
      expect(split.events, records);
      expect(split.deletedObsidianReferences, isEmpty);
      expect((await Store.open(store.directory)).events, records);
    },
  );

  test(
    'leaving a note and a task with the same ID rejects the entire sync',
    () async {
      final a = File('${vault.path}/A.md');
      final b = File('${vault.path}/B.md');
      await a.writeAsString('- [ ] 原任务');
      await b.writeAsString('');
      const sync = ObsidianSync();
      await sync.synchronize(store, vault);
      final rootId = store.items.values.singleWhere((n) => n.name == 'A').id;
      final oldItems = store.items;
      final originalA = await a.readAsString();
      final duplicate = '${await b.readAsString()}\n- [ ] 合并但未删除原文件 $rootId\n';
      await b.writeAsString(duplicate);
      await expectLater(sync.synchronize(store, vault), throwsFormatException);
      expect(await a.readAsString(), originalA);
      expect(await b.readAsString(), duplicate);
      expect(store.items, oldItems);
      expect((await Store.open(store.directory)).items, oldItems);
    },
  );

  test(
    'unsupported IDs fail without rewriting any Markdown or stored data',
    () async {
      final a = File('${vault.path}/A.md');
      final b = File('${vault.path}/B.md');
      await a.writeAsString('- [ ] 已有任务');
      const sync = ObsidianSync();
      await sync.synchronize(store, vault);
      final oldItems = store.items;
      final oldTags = store.tags;
      final originalA = await a.readAsString();
      for (final invalid in [
        '---\ndaymark-id: obsidian-00000000-0000-4000-8000-000000000001\n---\n- [ ] 不应写入\n',
        '<!-- daymark-file:old -->\n- [ ] 不应写入\n',
        '- [ ] 不应写入 ^custom-link\n',
      ]) {
        await b.writeAsString(invalid);
        await expectLater(
          sync.synchronize(store, vault),
          throwsFormatException,
        );
        expect(await a.readAsString(), originalA);
        expect(await b.readAsString(), invalid);
        expect(store.items, oldItems);
        expect(store.tags, oldTags);
        expect((await Store.open(store.directory)).items, oldItems);
      }
    },
  );
  test(
    'noncanonical saved identities are rejected instead of splitting record ownership',
    () async {
      final path = await vault.resolveSymbolicLinks();
      final rootId = obsidianId(20);
      final taskId = obsidianId(21);
      final storedId = taskId.substring('^daymark-'.length);
      final line = '- [ ] 正文格式正确但存储身份错误 $taskId';
      final content = '---\ndaymark-id: "$rootId"\n---\n$line\n';
      final file = File('$path/A.md');
      await file.writeAsString(content);
      await store.saveItem(
        Item(
          id: rootId,
          name: 'A',
          source: ItemSource(
            directory: path,
            path: 'A.md',
            kind: 'file',
            order: 0,
            raw: content,
          ),
        ),
      );
      await store.saveItem(
        Item(
          id: storedId,
          name: '原事项',
          parentId: rootId,
          source: ItemSource(
            directory: path,
            path: 'A.md',
            kind: 'task',
            order: 0,
            raw: line,
          ),
        ),
      );
      final event = Event(
        'e',
        '原记录',
        'work',
        DateTime.utc(2026, 11, 8, 9),
        DateTime.utc(2026, 11, 8, 10),
        '原备注',
        storedId,
      );
      await store.saveEvent(event);
      final oldItems = store.items;
      final oldBytes = await store.eventsFile.readAsBytes();
      await expectLater(
        const ObsidianSync().synchronize(store, vault),
        throwsFormatException,
      );
      expect(store.items, oldItems);
      expect(store.events['e'], event);
      expect(await file.readAsString(), content);
      expect(await store.eventsFile.readAsBytes(), oldBytes);
      expect((await Store.open(store.directory)).items, oldItems);
    },
  );
}
