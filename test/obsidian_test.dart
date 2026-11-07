import 'package:daymark/domain/obsidian.dart';
import 'package:daymark/domain/item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var counter = 0;
  ObsidianImport parse(Map<String, String> docs) => parseObsidian(
    docs,
    directory: 'vault/Daymark',
    newId: () => 'test-${counter++}',
  );
  test('YAML parents, inherited tags, fields and all four states', () {
    final result = parse({
      '大事项.md':
          '---\nparent:\ntags: [主业, 副业]\n---\n- [ ] ⏫ 名称 | 描述\n\t- [/] 子事项 | | 结果 📅 2026-12-01 #task\n\t\t- [-] 取消\n- [x] 完成 ✅ 2026-11-08\n',
      '小事项.md': '---\nparent: [[大事项]]\ntags:\n  - 学习\n---\n- [ ] 任务\n',
    });
    final nodes = result.items.values.toList();
    Item node(String name) => nodes.singleWhere((n) => n.name == name);
    expect(node('小事项').parentId, node('大事项').id);
    expect(result.tagNames[node('大事项').id], ['主业', '副业']);
    expect(node('子事项').parentId, node('名称').id);
    expect(node('取消').parentId, node('子事项').id);
    expect(node('名称').objective, '描述');
    expect(node('子事项').objective, '');
    expect(node('子事项').outcome, '结果');
    expect(node('子事项').status, ItemStatus.paused);
    expect(node('取消').status, ItemStatus.dropped);
    expect(node('完成').status, ItemStatus.done);
    expect(node('名称').isTodo, true);
    expect(node('子事项').isTodo, false);
    for (final n in nodes) {
      expect(Item.fromJson(n.toJson()), n);
    }
  });
  test('IDs survive renames, reindentation and cross-file moves', () {
    final first = parse({'A.md': '- [ ] 名称 | 描述\n', 'B.md': ''});
    final task = first.items.values.singleWhere((n) => n.name == '名称');
    final root = first.items.values.singleWhere((n) => n.name == 'A');
    final line = first.documents['A.md']!
        .split('\n')
        .singleWhere((l) => l.startsWith('-'));
    final second = parse({
      '重命名.md': first.documents['A.md']!.replaceAll('$line\n', ''),
      'B.md': '${first.documents['B.md']}\n${line.replaceFirst('名称', '新名称')}\n',
    });
    expect(second.items[task.id]!.name, '新名称');
    expect(
      second.items[task.id]!.parentId,
      second.items.values.singleWhere((n) => n.name == 'B').id,
    );
    expect(second.items[root.id]!.name, '重命名');
    expect(parse(second.documents).documents, second.documents);
  });
  test(
    'preserves CRLF, BOM, fenced examples, wiki aliases and escaped pipes',
    () {
      final result = parse({
        'A.md':
            '\uFEFF---\r\ntags: 主业\r\n---\r\n```md\r\n- [ ] 示例\r\n```\r\n- [ ] [[链接|别名]] | a\\|b | `x|y` 🔁 every week\r\n',
      });
      expect(result.items.length, 2);
      final task = result.items.values.singleWhere(
        (n) => n.source!.kind == 'task',
      );
      expect(task.name, '[[链接|别名]]');
      expect(task.objective, 'a|b');
      expect(task.outcome, '`x|y`');
      expect(result.documents['A.md']!.startsWith('\uFEFF---\r\n'), true);
      expect(
        result.documents['A.md']!.replaceAll('\r\n', '').contains('\n'),
        false,
      );
    },
  );
  test('filters official Tasks on-completion and Dataview fields', () {
    final result = parse({
      'A.md':
          '- [ ] 名称 (priority:: high) | 描述 | 结果 🏁 delete [due:: 2026-11-08]',
    });
    final task = result.items.values.singleWhere(
      (n) => n.source!.kind == 'task',
    );
    expect(task.name, '名称');
    expect(task.outcome, '结果');
  });
  test('invalid parent, cycles, duplicate IDs and malformed YAML fail', () {
    expect(
      () => parse({'A.md': '---\nparent: "[[B]]"\n---\n'}),
      throwsFormatException,
    );
    expect(
      () => parse({
        'A.md': '---\nparent: "[[B]]"\n---\n',
        'B.md': '---\nparent: "[[A]]"\n---\n',
      }),
      throwsFormatException,
    );
    expect(
      () => parse({
        'A.md': '- [ ] A <!-- daymark:same -->\n- [ ] B <!-- daymark:same -->',
      }),
      throwsFormatException,
    );
    expect(
      () => parse({'A.md': '---\ntags: [oops\n---\n'}),
      throwsA(isA<Exception>()),
    );
    expect(() => parse({'A.md': '- [ ] | description'}), throwsFormatException);
  });
  test('duplicate titles and empty done/cancel outcomes remain valid', () {
    final result = parse({'A.md': '- [x] 重复\n  - [ ] 子事项\n- [-] 重复'});
    validateItems(result.items);
    expect(result.items.length, 4);
  });
}
