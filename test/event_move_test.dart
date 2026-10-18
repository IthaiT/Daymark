import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Store store;
  late JournalController controller;
  var writes = 0;
  final day = DateTime.utc(2026, 10, 12);
  setUp(() async {
    directory = await (await Directory(
      '.test-artifacts',
    ).create()).createTemp('event-move-');
    writes = 0;
    store = await Store.open(
      directory,
      writer: (file, bytes) async {
        writes++;
        await AtomicFile.write(file, bytes);
      },
    );
    controller = JournalController(store, day: day);
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });

  Event event(String id, String? tag, int startHour) => Event(
    id,
    id,
    tag,
    day.add(Duration(hours: startHour)),
    day.add(Duration(hours: startHour + 1)),
  );

  test('moves several events in one write and one undo step', () async {
    final first = event('first', 'linux', 9);
    final second = event('second', null, 10);
    final later = event('later', 'linux', 13);
    await store.replaceEvents({
      first.id: first,
      second.id: second,
      later.id: later,
    });
    await controller.initialize();
    final missing = store.events.values.singleWhere(
      (event) => event.isUndefined,
    );
    final beforeWrites = writes;

    await controller.setEventTag([first.id, second.id, missing.id], 'work');

    expect(writes - beforeWrites, 1);
    expect(store.events[first.id]!.tagId, 'work');
    expect(store.events[second.id]!.tagId, 'work');
    expect(store.events[missing.id]?.isUndefined, isTrue);
    expect(controller.history.canUndo, isTrue);

    await controller.undo();
    expect(store.events[first.id]!.tagId, 'linux');
    expect(store.events[second.id]!.tagId, isNull);
    expect(store.events[missing.id]?.isUndefined, isTrue);
    await controller.redo();
    expect(store.events[first.id]!.tagId, 'work');
  });

  test('clears a tag to unclassified and rejects unknown targets', () async {
    final first = event('first', 'linux', 9);
    await store.replaceEvents({first.id: first});
    await controller.initialize();

    await expectLater(
      controller.setEventTag([first.id], 'missing'),
      throwsFormatException,
    );
    expect(store.events[first.id]!.tagId, 'linux');

    await controller.setEventTag([first.id], null);
    expect(store.events[first.id]!.tagId, isNull);
  });

  test('does not write when the selection has nothing to change', () async {
    final first = event('first', 'linux', 9);
    await store.replaceEvents({first.id: first});
    await controller.initialize();
    final beforeWrites = writes;

    await controller.setEventTag([first.id], 'linux');
    await controller.setEventTag(['not-stored'], 'work');

    expect(writes, beforeWrites);
    expect(controller.history.canUndo, isFalse);
  });
}
