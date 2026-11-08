import 'package:daymark/data/obsidian_navigation.dart';
import 'package:daymark/domain/obsidian.dart';
import 'package:daymark/ui/obsidian_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/obsidian_ids.dart';

void main() {
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
