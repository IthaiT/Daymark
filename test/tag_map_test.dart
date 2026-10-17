import 'dart:io';

import 'package:daymark/application/journal_controller.dart';
import 'package:daymark/application/tag_map_controller.dart';
import 'package:daymark/data/atomic_file.dart';
import 'package:daymark/data/store.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/tag_tree.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _root(List<Map<String, Object?>> children) => {
  'id': tagTreeRootId,
  'name': tagTreeRootName,
  'children': children,
};

Map<String, Object?> _node(
  String id,
  String name, [
  List<Map<String, Object?>> children = const [],
]) => {'id': id, 'name': name, 'children': children};

Map<String, Object?> _fullTree({
  List<Map<String, Object?>>? workChildren,
  List<Map<String, Object?>>? lifeChildren,
}) => _root([
  _node(
    'work',
    '主业',
    workChildren ??
        [
          _node('embedded', '嵌入式', [_node('linux', 'Linux')]),
        ],
  ),
  _node('side', '副业', [
    _node('agent', 'Agent', [
      _node('learning', '学习', [_node('course', '某一门课程')]),
    ]),
  ]),
  _node('explore', '探索'),
  _node('life', '生活', lifeChildren ?? [_node('rest', '休息')]),
]);

void main() {
  group('标签树映射', () {
    test('保留稳定 ID，并按 Daymark 现有规则排序同级标签', () {
      final tags = [
        const Tag('work', '主业'),
        const Tag('embedded', '嵌入式', 'work'),
        const Tag('linux', 'Linux', 'embedded'),
        const Tag('a', 'A'),
        const Tag('b', 'b'),
      ];
      final tree = TagTree.fromTags(tags);
      expect(tree.root.id, tagTreeRootId);
      expect(tree.root.name, tagTreeRootName);
      expect(tree.children.map((node) => node.id), ['a', 'b', 'work']);
      expect(tree.children.last.children.single.id, 'embedded');
      expect(tree.children.last.children.single.children.single.id, 'linux');
      expect(tree.children.map((node) => node.name), ['A', 'b', '主业']);
    });

    test('整树往返不改变标签 ID、名称和父子关系', () {
      final tags = {for (final tag in defaultTags) tag.id: tag};
      final plan = TagTree.fromTags(tags.values).toTagMap(tags);
      expect(plan.tags, tags);
      expect(plan.assignedIds, isEmpty);
    });

    test('新节点保存时分配稳定 ID，已有节点保持原 ID', () {
      final tree = TagTree.fromJson(
        _root([
          _node('work', '主业', [_node('new:abc', '新标签')]),
          _node('side', '副业'),
        ]),
      );
      final plan = tree.toTagMap({
        'work': const Tag('work', '主业'),
        'side': const Tag('side', '副业'),
      }, createId: () => 'generated');
      expect(plan.assignedIds, {'new:abc': 'generated'});
      expect(plan.tags.keys, containsAll(['work', 'side', 'generated']));
      expect(plan.tags['generated']!.parentId, 'work');
      expect(plan.tags['generated']!.name, '新标签');
      expect(plan.tags.containsKey('new:abc'), isFalse);
    });

    test('新节点 ID 与已有标签冲突时重试', () {
      final tree = TagTree.fromJson(_root([_node('new:x', '新标签')]));
      var attempts = 0;
      final plan = tree.toTagMap({
        'taken': const Tag('taken', '已有'),
      }, createId: () => ++attempts == 1 ? 'taken' : 'fresh');
      expect(attempts, 2);
      expect(plan.assignedIds['new:x'], 'fresh');
      expect(plan.tags.containsKey('fresh'), isTrue);
      expect(plan.tags.containsKey('taken'), isFalse);
    });

    test('移动节点只改变父标签，事件关联的 ID 不变', () {
      final tags = {for (final tag in defaultTags) tag.id: tag};
      final moved = TagTree.fromJson(
        _root([
          _node('work', '主业', [_node('embedded', '嵌入式')]),
          _node('side', '副业', [_node('linux', 'Linux')]),
        ]),
      );
      final plan = moved.toTagMap(tags);
      expect(plan.tags['linux']!.parentId, 'side');
      expect(plan.tags['linux']!.id, 'linux');
    });

    test('拒绝损坏、重复、空名称和未知标签的树', () {
      for (final value in <Object?>[
        null,
        _root([])..['id'] = 'other',
        _root([_node(tagTreeRootId, '标签')]),
        _root([_node('a', 'A'), _node('a', 'B')]),
        _root([_node('a', '   ')]),
        _root([_node('new:', '新标签')]),
        _root([
          _node('a', 'A', [_node('a', 'B')]),
        ]),
        {'id': tagTreeRootId, 'name': tagTreeRootName, 'children': 'x'},
      ]) {
        expect(() => TagTree.fromJson(value), throwsFormatException);
      }
      expect(
        () => TagTree.fromJson(_root([_node('missing', '未知')])).toTagMap({}),
        throwsFormatException,
      );
    });
  });

  group('标签整表保存', () {
    late Directory directory;
    late Store store;
    var failWrites = false;
    setUp(() async {
      directory = await (await Directory(
        '.test-artifacts',
      ).create()).createTemp('tag-map-');
      failWrites = false;
      store = await Store.open(
        directory,
        writer: (file, bytes) async {
          if (failWrites) throw const FileSystemException('模拟写入失败');
          await AtomicFile.write(file, bytes);
        },
      );
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('移动标签后原子写入并保留事件关联', () async {
      final event = Event(
        'event',
        '学习',
        'linux',
        DateTime.utc(2026, 10, 7, 9),
        DateTime.utc(2026, 10, 7, 10),
      );
      await store.saveEvent(event);
      final tags = Map.of(store.tags);
      tags['linux'] = const Tag('linux', 'Linux', 'life');
      await store.replaceTags(tags);
      final reopened = await Store.open(directory);
      expect(reopened.tags['linux']!.parentId, 'life');
      expect(reopened.events['event']!.tagId, 'linux');
      expect(reopened.tags['linux']!.id, 'linux');
    });

    test('删除仍有事件或重名同级的标签会被拒绝', () async {
      final before = await store.tagsFile.readAsBytes();
      await store.saveEvent(
        Event(
          'event',
          '学习',
          'linux',
          DateTime.utc(2026, 10, 7, 9),
          DateTime.utc(2026, 10, 7, 10),
        ),
      );
      final removed = Map.of(store.tags)..remove('linux');
      await expectLater(store.replaceTags(removed), throwsFormatException);
      expect(await store.tagsFile.readAsBytes(), before);
      expect(store.tags.containsKey('linux'), isTrue);

      final duplicate = Map.of(store.tags);
      duplicate['extra'] = const Tag('extra', '嵌入式', 'work');
      await expectLater(store.replaceTags(duplicate), throwsFormatException);
      expect(await store.tagsFile.readAsBytes(), before);
    });

    test('写入失败会保留原文件和内存状态', () async {
      final before = await store.tagsFile.readAsBytes();
      final oldTags = store.tags;
      failWrites = true;
      final tags = Map.of(store.tags);
      tags['work'] = const Tag('work', '主业改名');
      await expectLater(
        store.replaceTags(tags),
        throwsA(isA<FileSystemException>()),
      );
      expect(store.tags, oldTags);
      expect(await store.tagsFile.readAsBytes(), before);
    });
  });

  group('导图控制器', () {
    late Directory directory;
    late Store store;
    late JournalController journal;
    late TagMapController controller;
    var failWrites = false;
    setUp(() async {
      directory = await (await Directory(
        '.test-artifacts',
      ).create()).createTemp('tag-map-controller-');
      failWrites = false;
      store = await Store.open(
        directory,
        writer: (file, bytes) async {
          if (failWrites) throw const FileSystemException('模拟写入失败');
          await AtomicFile.write(file, bytes);
        },
      );
      journal = JournalController(
        store,
        day: DateTime.utc(2026, 10, 7),
        clock: () => DateTime.utc(2026, 10, 7, 12),
      );
      await journal.initialize();
      controller = TagMapController(journal);
    });
    tearDown(() async {
      controller.dispose();
      journal.dispose();
      await directory.delete(recursive: true);
    });

    test('编辑先在内存中保留，保存后才写入磁盘并排序', () async {
      final before = await store.tagsFile.readAsString();
      controller.applyFromWeb(
        _fullTree(
          workChildren: [
            _node('embedded', '嵌入式', [_node('linux', 'Linux')]),
            _node('new:child', '新子标签'),
          ],
        ),
      );
      expect(controller.dirty, isTrue);
      expect(await store.tagsFile.readAsString(), before);

      final saved = await controller.save();
      expect(controller.dirty, isFalse);
      expect(store.tags.containsKey('new:child'), isFalse);
      final added = store.tags.values.singleWhere((tag) => tag.name == '新子标签');
      expect(added.parentId, 'work');
      expect(saved.children.map((node) => node.id), [
        'work',
        'side',
        'explore',
        'life',
      ]);
      final reopened = await Store.open(directory);
      expect(reopened.tags.values.where((tag) => tag.name == '新子标签'), [added]);
    });

    test('移动标签保存后层级变更且草稿清空', () async {
      controller.applyFromWeb(
        _fullTree(
          workChildren: [_node('embedded', '嵌入式')],
          lifeChildren: [_node('rest', '休息'), _node('linux', 'Linux')],
        ),
      );
      expect(controller.dirty, isTrue);
      await controller.save();
      expect(store.tags['linux']!.parentId, 'life');
      expect(controller.dirty, isFalse);
      expect(
        controller.draft.children
            .expand((node) => node.children)
            .map((node) => node.id),
        contains('linux'),
      );
    });

    test('保存失败保留草稿与旧文件', () async {
      final before = await store.tagsFile.readAsBytes();
      controller.applyFromWeb(
        _fullTree(
          workChildren: [
            _node('embedded', '嵌入式', [_node('linux', 'Linux')]),
            _node('new:child', '未保存'),
          ],
        ),
      );
      failWrites = true;
      await expectLater(controller.save(), throwsA(isA<FileSystemException>()));
      expect(controller.dirty, isTrue);
      expect(controller.draft.children.first.name, '主业');
      expect(await store.tagsFile.readAsBytes(), before);
    });

    test('删除规则与事件、子标签和虚拟根节点一致', () async {
      await store.saveEvent(
        Event(
          'event',
          '学习',
          'linux',
          DateTime.utc(2026, 10, 7, 9),
          DateTime.utc(2026, 10, 7, 10),
        ),
      );
      expect(controller.deleteBlocker(tagTreeRootId), '虚拟根节点不能删除。');
      expect(controller.deleteBlocker('embedded'), '请先删除或移动它的子标签。');
      expect(controller.deleteBlocker('linux'), contains('1 个事件'));
      expect(controller.deleteBlocker('rest'), isNull);
    });

    test('同步侧栏新增标签时保留未保存的导图编辑', () async {
      final tree = _fullTree()['children']! as List<Map<String, Object?>>;
      controller.applyFromWeb(
        _root([
          _node('work', '主业改名', [
            _node('embedded', '嵌入式', [_node('linux', 'Linux')]),
            _node('new:child', '未保存'),
          ]),
          ...tree.skip(1),
        ]),
      );
      await journal.saveTag('导图外新增', null);
      expect(controller.syncFromStore(), isTrue);
      final names = controller.draft.children.map((node) => node.name);
      expect(names, contains('导图外新增'));
      expect(names, contains('主业改名'));
      final saved = await controller.save();
      expect(
        saved.children.map((node) => node.name),
        containsAll(['导图外新增', '主业改名']),
      );
      expect(
        store.tags.values.singleWhere((tag) => tag.name == '导图外新增').parentId,
        isNull,
      );
    });

    test('已解析的树可直接应用到草稿', () {
      final tree = TagTree.fromJson(_fullTree());
      controller.applyTree(tree);
      expect(controller.draft.sameAs(tree), isTrue);
      expect(controller.dirty, isFalse);
    });

    test('同级重名校验沿用 Unicode 大小写折叠', () {
      expect(controller.validateName(null, '  '), '请输入标签名称。');
      expect(controller.validateName(null, '新一级'), isNull);
      expect(controller.validateName(null, '主业', ignoreId: 'work'), isNull);
      expect(controller.validateName('work', '嵌入式'), '同一个父标签下不能有重名标签。');
      expect(controller.validateName('embedded', 'LINUX'), '同一个父标签下不能有重名标签。');
      expect(controller.validateName('work', 'LINUX'), isNull);
    });
  });
}
