import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daymark/application/settings_controller.dart';
import 'package:daymark/data/settings_store.dart';
import 'package:daymark/domain/settings.dart';

void main() {
  late Directory directory;

  setUp(() async {
    await Directory('.test-artifacts').create(recursive: true);
    directory = await Directory('.test-artifacts').createTemp('settings-');
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('missing settings stay in memory until an explicit change', () async {
    final store = await SettingsStore.open(directory);
    expect(store.state, const AppSettings());
    expect(store.state.autoUndefined, isTrue);
    expect(store.state.dragMinutes, 1);
    expect(await store.file.exists(), isFalse);
  });

  test('settings persist without creating record files', () async {
    final store = await SettingsStore.open(directory);
    final controller = SettingsController(store);
    addTearDown(controller.dispose);
    await controller.update(
      const AppSettings(autoUndefined: false, dragMinutes: 15),
    );
    final reopened = await SettingsStore.open(directory);
    expect(
      reopened.state,
      const AppSettings(autoUndefined: false, dragMinutes: 15),
    );
    expect(jsonDecode(await store.file.readAsString()), {
      'version': 1,
      'auto_undefined': false,
      'drag_minutes': 15,
      'split_overlap': false,
    });
    expect(
      (await directory.list().toList()).map(
        (file) => file.uri.pathSegments.last,
      ),
      ['settings.json'],
    );
  });

  test('split overlap preference survives a reopen', () async {
    final store = await SettingsStore.open(directory);
    final controller = SettingsController(store);
    addTearDown(controller.dispose);
    await controller.update(const AppSettings(splitOverlap: true));
    final reopened = await SettingsStore.open(directory);
    expect(reopened.state.splitOverlap, isTrue);
    expect(reopened.state, const AppSettings(splitOverlap: true));
  });

  test('unknown or missing values fall back to the defaults', () async {
    final file = File('${directory.path}/settings.json');
    await file.writeAsString(
      '{"version":1,"auto_undefined":"no","drag_minutes":7}',
    );
    final store = await SettingsStore.open(directory);
    expect(store.readError, isNull);
    expect(store.state, const AppSettings());
  });

  test(
    'invalid settings preserve the original file and use defaults',
    () async {
      for (final source in [
        '{bad',
        '{"version":2,"auto_undefined":false}',
        '[]',
      ]) {
        final file = File('${directory.path}/settings.json');
        await file.writeAsString(source);
        final store = await SettingsStore.open(directory);
        expect(store.state, const AppSettings());
        expect(store.readError, isA<FormatException>());
        expect(await file.readAsString(), source);
      }
    },
  );

  test(
    'failed settings write keeps the prior value and permits retry',
    () async {
      var fail = true;
      final store = await SettingsStore.open(
        directory,
        writer: (file, bytes) async {
          if (fail) throw const FileSystemException('synthetic failure');
          await file.writeAsBytes(bytes, flush: true);
        },
      );
      final controller = SettingsController(store);
      addTearDown(controller.dispose);
      await expectLater(
        controller.update(const AppSettings(dragMinutes: 30)),
        throwsA(isA<FileSystemException>()),
      );
      expect(controller.state, const AppSettings());
      expect(await store.file.exists(), isFalse);
      fail = false;
      await controller.update(const AppSettings(dragMinutes: 30));
      expect(controller.state.dragMinutes, 30);
    },
  );
}
