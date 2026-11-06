import 'package:daymark/domain/item.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Item> tree(List<Item> items) => {
  for (final item in items) item.id: item,
};

DateTime at(int minutes) =>
    DateTime.utc(2026, 11, 4).add(Duration(minutes: minutes));

void main() {
  test('sibling names must stay unique under the same parent', () {
    expect(
      () => validateItems(
        tree([
          const Item(id: 'a', name: '跳槽'),
          const Item(id: 'b', name: '跳槽'),
        ]),
      ),
      throwsFormatException,
    );
    validateItems(
      tree([
        const Item(id: 'a', name: '跳槽'),
        const Item(id: 'b', name: '跳槽', parentId: 'job'),
        const Item(id: 'job', name: '主业'),
      ]),
    );
  });

  test('cycles and missing ancestors are rejected', () {
    expect(
      () => validateItems(
        tree([
          const Item(id: 'a', name: 'a', parentId: 'b'),
          const Item(id: 'b', name: 'b', parentId: 'a'),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () =>
          validateItems(tree([const Item(id: 'a', name: 'a', parentId: 'x')])),
      throwsFormatException,
    );
  });

  test('a project tree nests as deep as you need', () {
    final items = tree([
      const Item(id: 'a', name: '项目'),
      const Item(id: 'b', name: '事项', parentId: 'a'),
      const Item(id: 'c', name: '细节', parentId: 'b'),
      const Item(id: 'd', name: '更深', parentId: 'c'),
      const Item(id: 'e', name: '还要更深', parentId: 'd'),
    ]);
    validateItems(items);
    expect(itemAncestors(items, 'e').map((item) => item.id), [
      'a',
      'b',
      'c',
      'd',
    ]);
    expect(orderedItems(items).length, 5);
  });

  test('finishing requires a result or an end date, dropping a reason', () {
    expect(
      () => validateItems(
        tree([const Item(id: 'a', name: '跳槽', status: ItemStatus.done)]),
      ),
      throwsFormatException,
    );
    validateItems(
      tree([
        const Item(
          id: 'a',
          name: '跳槽',
          status: ItemStatus.done,
          outcome: '拿到 offer',
        ),
      ]),
    );
    validateItems(
      tree([
        Item(
          id: 'a',
          name: '跳槽',
          status: ItemStatus.done,
          endedOn: DateTime.utc(2026, 11, 4),
        ),
      ]),
    );
    expect(
      () => validateItems(
        tree([const Item(id: 'a', name: '跳槽', status: ItemStatus.dropped)]),
      ),
      throwsFormatException,
    );
    validateItems(
      tree([
        const Item(
          id: 'a',
          name: '跳槽',
          status: ItemStatus.dropped,
          outcome: '方向不合适',
        ),
      ]),
    );
  });

  test('a finished project cannot keep an open child', () {
    expect(
      () => validateItems(
        tree([
          const Item(
            id: 'job',
            name: '跳槽',
            status: ItemStatus.done,
            outcome: '完成',
          ),
          const Item(id: 'resume', name: '改简历', parentId: 'job'),
        ]),
      ),
      throwsFormatException,
    );
    validateItems(
      tree([
        const Item(
          id: 'job',
          name: '跳槽',
          status: ItemStatus.done,
          outcome: '完成',
        ),
        const Item(
          id: 'resume',
          name: '改简历',
          parentId: 'job',
          status: ItemStatus.done,
          outcome: '已投递',
        ),
      ]),
    );
  });

  test('dates must be whole civil days in order', () {
    expect(
      () => validateItems(
        tree([
          Item(id: 'a', name: '跳槽', startedOn: DateTime.utc(2026, 11, 4, 9)),
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => validateItems(
        tree([
          Item(
            id: 'a',
            name: '跳槽',
            startedOn: DateTime.utc(2026, 11, 4),
            endedOn: DateTime.utc(2026, 11, 1),
          ),
        ]),
      ),
      throwsFormatException,
    );
  });

  test('ancestors and root resolve through the tree', () {
    final items = tree([
      const Item(id: 'job', name: '主业'),
      const Item(id: 'hop', name: '跳槽', parentId: 'job'),
      const Item(id: 'resume', name: '改简历', parentId: 'hop'),
    ]);
    expect(itemAncestors(items, 'resume').map((item) => item.id), [
      'job',
      'hop',
    ]);
    expect(itemRoot(items, 'resume')!.id, 'job');
    expect(itemRoot(items, 'job')!.id, 'job');
    expect(itemRoot(items, 'missing'), isNull);
    expect(itemAncestors(items, 'job'), isEmpty);
  });

  test('duration rolls up from children and ignores unfinished records', () {
    final items = tree([
      const Item(id: 'job', name: '主业'),
      const Item(id: 'hop', name: '跳槽', parentId: 'job'),
      const Item(id: 'resume', name: '改简历', parentId: 'hop'),
    ]);
    final durations = itemDurations(items, [
      Event('a', '调研', null, at(0), at(90), '', 'hop'),
      Event('b', '改简历', null, at(120), at(150), '', 'resume'),
      Event('c', '未结束', null, at(200), null, '', 'hop'),
      Event('d', '无归属', null, at(240), at(300)),
    ]);
    expect(durations['missing'], isNull);
    expect(durations['resume'], const Duration(minutes: 30));
    expect(durations['hop'], const Duration(minutes: 120));
    expect(durations['job'], const Duration(minutes: 120));
  });

  test('tree order keeps each root followed by its descendants', () {
    final items = tree([
      const Item(id: 'b', name: '副业'),
      const Item(id: 'a', name: '主业'),
      const Item(id: 'a2', name: '跳槽', parentId: 'a'),
      const Item(id: 'a1', name: '嵌入式', parentId: 'a'),
    ]);
    expect(orderedItems(items).map((entry) => entry.$1.id), [
      'a',
      'a1',
      'a2',
      'b',
    ]);
    expect(orderedItems(items).map((entry) => entry.$2), [0, 1, 1, 0]);
  });

  test('copyWith can clear optional fields', () {
    final item = Item(
      id: 'a',
      name: '跳槽',
      parentId: 'job',
      startedOn: DateTime.utc(2026, 11, 4),
      endedOn: DateTime.utc(2026, 11, 5),
    );
    final cleared = item.copyWith(
      clearParent: true,
      clearStartedOn: true,
      clearEndedOn: true,
    );
    expect(cleared.parentId, isNull);
    expect(cleared.startedOn, isNull);
    expect(cleared.endedOn, isNull);
    expect(cleared.name, '跳槽');
  });
}
