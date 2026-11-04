import 'package:daymark/domain/item.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Item> tree(List<Item> items) => {
  for (final item in items) item.id: item,
};

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

  test('a project tree stops at three levels', () {
    validateItems(
      tree([
        const Item(id: 'a', name: '项目'),
        const Item(id: 'b', name: '事项', parentId: 'a'),
        const Item(id: 'c', name: '细节', parentId: 'b'),
      ]),
    );
    expect(
      () => validateItems(
        tree([
          const Item(id: 'a', name: '项目'),
          const Item(id: 'b', name: '事项', parentId: 'a'),
          const Item(id: 'c', name: '细节', parentId: 'b'),
          const Item(id: 'd', name: '更深', parentId: 'c'),
        ]),
      ),
      throwsFormatException,
    );
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
