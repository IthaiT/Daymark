import 'dart:convert';
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
  late DateTime now;
  var fail = false;
  final rootId = obsidianId(801);
  final taskId = obsidianId(802);
  setUp(() async {
    now = DateTime(2026, 11, 8, 23, 30);
    fail = false;
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('item-completion-');
    vault = await Directory('${directory.path}/vault').create();
    store = await Store.open(
      Directory('${directory.path}/data'),
      clock: () => now,
      backupTrees: true,
      writer: (file, bytes) async {
        if (fail && file.path.endsWith('items.json')) {
          throw const FileSystemException('denied');
        }
        await AtomicFile.write(file, bytes);
      },
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  Future<void> write(
    String status, [
    String metadata = '',
  ]) => File('${vault.path}/A.md').writeAsString(
    '---\ndaymark-id: "$rootId"\ntags: [主业]\n---\n- [$status] 修改简历 | 描述 | 结果 $metadata $taskId\n',
  );
  Future<void> sync() => const ObsidianSync().synchronize(store, vault);

  test(
    'completion date admits today and six prior days, excluding future, unknown and missing',
    () {
      for (final age in [-1, 0, 6, 7, 30]) {
        final item = Item(
          id: 'a',
          name: 'a',
          status: ItemStatus.done,
          completedOn: DateTime.utc(2026, 11, 8).subtract(Duration(days: age)),
        );
        expect(item.canRecordOn(now), age >= 0 && age < 7);
        expect(Item.fromJson(item.toJson()), item);
        expect(item.copyWith(clearCompletedOn: true).completedOn, isNull);
      }
      expect(
        const Item(
          id: 'a',
          name: 'a',
          status: ItemStatus.done,
          outcome: 'done',
        ).canRecordOn(now),
        false,
      );
      for (final status in [ItemStatus.paused, ItemStatus.dropped]) {
        expect(
          Item(
            id: 'a',
            name: 'a',
            status: status,
            completedOn: dayStart(now),
          ).canRecordOn(now),
          false,
        );
      }
      final missing = Item(
        id: 'a',
        name: 'a',
        completedOn: dayStart(now),
        source: const ItemSource(
          directory: 'vault',
          path: 'A.md',
          kind: 'task',
          order: 0,
          raw: '',
          missing: true,
        ),
      );
      expect(missing.canRecordOn(now), false);
      expect(missing.copyWith(status: ItemStatus.done).canRecordOn(now), false);
    },
  );

  test(
    'plugin-free state observation survives restart, repeated sync, reopening and recompletion',
    () async {
      await write(' ');
      await sync();
      final event = Event(
        'e',
        '原名称',
        ['work'],
        DateTime.utc(2026, 11, 8, 9),
        DateTime.utc(2026, 11, 8, 10),
        '原备注',
        taskId,
      );
      await store.saveEvent(event);
      final before = await store.eventsFile.readAsBytes();
      await write('x');
      await sync();
      expect(store.items[taskId]!.completedOn, DateTime.utc(2026, 11, 8));
      expect(store.itemIdForTitle('修改简历'), taskId);
      now = DateTime(2026, 11, 14, 23, 59);
      store = await Store.open(
        store.directory,
        clock: () => now,
        backupTrees: true,
      );
      await sync();
      expect(store.items[taskId]!.canRecordOn(now), true);
      expect(store.items[taskId]!.completedOn, DateTime.utc(2026, 11, 8));
      now = DateTime(2026, 11, 15);
      await sync();
      expect(store.itemIdForTitle('修改简历'), isNull);
      await write(' ', '✅ 2026-11-08');
      await sync();
      expect(store.items[taskId]!.completedOn, isNull);
      expect(store.items[taskId]!.isTodo, true);
      await write('x');
      await sync();
      expect(store.items[taskId]!.completedOn, DateTime.utc(2026, 11, 15));
      expect(store.itemIdForTitle('修改简历'), taskId);
      expect(store.events['e'], event);
      expect(await store.eventsFile.readAsBytes(), before);
      final snapshot =
          jsonDecode(
                await File(
                  '${store.directory.path}/tree-backups/latest.json',
                ).readAsString(),
              )
              as Map;
      expect(
        ((snapshot['items'] as List).singleWhere(
              (row) => (row as Map)['id'] == taskId,
            )
            as Map)['completed_on'],
        '2026-11-15',
      );
    },
  );

  test(
    'first-import undated done stays unknown; optional source dates are honored',
    () async {
      await write('x');
      await sync();
      expect(store.items[taskId]!.completedOn, isNull);
      now = now.add(const Duration(days: 4));
      await sync();
      expect(store.items[taskId]!.completedOn, isNull);
      await write('x', '[completion:: 2026-11-08]');
      await sync();
      expect(store.items[taskId]!.completedOn, DateTime.utc(2026, 11, 8));
      expect(store.itemIdForTitle('修改简历'), taskId);
    },
  );

  test(
    'a failed sync does not persist or consume the observed transition',
    () async {
      await write(' ');
      await sync();
      await write('x');
      fail = true;
      await expectLater(sync(), throwsA(isA<FileSystemException>()));
      expect(store.items[taskId]!.completedOn, isNull);
      expect(store.items[taskId]!.status, ItemStatus.active);
      expect(
        (await Store.open(store.directory)).items[taskId]!.status,
        ItemStatus.active,
      );
      fail = false;
      now = now.add(const Duration(days: 1));
      await sync();
      expect(store.items[taskId]!.completedOn, DateTime.utc(2026, 11, 9));
    },
  );

  test(
    'local completion resets and restarts its date while edits retain it',
    () async {
      await store.saveItem(const Item(id: 'local', name: '本地事项'));
      var item = await store.saveItem(
        store.items['local']!.copyWith(status: ItemStatus.done, outcome: '完成'),
      );
      expect(item.completedOn, DateTime.utc(2026, 11, 8));
      now = now.add(const Duration(days: 10));
      item = await store.saveItem(item.copyWith(name: '改名'));
      expect(item.completedOn, DateTime.utc(2026, 11, 8));
      item = await store.saveItem(item.copyWith(status: ItemStatus.active));
      expect(item.completedOn, isNull);
      item = await store.saveItem(item.copyWith(status: ItemStatus.done));
      expect(item.completedOn, DateTime.utc(2026, 11, 18));
    },
  );

  test(
    'optional completion formats ignore literals and dates on non-done lines',
    () {
      for (final metadata in [
        '✅ 2026-11-08',
        '[completion:: 2026-11-08]',
        '(completion:: 2026-11-08)',
      ]) {
        final parsed = parseObsidian({
          'A.md':
              '---\ndaymark-id: "$rootId"\n---\n- [x] 名称 | $metadata 描述 | 结果 $taskId',
        }, directory: 'vault');
        expect(parsed.items[taskId]!.completedOn, DateTime.utc(2026, 11, 8));
        expect(parsed.items[taskId]!.objective, '描述');
      }
      for (final metadata in [
        '`✅ 2026-11-08`',
        '[[✅ 2026-11-08]]',
        '<!-- ✅ 2026-11-08 -->',
        '%% ✅ 2026-11-08 %%',
        '\\✅ 2026-11-08',
      ]) {
        final parsed = parseObsidian({
          'A.md': '---\ndaymark-id: "$rootId"\n---\n- [x] 名称 $metadata $taskId',
        }, directory: 'vault');
        expect(parsed.items[taskId]!.completedOn, isNull, reason: metadata);
      }
      for (final status in [' ', '/', '-']) {
        final parsed = parseObsidian({
          'A.md':
              '---\ndaymark-id: "$rootId"\n---\n- [$status] 名称 ✅ 2026-11-08 $taskId',
        }, directory: 'vault');
        expect(parsed.items[taskId]!.completedOn, isNull);
      }
      for (final metadata in [
        '✅ 2026-02-30',
        '✅ 2026-11-08 [completion:: 2026-11-07]',
      ]) {
        expect(
          () => parseObsidian({
            'A.md':
                '---\ndaymark-id: "$rootId"\n---\n- [x] 名称 $metadata $taskId',
          }, directory: 'vault'),
          throwsFormatException,
        );
      }
    },
  );
}
