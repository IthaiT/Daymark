import 'dart:io';

import 'package:daymark/application/appearance_controller.dart';
import 'package:daymark/data/appearance_store.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/appearance.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/tag_colors.dart';
import 'package:daymark/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => Directory('.test-artifacts').create(recursive: true));

  test(
    'stored project colours survive rename, reparent and new projects',
    () async {
      final directory = await Directory(
        '.test-artifacts',
      ).createTemp('fixed-colors-');
      addTearDown(() => directory.delete(recursive: true));
      final store = await AppearanceStore.open(directory);
      final controller = AppearanceController(store);
      addTearDown(controller.dispose);
      const tags = [
        Tag('work', '主业', null),
        Tag('life', '生活', null),
        Tag('thinking', 'Thinking', null),
        Tag('daymark', 'Daymark', 'thinking'),
        Tag('agent', 'ai agent', 'thinking'),
      ];
      await controller.ensureRootColors(tags);
      final roots = {...controller.state.tagColors};
      final daymark = suggestTagColor(tags, roots);
      await controller.setTagStyle('daymark', daymark, TagDisplay.normal);
      final agent = suggestTagColor(tags, controller.state.tagColors);
      expect(agent, isNot(daymark));
      await controller.setTagStyle('agent', agent, TagDisplay.normal);
      await controller.ensureRootColors([
        ...tags.where((tag) => tag.id != 'thinking'),
        const Tag('thinking', '改名并移动', 'work'),
        const Tag('new', '新项目', null),
      ]);
      for (final entry in roots.entries) {
        expect(controller.state.tagColors[entry.key], entry.value);
      }
      expect(controller.state.tagColors['daymark'], daymark);
      final reopened = await AppearanceStore.open(directory);
      expect(reopened.state.tagColors, controller.state.tagColors);
      await controller.setTagStyle('daymark', daymark, TagDisplay.routine);
      expect(controller.state.tagColors['daymark'], daymark);
    },
  );

  test(
    'automatic colour assignment does not overwrite corrupt preferences',
    () async {
      final directory = await Directory(
        '.test-artifacts',
      ).createTemp('colors-bad-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/appearance.json');
      await file.writeAsString('{broken');
      final store = await AppearanceStore.open(directory);
      final controller = AppearanceController(store);
      addTearDown(controller.dispose);
      await controller.ensureRootColors(const [Tag('work', '主业', null)]);
      expect(await file.readAsString(), '{broken');
      expect(controller.state.tagColors, isEmpty);
    },
  );

  test(
    'inherited accent stays unchanged after sibling insertion and sorting',
    () async {
      final directory = await Directory(
        '.test-artifacts',
      ).createTemp('same-hue-');
      addTearDown(() => directory.delete(recursive: true));
      final store = await Store.open(directory);
      final before = tagDotFor(store, 'linux', const {});
      expect(before, tagDotFor(store, 'work', const {}));
      await store.saveTag('AAA', 'work');
      await store.saveTag('ZZZ', 'work', id: 'embedded');
      expect(tagDotFor(store, 'linux', const {}), before);
      final event = Event(
        'sleep',
        '睡觉',
        'life',
        DateTime.utc(2026),
        DateTime.utc(2026, 1, 1, 8),
      );
      final (fill, ink) = eventColorsFor(
        store,
        event,
        const {},
        tagDisplays: const {'life': TagDisplay.routine},
      );
      expect(fill, Colors.grey[200]);
      expect(
        (ink.computeLuminance() + .05) < (fill.computeLuminance() + .05),
        isTrue,
      );
    },
  );
}
