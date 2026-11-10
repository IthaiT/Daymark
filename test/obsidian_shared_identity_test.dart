import 'package:daymark/domain/obsidian.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/obsidian_ids.dart';

String note(
  int identity,
  String body, {
  String? parent,
  List<String> tags = const [],
}) =>
    '---\ndaymark-id: "${obsidianId(identity)}"\n'
    '${parent == null ? '' : 'parent: "[[$parent]]"\n'}'
    'tags: [${tags.join(', ')}]\n---\n$body';

ObsidianImport parse(Map<String, String> documents) =>
    parseObsidian(documents, directory: 'synthetic/Daymark');

void main() {
  test('compatible repeated parents merge their different children', () {
    final shared = obsidianId(2);
    final result = parse({
      '计划.md': note(
        1,
        '- [ ] 准备面试 | 描述 | 结果 $shared\n'
        '  - [ ] 修改简历 ${obsidianId(3)}\n'
        '- [ ] 准备面试 | 描述 | 结果 $shared\n'
        '  - [ ] 练习面试 ${obsidianId(4)}\n',
      ),
    });
    expect(result.items.length, 4);
    expect(result.items[shared]!.name, '准备面试');
    expect(result.items[shared]!.parentId, obsidianId(1));
    expect(
      result.items.values
          .where((item) => item.parentId == shared)
          .map((item) => item.name),
      ['修改简历', '练习面试'],
    );
  });

  test(
    'repeated descendants merge recursively without collapsing different IDs',
    () {
      final result = parse({
        '计划.md': note(
          1,
          '- [ ] 父事项 ${obsidianId(2)}\n'
          '  - [ ] 子事项 ${obsidianId(3)}\n'
          '    - [ ] 相同名称 ${obsidianId(4)}\n'
          '- [ ] 父事项 ${obsidianId(2)}\n'
          '  - [ ] 子事项 ${obsidianId(3)}\n'
          '    - [ ] 相同名称 ${obsidianId(5)}\n',
        ),
      });
      expect(result.items.length, 5);
      expect(result.items[obsidianId(3)]!.parentId, obsidianId(2));
      expect(
        result.items.values
            .where((item) => item.parentId == obsidianId(3))
            .map((item) => item.id)
            .toSet(),
        {obsidianId(4), obsidianId(5)},
      );
    },
  );

  test(
    'location, indentation and ignored Tasks metadata do not define identity',
    () {
      final source = note(
        1,
        '  - [ ] 事项 | 描述 | 结果 📅 2026-11-10 ${obsidianId(2)}\n'
        '\n- [ ] 事项 | 描述 | 结果 [due:: 2026-12-01] <!-- 注释 --> ${obsidianId(2)}\n',
      );
      final result = parse({'计划.md': source});
      expect(result.items.length, 2);
      expect(result.items[obsidianId(2)]!.objective, '描述');
      expect(result.items[obsidianId(2)]!.outcome, '结果');
      expect(result.documents['计划.md'], source);
    },
  );

  test(
    'tag order, repetition and case follow existing tag-name comparison',
    () {
      final result = parse({
        '计划.md': note(
          1,
          '- [ ] 事项 #研发 #Test ${obsidianId(2)}\n'
          '- [ ] 事项 #TEST #研发 #研发 ${obsidianId(2)}\n',
        ),
      });
      expect(result.items.length, 2);
      expect(result.tagNames[obsidianId(2)], ['研发', 'Test']);
    },
  );

  test(
    'note and inline occurrences resolve the same parent and union children across files',
    () {
      final documents = {
        '项目.md': note(
          1,
          '- [ ] 共享 #研发 ${obsidianId(2)}\n'
          '  - [ ] 内联子事项 ${obsidianId(3)}\n',
          tags: ['主业'],
        ),
        '共享.md': note(
          2,
          '- [ ] 文件子事项 ${obsidianId(4)}\n',
          parent: '目录/项目|别名',
          tags: ['研发'],
        ),
      };
      final first = parse(documents);
      final reversed = parse(
        Map.fromEntries(documents.entries.toList().reversed),
      );
      expect(first.items.length, 4);
      expect(first.items, reversed.items);
      expect(first.tagNames, reversed.tagNames);
      expect(first.items[obsidianId(2)]!.parentId, obsidianId(1));
      expect(first.items[obsidianId(2)]!.source!.kind, 'file');
      expect(first.items[obsidianId(2)]!.source!.path, '共享.md');
      for (final child in [3, 4]) {
        expect(first.items[obsidianId(child)]!.parentId, obsidianId(2));
      }
    },
  );

  for (final field in [
    ('名称', '- [ ] 事项 | 描述 | 结果', '- [ ] 其他名称 | 描述 | 结果'),
    ('描述', '- [ ] 事项 | 描述 | 结果', '- [ ] 事项 | 其他描述 | 结果'),
    ('结果', '- [ ] 事项 | 描述 | 结果', '- [ ] 事项 | 描述 | 其他结果'),
    ('状态', '- [ ] 事项 | 描述 | 结果', '- [/] 事项 | 描述 | 结果'),
    ('完成日期', '- [x] 事项 ✅ 2026-11-09', '- [x] 事项 ✅ 2026-11-10'),
    ('自身标签', '- [ ] 事项 #研发', '- [ ] 事项 #客户'),
  ]) {
    test('${field.$1} mismatch remains a located conflict', () {
      final identity = obsidianId(2);
      expect(
        () => parse({
          '计划.md': note(1, '${field.$2} $identity\n${field.$3} $identity\n'),
        }),
        throwsA(
          isA<ObsidianDuplicateIdException>()
              .having(
                (error) => error.message,
                'difference',
                contains('差异：${field.$1}'),
              )
              .having(
                (error) => error.message,
                'source',
                contains('计划.md 第 5 行'),
              )
              .having(
                (error) => error.message,
                'other source',
                contains('计划.md 第 6 行'),
              ),
        ),
      );
    });
  }

  test('equal parent titles with different parent IDs remain a conflict', () {
    ObsidianImport result() => parse({
      '计划.md': note(
        1,
        '- [ ] 同名父事项 ${obsidianId(3)}\n'
        '  - [ ] 共享 ${obsidianId(2)}\n'
        '- [ ] 同名父事项 ${obsidianId(4)}\n'
        '  - [ ] 共享 ${obsidianId(2)}\n',
      ),
    });
    expect(
      result,
      throwsA(
        isA<ObsidianDuplicateIdException>()
            .having(
              (error) => error.message,
              'parent mismatch',
              contains('差异：父事项'),
            )
            .having(
              (error) => error.message,
              'first parent',
              contains(obsidianId(3)),
            )
            .having(
              (error) => error.message,
              'second parent',
              contains(obsidianId(4)),
            ),
      ),
    );
  });

  test('matching contents under different file parents still conflict', () {
    expect(
      () => parse({
        'A.md': note(1, '- [ ] 共享 ${obsidianId(3)}\n'),
        'B.md': note(2, '- [ ] 共享 ${obsidianId(3)}\n'),
      }),
      throwsA(
        isA<ObsidianDuplicateIdException>().having(
          (error) => error.message,
          'parent mismatch',
          contains('差异：父事项'),
        ),
      ),
    );
  });

  test('compatible parents do not hide a conflicting shared child', () {
    expect(
      () => parse({
        '计划.md': note(
          1,
          '- [ ] 父事项 ${obsidianId(2)}\n'
          '  - [ ] 子事项 ${obsidianId(3)}\n'
          '- [ ] 父事项 ${obsidianId(2)}\n'
          '  - [ ] 改名后的子事项 ${obsidianId(3)}\n',
        ),
      }),
      throwsA(
        isA<ObsidianDuplicateIdException>()
            .having(
              (error) => error.message,
              'child identity',
              contains('ID：${obsidianId(3)}'),
            )
            .having((error) => error.message, 'difference', contains('差异：名称')),
      ),
    );
  });

  test('merging compatible occurrences still rejects cycles', () {
    expect(
      () => parse({
        'A.md': note(1, '- [ ] B ${obsidianId(2)}\n', parent: 'B'),
        'B.md': note(2, '- [ ] A ${obsidianId(1)}\n', parent: 'A'),
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'cycle',
          contains('自己或自己的子事项'),
        ),
      ),
    );
  });
}
