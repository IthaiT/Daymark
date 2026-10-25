import 'dart:io';

import 'package:daymark/application/appearance_controller.dart';
import 'package:daymark/data/appearance_store.dart';
import 'package:daymark/domain/appearance.dart';
import 'package:daymark/domain/journal_view_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => Directory('.test-artifacts').create(recursive: true));

  test('old preferences retain recording-independent focused defaults', () {
    final old = AppAppearance.fromJson({
      'version': 1,
      'palette': 'slate',
      'tag_colors': {'work': 'blue'},
    });
    expect(old.tagColors['work'], TagColor.blue);
    expect(old.tagDisplays, isEmpty);
    expect(old.journalView, JournalViewPreferences.focused);
    final unknown = AppAppearance.fromJson({
      ...old.toJson(),
      'tag_display': {'work': 'routine', 'future': 'unknown'},
      'journal_view': {'show_routine': true, 'show_undefined': 42},
    });
    expect(unknown.tagDisplays, {'work': TagDisplay.routine});
    expect(unknown.journalView, JournalViewPreferences.fullDay);
  });

  test('legacy custom choices normalize and new choices round trip', () {
    for (final routine in [false, true]) {
      for (final undefined in [false, true]) {
        final migrated = JournalViewPreferences.fromJson({
          'show_routine': routine,
          'show_undefined': undefined,
        });
        expect(
          migrated.preset,
          routine ? JournalViewPreset.fullDay : JournalViewPreset.focused,
        );
        expect(migrated.showUnclassified, isTrue);
      }
    }
    final hidden = JournalViewPreferences.fullDay.copyWith(
      showUnclassified: false,
    );
    expect(JournalViewPreferences.fromJson(hidden.toJson()), hidden);
    expect(hidden.foldsEmptyTime, isFalse);
    expect(JournalViewPreferences.focused.foldsEmptyTime, isTrue);
    expect(
      JournalViewPreferences.fromJson({
        'preset': 'future',
        'show_unclassified': 42,
      }),
      JournalViewPreferences.focused,
    );
  });

  test(
    'tag style and view changes survive reopening without record files',
    () async {
      final directory = await Directory('.test-artifacts').createTemp('view-');
      addTearDown(() => directory.delete(recursive: true));
      final store = await AppearanceStore.open(directory);
      final controller = AppearanceController(store);
      addTearDown(controller.dispose);
      await controller.setTagStyle(
        'sleep',
        TagColor.purple,
        TagDisplay.routine,
      );
      final view = JournalViewPreferences.fullDay.copyWith(
        showUnclassified: false,
      );
      await controller.setJournalView(view);
      await controller.setPalette(AppPalette.rose);
      final reopened = await AppearanceStore.open(directory);
      expect(reopened.state.tagDisplays, {'sleep': TagDisplay.routine});
      expect(reopened.state.tagColors, {'sleep': TagColor.purple});
      expect(reopened.state.journalView, view);
      expect(reopened.state.palette, AppPalette.rose);
      expect((await directory.list().toList()).length, 1);
      await controller.setTagStyle('sleep', null, null);
      expect(controller.state.tagDisplays, isEmpty);
      expect(controller.state.tagColors, isEmpty);
      expect(controller.state.journalView, view);
    },
  );

  test('failed combined style write keeps both previous properties', () async {
    final directory = await Directory(
      '.test-artifacts',
    ).createTemp('view-fail-');
    addTearDown(() => directory.delete(recursive: true));
    var fail = false;
    final store = await AppearanceStore.open(
      directory,
      writer: (file, bytes) async {
        if (fail) throw const FileSystemException('synthetic failure');
        await file.writeAsBytes(bytes, flush: true);
      },
    );
    final controller = AppearanceController(store);
    addTearDown(controller.dispose);
    await controller.setTagStyle('sleep', TagColor.orange, TagDisplay.normal);
    final before = await store.file.readAsString();
    fail = true;
    await expectLater(
      controller.setTagStyle('sleep', TagColor.teal, TagDisplay.routine),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.state.tagColors['sleep'], TagColor.orange);
    expect(controller.state.tagDisplays['sleep'], TagDisplay.normal);
    expect(await store.file.readAsString(), before);
    await expectLater(
      controller.setJournalView(JournalViewPreferences.fullDay),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.state.journalView, JournalViewPreferences.focused);
    await expectLater(
      controller.setJournalView(
        JournalViewPreferences.focused.copyWith(showUnclassified: false),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.state.journalView.showUnclassified, isTrue);
  });
}
