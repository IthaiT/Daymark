import 'package:daymark/domain/obsidian.dart';
import 'package:daymark/domain/item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'support/obsidian_ids.dart';

void main() {
  var counter = 0;
  ObsidianImport parse(Map<String, String> docs) => parseObsidian(
    docs,
    directory: 'vault/Daymark',
    newId: () => obsidianId(counter++),
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
        .singleWhere((l) => l.startsWith('- ['));
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
        'A.md': '- [ ] A ${obsidianId(900)}\n- [ ] B ${obsidianId(900)}',
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
  group('duplicate identity source locations', () {
    String message(Map<String, String> documents) {
      try {
        parse(documents);
      } on ObsidianDuplicateIdException catch (error) {
        return error.message;
      }
      fail('Expected a duplicate identity error.');
    }

    test('same-name rows identify original lines before YAML is inserted', () {
      final id = obsidianId(900);
      final result = message({'计划.md': '- [ ] 准备面试 $id\n\n- [ ] 准备面试 $id\n'});
      expect(result, contains('事项「准备面试」— 计划.md 第 1 行'));
      expect(result, contains('事项「准备面试」— 计划.md 第 3 行'));
      expect(result, contains('原始文件和已保存数据均已保留'));
    });

    test('reports every location in every duplicate group across files', () {
      final first = obsidianId(901);
      final second = obsidianId(902);
      final result = message({
        '工作.md': '- [ ] 准备面试 $first\n- [ ] 修改简历 $second\n',
        '副本.md': '- [ ] 面试副本 $first\n- [ ] 简历副本 $second\n',
        '归档.md': '归档正文\n- [x] 面试归档 $first\n',
      });
      expect(result, contains('重复组 1：'));
      expect(result, contains('重复组 2：'));
      expect(result, contains('事项「准备面试」— 工作.md 第 1 行'));
      expect(result, contains('事项「修改简历」— 工作.md 第 2 行'));
      expect(result, contains('事项「面试副本」— 副本.md 第 1 行'));
      expect(result, contains('事项「简历副本」— 副本.md 第 2 行'));
      expect(result, contains('事项「面试归档」— 归档.md 第 2 行'));
      expect(result, contains('ID：$first'));
      expect(result, contains('ID：$second'));
    });

    test(
      'note properties and task rows report both names and property location',
      () {
        final id = obsidianId(903);
        final result = message({
          '原笔记.md': '\uFEFF---\r\n# 说明\r\n"daymark-id": "$id"\r\n---\r\n',
          '合并.md': '目标正文\n- [ ] 原笔记的副本 $id\n',
        });
        expect(result, contains('事项「原笔记」— 原笔记.md 第 3 行（daymark-id 属性）'));
        expect(result, contains('事项「原笔记的副本」— 合并.md 第 2 行'));
      },
    );

    test(
      'duplicate note properties point to each file, including multiline YAML',
      () {
        final id = obsidianId(904);
        final result = message({
          'A.md': '---\ndaymark-id: "$id"\n---\n',
          'B.md': '---\ndaymark-id:\n  "$id"\n---\n',
        });
        expect(result, contains('事项「A」— A.md 第 2 行（daymark-id 属性）'));
        expect(result, contains('事项「B」— B.md 第 3 行（daymark-id 属性）'));
      },
    );
  });
  test(
    'inline tags in every field belong to their task, not link or code text',
    () {
      final result = parse({
        'A.md':
            '---\ntags: [主业]\n---\n- [ ] #研发 名称 | 描述 #客户/甲 | #待确认 结果 #研发\n  - [ ] 子事项 #自己的标签\n- [ ] `#code` [[目标#标题]] \\#literal #123 | #有效_tag 描述\n',
      });
      final task = result.items.values.singleWhere((n) => n.name == '名称');
      expect(result.tagNames[task.id], ['研发', '客户/甲', '待确认']);
      expect(task.objective, '描述');
      expect(task.outcome, '结果');
      final child = result.items.values.singleWhere((n) => n.name == '子事项');
      expect(result.tagNames[child.id], ['自己的标签']);
      final literal = result.items.values.singleWhere(
        (n) => n.name.startsWith('`'),
      );
      expect(literal.name, '`#code` [[目标#标题]] \\#literal #123');
      expect(result.tagNames[literal.id], ['有效_tag']);
    },
  );
  test('note properties and task blocks contain the exact stored identity', () {
    final result = parse({'A.md': '- [ ] 名称 | 描述\n'});
    final root = result.items.values.singleWhere((n) => n.name == 'A');
    final task = result.items.values.singleWhere((n) => n.name == '名称');
    final document = result.documents['A.md']!;
    final properties = loadYaml(document.split('---')[1]) as YamlMap;
    expect(properties['daymark-id'], root.id);
    expect(document, contains('- [ ] 名称 | 描述 ${task.id}'));
    expect(obsidianBlockId(task.source!.raw), task.id);
    for (final id in result.items.keys) {
      expect(id, matches(r'^\^daymark-obsidian-[0-9a-f-]{36}$'));
    }
    expect(parse(result.documents).documents, result.documents);
    expect(
      parse(result.documents).items.keys.toSet(),
      result.items.keys.toSet(),
    );
  });

  test(
    'a note identity can be pasted unchanged into a task in another file',
    () {
      final first = parse({'跳槽.md': '- [ ] 修改简历\n', '主业.md': ''});
      final job = first.items.values.singleWhere((n) => n.name == '跳槽');
      final resume = first.items.values.singleWhere((n) => n.name == '修改简历');
      final line = resume.source!.raw;
      final merged = parse({
        '主业.md': '${first.documents['主业.md']}\n- [ ] 跳槽 ${job.id}\n    $line\n',
      });
      expect(merged.items[job.id]!.source!.kind, 'task');
      expect(
        merged.items[job.id]!.parentId,
        merged.items.values.singleWhere((n) => n.name == '主业').id,
      );
      expect(merged.items[resume.id]!.parentId, job.id);
      expect(merged.items[resume.id]!.source!.raw, '    $line');
      expect(parse(merged.documents).documents, merged.documents);
      // Splitting the subtree back into a note reuses the very same identity.
      final split = parse({
        '跳槽.md': '---\ndaymark-id: "${job.id}"\n---\n$line\n',
        '主业.md': first.documents['主业.md']!,
      });
      expect(split.items[job.id]!.source!.kind, 'file');
      expect(split.items[resume.id]!.parentId, job.id);
    },
  );

  test('new and blank notes store their identity only in frontmatter', () {
    for (final source in ['', '正文', '---\n---\n正文']) {
      final result = parse({'A.md': source});
      final root = result.items.values.single;
      final annotated = result.documents['A.md']!;
      expect(annotated, startsWith('---\n'));
      final properties = loadYaml(annotated.split('---')[1]) as YamlMap;
      expect(properties['daymark-id'], root.id);
      expect(annotated, endsWith(source.endsWith('正文') ? '正文' : ''));
      expect(parse(result.documents).documents, result.documents);
    }
  });

  test(
    'existing properties survive renames without rewriting unrelated YAML',
    () {
      final id = obsidianId(500);
      final source =
          "---\n# preserved\n'daymark-id': '$id' # identity\ntags: [主业]\nsummary: |\n  daymark-id: literal text\n---\n正文\n";
      final result = parse({'改名后.md': source});
      expect(result.items[id]!.name, '改名后');
      expect(result.documents['改名后.md'], source);
    },
  );

  test(
    'property insertion preserves BOM, CRLF, comments and existing task IDs',
    () {
      final taskId = obsidianId(501);
      final source =
          '\uFEFF---\r\n# keep this comment\r\ntags: [主业]\r\nsummary: |\r\n  daymark-id: literal\r\n---\r\n正文\r\n- [ ] 任务 $taskId\r\n';
      final result = parse({'A.md': source});
      final annotated = result.documents['A.md']!;
      expect(
        result.items[taskId]!.parentId,
        result.items.values.singleWhere((n) => n.name == 'A').id,
      );
      expect(annotated, contains('# keep this comment\r\ntags: [主业]'));
      expect(annotated, contains('  daymark-id: literal\r\n'));
      expect(annotated, contains('- [ ] 任务 $taskId\r\n'));
      expect(annotated, startsWith('\uFEFF---\r\n'));
      expect(annotated.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(parse(result.documents).documents, result.documents);
    },
  );

  test('blank properties and flow mappings retain unrelated YAML', () {
    final headers = [
      'daymark-id: # retained comment\ntags: [主业]',
      'daymark-id: null\ntags: [主业]',
      "'daymark-id': '' # retained comment\ntags: [主业]",
      'daymark-id: "  "\ntags: [主业]',
      '{tags: [主业]} # retained comment',
      '{daymark-id: null, tags: [主业]} # retained comment',
      '{}',
      '  tags: [主业]\n  summary: keep',
    ];
    for (final yaml in headers) {
      final result = parse({'A.md': '---\n$yaml\n---\n正文'});
      final annotated = result.documents['A.md']!;
      final values = loadYaml(annotated.split('---')[1]) as YamlMap;
      expect(values['daymark-id'], result.items.keys.single);
      if (yaml.contains('主业')) expect(values['tags'], ['主业']);
      if (yaml.contains('retained comment')) {
        expect(annotated, contains('# retained comment'));
      }
      expect(annotated, endsWith('---\n正文'));
      expect(parse(result.documents).documents, result.documents);
    }
  });

  test('old identity formats are rejected rather than migrated or aliased', () {
    for (final source in [
      '---\ndaymark-id: obsidian-00000000-0000-4000-8000-000000000001\n---\n',
      '---\ndaymark-id: "daymark-obsidian-00000000-0000-4000-8000-000000000001"\n---\n',
      '^daymark-file-obsidian-old\n',
      '<!-- daymark-file:old -->\n',
      '- [ ] 名称 <!-- daymark:old -->\n',
      '- [ ] 名称 ^existing-link\n',
      '- [ ] 名称 ^daymark-encoded-6f6c64\n',
      '- [ ] 名称 ^daymark-obsidian-invalid\n',
      '- [ ] 名称 ^daymark-invalid_id\n',
      '- [ ] 名称 ^daymark-invalid.id\n',
    ]) {
      expect(
        () => parse({'A.md': source}),
        throwsFormatException,
        reason: source,
      );
    }
  });

  test('invalid properties and duplicate identities fail before import', () {
    for (final value in [
      '123',
      'true',
      '[one, two]',
      '{id: one}',
      '"has spaces"',
    ]) {
      expect(
        () => parse({'A.md': '---\ndaymark-id: $value\n---\n'}),
        throwsFormatException,
      );
    }
    final id = obsidianId(700);
    for (final documents in [
      {
        'A.md': '---\ndaymark-id: "$id"\n---\n',
        'B.md': '---\ndaymark-id: "$id"\n---\n',
      },
      {'A.md': '---\ndaymark-id: "$id"\n---\n- [ ] 同一身份 $id\n'},
      {'A.md': '- [ ] 两个块 $id ${obsidianId(701)}\n'},
    ]) {
      expect(() => parse(documents), throwsFormatException);
    }
    expect(
      () => parse({'A.md': '---\ndaymark-id: "$id"\ndaymark-id: "$id"\n---\n'}),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'examples inside fences and comments remain literal; unclosed ones fail',
    () {
      final id = obsidianId(702);
      final source =
          '---\ndaymark-id: "$id"\n---\n```md\n^daymark-file-example\n```\n<!--\n<!-- daymark-file:comment-example -->\n';
      final result = parse({'A.md': source});
      expect(result.items.keys, [id]);
      expect(result.documents['A.md'], source);
      for (final source in ['```md\n示例', '<!--\n示例', '%%\n示例']) {
        expect(() => parse({'A.md': source}), throwsFormatException);
      }
    },
  );
}
