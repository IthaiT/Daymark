import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daymark/application/appearance_controller.dart';
import 'package:daymark/data/appearance_store.dart';
import 'package:daymark/domain/appearance.dart';

void main() {
  late Directory directory;

  setUp(() async {
    await Directory('.test-artifacts').create(recursive: true);
    directory = await Directory('.test-artifacts').createTemp('appearance-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('missing preferences stay in memory until an explicit change', () async {
    final store = await AppearanceStore.open(directory);
    expect(store.state.palette, AppPalette.slate);
    expect(await store.file.exists(), isFalse);
    expect(await directory.list().toList(), isEmpty);
  });

  test('palette selection persists without creating record files', () async {
    final store = await AppearanceStore.open(directory);
    final controller = AppearanceController(store);
    addTearDown(controller.dispose);
    await controller.setPalette(AppPalette.rose);
    final reopened = await AppearanceStore.open(directory);
    expect(reopened.state.palette, AppPalette.rose);
    expect(jsonDecode(await store.file.readAsString()), {
      'version': 1,
      'palette': 'rose',
    });
    expect(
      (await directory.list().toList()).map(
        (file) => file.uri.pathSegments.last,
      ),
      ['appearance.json'],
    );
  });

  test(
    'invalid preferences preserve the original file and use defaults',
    () async {
      for (final source in [
        '{bad',
        '{"version":2,"palette":"rose"}',
        '{"version":1,"palette":"unknown"}',
      ]) {
        final file = File('${directory.path}/appearance.json');
        await file.writeAsString(source);
        final store = await AppearanceStore.open(directory);
        expect(store.state.palette, AppPalette.slate);
        expect(store.readError, isA<FormatException>());
        expect(await file.readAsString(), source);
      }
    },
  );

  test(
    'failed preference write retains the prior theme and permits retry',
    () async {
      var fail = true;
      final store = await AppearanceStore.open(
        directory,
        writer: (file, bytes) async {
          if (fail) throw const FileSystemException('synthetic failure');
          await file.writeAsBytes(bytes, flush: true);
        },
      );
      final controller = AppearanceController(store);
      addTearDown(controller.dispose);
      await expectLater(
        controller.setPalette(AppPalette.indigo),
        throwsA(isA<FileSystemException>()),
      );
      expect(controller.state.palette, AppPalette.slate);
      expect(controller.busy, isFalse);
      expect(await store.file.exists(), isFalse);
      fail = false;
      await controller.setPalette(AppPalette.sand);
      expect(controller.state.palette, AppPalette.sand);
    },
  );

  test(
    'tag colour overrides persist, clear and tolerate unknown values',
    () async {
      final store = await AppearanceStore.open(directory);
      final controller = AppearanceController(store);
      addTearDown(controller.dispose);
      await controller.setTagColor('work', TagColor.pink);
      await controller.setTagColor('side', TagColor.amber);
      expect(jsonDecode(await store.file.readAsString()), {
        'version': 1,
        'palette': 'slate',
        'tag_colors': {'work': 'pink', 'side': 'amber'},
      });
      final reopened = await AppearanceStore.open(directory);
      expect(reopened.state.tagColors, {
        'work': TagColor.pink,
        'side': TagColor.amber,
      });

      await controller.setTagColor('work', null);
      expect(controller.state.tagColors, {'side': TagColor.amber});
      expect(
        (jsonDecode(await store.file.readAsString())
            as Map<String, Object?>)['tag_colors'],
        {'side': 'amber'},
      );

      await store.file.writeAsString(
        '{"version":1,"palette":"slate","tag_colors":'
        '{"work":"teal","ghost":"mauve","removed":1}}',
      );
      final lenient = await AppearanceStore.open(directory);
      expect(lenient.state.tagColors, {'work': TagColor.teal});
      expect(lenient.readError, isNull);
    },
  );

  test('queued theme changes commit in order', () async {
    final gate = Completer<void>();
    final writes = <String>[];
    final store = await AppearanceStore.open(
      directory,
      writer: (file, bytes) async {
        final value = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
        writes.add(value['palette']! as String);
        if (writes.length == 1) await gate.future;
        await file.writeAsBytes(bytes, flush: true);
      },
    );
    final controller = AppearanceController(store);
    addTearDown(controller.dispose);
    final first = controller.setPalette(AppPalette.pine);
    final last = controller.setPalette(AppPalette.indigo);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.palette, AppPalette.slate);
    gate.complete();
    await Future.wait([first, last]);
    expect(writes, ['pine', 'indigo']);
    expect(controller.state.palette, AppPalette.indigo);
  });
}
