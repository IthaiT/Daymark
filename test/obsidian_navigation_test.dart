import 'dart:io';

import 'package:daymark/data/obsidian_navigation.dart';
import 'package:daymark/domain/obsidian.dart';
import 'package:daymark/ui/obsidian_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/obsidian_ids.dart';

void main() {
  group('vault link resolution', () {
    late Directory directory;
    late Directory vault;
    late Directory items;
    setUp(() async {
      directory = await (await Directory(
        '.test-artifacts',
      ).create()).createTemp('obsidian-navigation-');
      vault = await Directory('${directory.path}/中文 Vault & Notes').create();
      await Directory('${vault.path}/.obsidian').create();
      items = await Directory('${vault.path}/Daymark').create();
    });
    tearDown(() async => directory.delete(recursive: true));

    test(
      'short links to other folders are delegated to the vault index',
      () async {
        const name = '20261107-如何讲好背景故事';
        final folder = await Directory(
          '${vault.path}/知识/表达',
        ).create(recursive: true);
        await File('${folder.path}/$name.md').writeAsString('合成笔记');
        final uri = await resolveObsidianNoteUri(items.path, name);
        // Obsidian takes the vault-relative remainder as its file parameter;
        // the short name can be resolved anywhere in the vault, not just here.
        final target = File('${vault.path}/$name.md');
        expect(await target.exists(), false);
        expect(uri.queryParameters['path'], target.absolute.path);
        expect(uri.scheme, 'obsidian');
        expect(uri.host, 'open');
      },
    );

    test(
      'an exact local source keeps priority over same-named notes',
      () async {
        final local = await File('${items.path}/同名.md').writeAsString('本地');
        await File('${vault.path}/同名.md').writeAsString('仓库根目录');
        final uri = await resolveObsidianNoteUri(items.path, '同名#^block|别名');
        expect(uri.queryParameters['path'], '${local.absolute.path}#^block');
      },
    );

    test(
      'vault-relative paths retain Unicode, spaces and heading anchors',
      () async {
        final folder = await Directory('${vault.path}/知识 & 经验').create();
        final note = await File(
          '${folder.path}/背景 故事.md',
        ).writeAsString('合成笔记');
        final uri = await resolveObsidianNoteUri(
          items.path,
          r'知识 & 经验\背景 故事.md#怎么讲 + 为什么|别名',
        );
        expect(uri.queryParameters['path'], '${note.absolute.path}#怎么讲 + 为什么');
        expect(uri.fragment, isEmpty);
      },
    );

    test('a configured subfolder still selects the enclosing vault', () async {
      final nested = await Directory('${items.path}/子目录').create();
      final uri = await resolveObsidianNoteUri(nested.path, '其他笔记');
      expect(
        uri.queryParameters['path'],
        File('${vault.path}/其他笔记.md').absolute.path,
      );
    });

    test('without a vault only existing local files can open', () async {
      final standalone = await Directory(
        '${directory.path}/standalone',
      ).create();
      final note = await File('${standalone.path}/本地.md').writeAsString('合成笔记');
      expect(
        (await resolveObsidianNoteUri(
          standalone.path,
          '本地',
        )).queryParameters['path'],
        note.absolute.path,
      );
      await expectLater(
        resolveObsidianNoteUri(standalone.path, '不存在'),
        throwsFormatException,
      );
      await expectLater(
        resolveObsidianNoteUri(items.path, '#只有锚点'),
        throwsFormatException,
      );
    });
  });

  test(
    'official path URI round trips Unicode, spaces, ampersands and block anchors',
    () {
      const path = r'E:\Vault & Notes\Daymark\中文 事项.md#^stable-id';
      final uri = obsidianOpenUri(path);
      expect(uri.scheme, 'obsidian');
      expect(uri.host, 'open');
      expect(Uri.parse(uri.toString()).queryParameters['path'], path);
      expect(uri.fragment, isEmpty);
      expect(uri.toString(), contains('%20'));
      expect(uri.toString(), isNot(contains('+')));
    },
  );
  test('item targets use the same complete identity as the source', () {
    final parsed = parseObsidian({
      'A.md': '- [ ] 原生 ${obsidianId(1)}',
    }, directory: 'synthetic');
    final item = parsed.items.values.singleWhere((item) => item.name == '原生');
    expect(obsidianItemTarget(item), 'A.md#${obsidianId(1)}');
  });
  testWidgets(
    'wikilink aliases open their actual destination and current-note anchors',
    (tester) async {
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObsidianText(
              text: '说明 [[目标#标题|显示别名]]，[[#^块|当前事项]]',
              directory: 'synthetic/Daymark',
              sourcePath: '当前.md',
              openNote: (directory, target) async {
                expect(directory, 'synthetic/Daymark');
                opened.add(target);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rich = tester.widget<SelectableText>(find.byType(SelectableText));
      final spans = rich.textSpan!.children!
          .whereType<TextSpan>()
          .where((s) => s.recognizer != null)
          .toList();
      expect(spans.map((s) => s.text), ['显示别名', '当前事项']);
      for (final span in spans) {
        (span.recognizer! as TapGestureRecognizer).onTap!();
        await tester.pump();
      }
      expect(opened, ['目标#标题', '当前.md#^块']);
    },
  );
}
