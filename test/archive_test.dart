import 'dart:io';

import 'package:daymark/data/archive_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/journal_archive.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 10, 24);
  Event event(String id, DateTime start, DateTime? end) =>
      Event(id, id, 'work', start, end, '合成备注');
  test('complete dates require full coverage, midnight and a past date', () {
    final next = day.add(const Duration(days: 1));
    final full = event('a', day, next);
    expect(completedJournalDays([full], next), {day});
    expect(completedJournalDays([full], day), isEmpty);
    expect(
      completedJournalDays([
        full.copyWith(end: next.subtract(const Duration(seconds: 1))),
      ], next),
      isEmpty,
    );
    expect(
      completedJournalDays([
        full.copyWith(start: day.add(const Duration(hours: 9))),
      ], next),
      isEmpty,
    );
    expect(
      completedJournalDays([event('unfinished', day, null)], next),
      isEmpty,
    );
    expect(
      completedJournalDays([full.copyWith(id: 'undefined:old')], next),
      isEmpty,
    );
  });
  test(
    'bounded gaps, overlaps and overnight events establish complete dates',
    () {
      final items = [
        event(
          'a',
          day.subtract(const Duration(hours: 2)),
          day.add(const Duration(hours: 7)),
        ),
        event(
          'b',
          day.add(const Duration(hours: 6)),
          day.add(const Duration(hours: 8)),
        ),
        event(
          'c',
          day.add(const Duration(days: 2, hours: 7)),
          day.add(const Duration(days: 2, hours: 9)),
        ),
      ];
      expect(completedJournalDays(items, day.add(const Duration(days: 3))), {
        day,
        day.add(const Duration(days: 1)),
      });
      expect(eventTouchesDays(items.first, {day}), isTrue);
      expect(
        eventTouchesDays(
          event('midnight', day.subtract(const Duration(hours: 1)), day),
          {day},
        ),
        isFalse,
      );
    },
  );

  group('fixed archive backup', () {
    late Directory directory;
    late Store store;
    setUp(() async {
      directory = await (await Directory(
        '.test-artifacts',
      ).create()).createTemp('archive-');
      store = await Store.open(directory);
      await store.replaceEvents({
        'a': event('a', day, day.add(const Duration(days: 1))),
      });
    });
    tearDown(() async => directory.delete(recursive: true));
    test(
      'a whole gap-only day is backed up before gap synchronization',
      () async {
        final left = event(
          'left',
          day.subtract(const Duration(hours: 1)),
          day.subtract(const Duration(minutes: 10)),
        );
        final right = event(
          'right',
          day.add(const Duration(days: 1, minutes: 6)),
          day.add(const Duration(days: 1, hours: 8)),
        );
        await store.replaceEvents({left.id: left, right.id: right});
        final archive = await ArchiveStore.open(directory);
        await archive.capture(
          store,
          day.add(const Duration(days: 1, hours: 9)),
        );
        final reopened = await ArchiveStore.open(directory);
        expect(reopened.days, {day});
        expect(
          reopened.events.values.single,
          undefinedEvents([left, right]).single,
        );
        expect(store.events.length, 2);
      },
    );
    test(
      'archived gap snapshots retain stored names, notes and full overnight bounds',
      () async {
        final left = event('left', day, day.add(const Duration(hours: 10)));
        final right = event(
          'right',
          day.add(const Duration(days: 1, hours: 2)),
          day.add(const Duration(days: 1, hours: 8)),
        );
        final gap = undefinedEvents([
          left,
          right,
        ]).single.copyWith(title: '跨天已记录空档', notes: '保留已有内容');
        await store.replaceEvents({
          left.id: left,
          right.id: right,
          gap.id: gap,
        });
        final archive = await ArchiveStore.open(directory);
        await archive.capture(
          store,
          day.add(const Duration(days: 1, hours: 9)),
        );
        expect((await ArchiveStore.open(directory)).events[gap.id], gap);
      },
    );
    test(
      'round trips full records and tags, appends dates and retains old backup',
      () async {
        final archive = await ArchiveStore.open(directory);
        final now = day.add(const Duration(days: 1));
        await archive.capture(store, now);
        final initial = await archive.file.readAsBytes();
        await archive.capture(store, now);
        expect(await archive.file.readAsBytes(), initial);
        final original = archive.events['a'];
        await store.replaceEvents({
          'a': store.events['a']!.copyWith(title: '外部错误修改'),
          'b': event('b', now, now.add(const Duration(days: 1))),
        });
        await archive.capture(store, now.add(const Duration(days: 1)));
        final reopened = await ArchiveStore.open(directory);
        expect(reopened.events['a'], original);
        expect(reopened.events['b'], store.events['b']);
        expect(reopened.tags, store.tags);
        expect(reopened.days, {day, now});
        expect(
          directory.listSync().where((f) => f.path.endsWith('archive.json')),
          hasLength(1),
        );
        await archive.capture(store, now, editedIds: {'a'});
        expect(
          (await ArchiveStore.open(directory)).events['a']!.title,
          '外部错误修改',
        );
      },
    );
    test('failure retains prior backup and archive dates for retry', () async {
      final archive = await ArchiveStore.open(directory);
      await archive.capture(store, day.add(const Duration(days: 1)));
      final bytes = await archive.file.readAsBytes();
      final failing = await ArchiveStore.open(
        directory,
        writer: (_, _) async {
          throw const FileSystemException('模拟备份失败');
        },
      );
      await store.replaceEvents({
        ...store.events,
        'b': event(
          'b',
          day.add(const Duration(days: 1)),
          day.add(const Duration(days: 2)),
        ),
      });
      await expectLater(
        failing.capture(store, day.add(const Duration(days: 2))),
        throwsA(isA<FileSystemException>()),
      );
      expect(failing.days, {day});
      expect(await archive.file.readAsBytes(), bytes);
    });
    test('corrupt archive stops loading without overwriting it', () async {
      final file = File('${directory.path}/archive.json');
      await file.writeAsString('{invalid');
      await expectLater(
        ArchiveStore.open(directory),
        throwsA(isA<DataError>()),
      );
      expect(await file.readAsString(), '{invalid');
    });
  });
}
