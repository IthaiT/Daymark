import 'dart:convert';
import 'dart:io';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('tree-backup-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  Future<Map<String, dynamic>> read(String name) async =>
      jsonDecode(
            await File('${directory.path}/tree-backups/$name').readAsString(),
          )
          as Map<String, dynamic>;
  test(
    'rotates the last observed day once and retains first-of-month snapshots',
    () async {
      var now = DateTime.utc(2026, 10, 31, 20);
      final store = await Store.open(directory, clock: () => now);
      await store.saveItem(const Item(id: 'a', name: '昨日树'));
      now = DateTime.utc(2026, 11, 1, 8);
      await store.captureTreeBackup();
      expect((await read('yesterday.json'))['date'], '2026-10-31');
      final monthly = await read('monthly/2026-11-01.json');
      await store.saveItem(const Item(id: 'a', name: '新树'));
      expect(await read('monthly/2026-11-01.json'), monthly);
      expect(
        ((await read('yesterday.json'))['items'] as List).single['name'],
        '昨日树',
      );
      now = DateTime.utc(2026, 11, 2);
      await store.captureTreeBackup();
      expect(
        ((await read('yesterday.json'))['items'] as List).single['name'],
        '新树',
      );
      expect((await read('yesterday.json'))['date'], '2026-11-01');
    },
  );
  test(
    'a failed post-write backup restores canonical bytes and memory',
    () async {
      var latestWrites = 0;
      var failAt = -1;
      final store = await Store.open(
        directory,
        writer: (file, bytes) async {
          if (file.path.endsWith('latest.json') && ++latestWrites == failAt) {
            throw const FileSystemException('backup denied');
          }
          await AtomicFile.write(file, bytes);
        },
      );
      await store.saveItem(const Item(id: 'a', name: '原值'));
      final bytes = await store.itemsFile.readAsBytes();
      failAt = latestWrites + 2;
      await expectLater(
        store.saveItem(const Item(id: 'a', name: '新值')),
        throwsA(isA<FileSystemException>()),
      );
      expect(await store.itemsFile.readAsBytes(), bytes);
      expect(store.items['a']!.name, '原值');
      expect((await Store.open(directory)).items['a']!.name, '原值');
    },
  );
  test(
    'corrupt latest snapshot is retained and never silently replaced',
    () async {
      final store = await Store.open(directory);
      final latest = File('${directory.path}/tree-backups/latest.json');
      await latest.writeAsString('broken');
      await expectLater(
        store.saveItem(const Item(id: 'a', name: '新值')),
        throwsFormatException,
      );
      expect(await latest.readAsString(), 'broken');
      expect(store.items, isEmpty);
    },
  );
}
