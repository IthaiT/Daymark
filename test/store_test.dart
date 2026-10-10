import 'dart:convert';
import 'dart:io';

import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/instance_lock.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

final throwsFileSystemException = throwsA(isA<FileSystemException>());

void main() {
  late Directory directory;
  late Store store;
  var failWrites = false;
  setUp(() async {
    final artifacts = await Directory('.test-artifacts').create();
    directory = await artifacts.createTemp('dart-store-');
    failWrites = false;
    store = await Store.open(
      directory,
      writer: (file, bytes) async {
        if (failWrites) throw const FileSystemException('模拟写入失败');
        await AtomicFile.write(file, bytes);
      },
    );
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  Event sample({String id = 'event', String? tagId = 'linux', DateTime? end}) =>
      Event(
        id,
        '学习 Linux, "驱动"',
        tagId,
        DateTime.utc(2026, 10, 7, 9, 0, 35),
        end ?? DateTime.utc(2026, 10, 7, 10, 0, 45),
        '第一行\n第二行',
      );

  test(
    'Chinese, CSV quotes, multiline notes and legacy seconds round trip with BOM',
    () async {
      final item = sample();
      await store.saveEvent(item);
      expect((await Store.open(directory)).events[item.id], item);
      expect((await store.eventsFile.readAsBytes()).take(3), [
        0xef,
        0xbb,
        0xbf,
      ]);
      expect(
        (await store.eventsFile.readAsString()).split('\r\n').first,
        csvFields.join(','),
      );
    },
  );

  test(
    'all tag levels and unclassified events survive hierarchy changes',
    () async {
      for (final (index, tag) in <String?>[
        null,
        'work',
        'embedded',
        'linux',
      ].indexed) {
        await store.saveEvent(sample(id: '$index', tagId: tag));
      }
      final bytes = await store.eventsFile.readAsBytes();
      await store.saveTag('嵌入式改名', 'side', id: 'embedded');
      await store.saveTag('新子标签', 'linux');
      expect(await store.eventsFile.readAsBytes(), bytes);
      expect((await Store.open(directory)).events['3']!.tagId, 'linux');
      expect(store.ancestors('linux').map((tag) => tag.id), [
        'side',
        'embedded',
        'linux',
      ]);
    },
  );

  test(
    'cycles, duplicate siblings and tags in use are rejected before writes',
    () async {
      final bytes = await store.tagsFile.readAsBytes();
      await expectLater(
        store.saveTag('主业', 'linux', id: 'work'),
        throwsFormatException,
      );
      await expectLater(
        store.saveTag('LINUX', 'embedded'),
        throwsFormatException,
      );
      await expectLater(store.deleteTag('embedded'), throwsFormatException);
      await store.saveEvent(sample());
      await expectLater(store.deleteTag('linux'), throwsFormatException);
      expect(await store.tagsFile.readAsBytes(), bytes);
    },
  );

  test(
    'unfinished legacy event is visible on start day without inferred duration',
    () async {
      final item = Event(
        'legacy',
        '旧记录',
        'work',
        DateTime.utc(2026, 10, 7, 9),
        null,
      );
      await store.replaceEvents({item.id: item});
      final restored = await Store.open(directory);
      expect(restored.eventsOn(DateTime.utc(2026, 10, 7)), [item]);
      expect(item.intervalOn(DateTime.utc(2026, 10, 7)), isNull);
      await expectLater(store.saveEvent(item), throwsFormatException);
    },
  );

  test(
    'failed event and tag saves preserve file, memory and temp cleanup',
    () async {
      await store.saveEvent(sample());
      final eventBytes = await store.eventsFile.readAsBytes();
      final tagBytes = await store.tagsFile.readAsBytes();
      final oldTags = store.tags;
      final oldEvents = store.events;
      failWrites = true;
      await expectLater(
        store.saveEvent(sample(id: 'another')),
        throwsFileSystemException,
      );
      await expectLater(store.saveTag('新标签', null), throwsFileSystemException);
      expect(store.tags, oldTags);
      expect(store.events, oldEvents);
      expect(await store.eventsFile.readAsBytes(), eventBytes);
      expect(await store.tagsFile.readAsBytes(), tagBytes);
      expect(
        directory.listSync().where((file) => file.path.endsWith('.tmp')),
        isEmpty,
      );
    },
  );

  test(
    'invalid or corrupt CSV cannot be overwritten or initialize a missing tag file',
    () async {
      for (final source in [
        'id,title\r\na,b\r\n',
        '${csvFields.join(',')}\r\na,事件,work,2026-02-30T09:00:00,2026-10-07T10:00:00,\r\n',
        '${csvFields.join(',')}\r\na,事件,work,2026-10-07T09:00:00,2026-10-07T10:00:00,extra,too many\r\n',
        '${csvFields.join(',')}\r\na,"未关闭,work,2026-10-07T09:00:00,,\r\n',
      ]) {
        await store.eventsFile.writeAsString(source);
        final bytes = await store.eventsFile.readAsBytes();
        await expectLater(Store.open(directory), throwsA(isA<DataError>()));
        expect(await store.eventsFile.readAsBytes(), bytes);
      }
      await store.tagsFile.delete();
      await expectLater(Store.open(directory), throwsA(isA<DataError>()));
      expect(await store.tagsFile.exists(), isFalse);
    },
  );

  test(
    'corrupt JSON including cycles and missing ancestors preserves both files',
    () async {
      for (final payload in [
        {'version': 2, 'tags': []},
        {
          'version': 1,
          'tags': [
            {'id': 'a', 'name': 'a', 'parent_id': 'b'},
            {'id': 'b', 'name': 'b', 'parent_id': 'missing'},
          ],
        },
        {
          'version': 1,
          'tags': [
            {'id': 'a', 'name': 'a', 'parent_id': 'b'},
            {'id': 'b', 'name': 'b', 'parent_id': 'a'},
          ],
        },
        {
          'version': 1,
          'tags': [
            {'id': 'a', 'name': 'a'},
            {'id': 'a', 'name': 'b'},
          ],
        },
      ]) {
        await store.tagsFile.writeAsString(jsonEncode(payload));
        final bytes = await store.tagsFile.readAsBytes();
        await expectLater(Store.open(directory), throwsA(isA<DataError>()));
        expect(await store.tagsFile.readAsBytes(), bytes);
      }
      await store.eventsFile.delete();
      await expectLater(Store.open(directory), throwsA(isA<DataError>()));
      expect(await store.eventsFile.exists(), isFalse);
    },
  );

  test('instance lock rejects another handle and is released on close', () {
    final first = InstanceLock.acquire(directory);
    try {
      expect(() => InstanceLock.acquire(directory), throwsFormatException);
    } finally {
      first.close();
    }
    final next = InstanceLock.acquire(directory);
    next.close();
    next.close();
  }, skip: !Platform.isWindows);

  test(
    'maps exposed to callers cannot bypass validation or mutate saved state',
    () {
      expect(() => store.tags.clear(), throwsUnsupportedError);
      expect(() => store.events.clear(), throwsUnsupportedError);
    },
  );
}
