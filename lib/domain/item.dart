import 'model.dart';
import 'unicode.dart';

/// Levels a project tree may contain: project, item, sub-item.
const maxItemLevels = 3;

/// Lifecycle of a node. A node carrying one of these states is what the
/// interface calls a project; a leaf without time is a planned item.
enum ItemStatus { active, paused, done, dropped }

extension ItemStatusText on ItemStatus {
  String get label => switch (this) {
    ItemStatus.active => '进行中',
    ItemStatus.paused => '暂停',
    ItemStatus.done => '已完成',
    ItemStatus.dropped => '已放弃',
  };

  /// Neither finished nor abandoned, so it can still receive new events.
  bool get isOpen => this == ItemStatus.active || this == ItemStatus.paused;
}

/// An immutable node of the project tree.
///
/// Items live in `items.json` and are referenced by [Event.itemId]. A node
/// without any event is a planned item: it costs nothing to keep, never
/// reaches the timeline, and never affects gap derivation or daily totals.
class Item {
  const Item({
    required this.id,
    required this.name,
    this.parentId,
    this.status = ItemStatus.active,
    this.startedOn,
    this.endedOn,
    this.objective = '',
    this.outcome = '',
  });

  final String id;
  final String name;
  final String? parentId;
  final ItemStatus status;
  final DateTime? startedOn;
  final DateTime? endedOn;

  /// What finishing this item should achieve, written before any time is
  /// booked against it.
  final String objective;

  /// Result once finished, reason once abandoned; empty while open.
  final String outcome;

  Item copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
    ItemStatus? status,
    DateTime? startedOn,
    bool clearStartedOn = false,
    DateTime? endedOn,
    bool clearEndedOn = false,
    String? objective,
    String? outcome,
  }) => Item(
    id: id,
    name: name ?? this.name,
    parentId: clearParent ? null : parentId ?? this.parentId,
    status: status ?? this.status,
    startedOn: clearStartedOn ? null : startedOn ?? this.startedOn,
    endedOn: clearEndedOn ? null : endedOn ?? this.endedOn,
    objective: objective ?? this.objective,
    outcome: outcome ?? this.outcome,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'parent_id': parentId,
    'status': status.name,
    'started_on': startedOn == null ? null : dateText(startedOn!),
    'ended_on': endedOn == null ? null : dateText(endedOn!),
    'objective': objective,
    'outcome': outcome,
  };

  @override
  bool operator ==(Object other) =>
      other is Item &&
      id == other.id &&
      name == other.name &&
      parentId == other.parentId &&
      status == other.status &&
      startedOn == other.startedOn &&
      endedOn == other.endedOn &&
      objective == other.objective &&
      outcome == other.outcome;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    parentId,
    status,
    startedOn,
    endedOn,
    objective,
    outcome,
  );
}

/// Rejects malformed trees before anything reaches disk.
///
/// A finished project may not keep open children, so time can never be booked
/// onto a project that claims to be over.
void validateItems(Map<String, Item> items) {
  for (final entry in items.entries) {
    final item = entry.value;
    if (entry.key != item.id || item.id.isEmpty || item.name.trim().isEmpty) {
      throw const FormatException('事项 ID 和名称不能为空。');
    }
    final parentId = item.parentId;
    if (parentId != null && !items.containsKey(parentId)) {
      throw FormatException('事项「${item.name}」的父事项不存在。');
    }
    for (final date in [item.startedOn, item.endedOn]) {
      if (date == null) continue;
      if (date.year < 1 || date.year > 9999 || date != dayStart(date)) {
        throw FormatException('事项「${item.name}」的日期不正确。');
      }
    }
    if (item.startedOn != null &&
        item.endedOn != null &&
        item.endedOn!.isBefore(item.startedOn!)) {
      throw FormatException('事项「${item.name}」的结束日期早于开始日期。');
    }
    if (item.status == ItemStatus.done &&
        item.outcome.trim().isEmpty &&
        item.endedOn == null) {
      throw FormatException('事项「${item.name}」完成前需要填写结果或结束日期。');
    }
    if (item.status == ItemStatus.dropped && item.outcome.trim().isEmpty) {
      throw FormatException('事项「${item.name}」放弃时请填写原因。');
    }
  }

  final siblings = <(String?, String)>{};
  for (final item in items.values) {
    if (!siblings.add((item.parentId, caseFold(item.name.trim())))) {
      throw const FormatException('同一个父事项下不能有重名事项。');
    }
    final visited = <String>{item.id};
    var parent = item.parentId;
    var levels = 1;
    while (parent != null) {
      if (!visited.add(parent)) {
        throw const FormatException('事项不能挂在自己或自己的子事项下。');
      }
      levels++;
      if (levels > maxItemLevels) {
        throw const FormatException('事项层级不能超过 $maxItemLevels 层。');
      }
      parent = items[parent]!.parentId;
    }
  }

  for (final item in items.values) {
    if (item.status != ItemStatus.done) continue;
    for (final child in items.values) {
      if (child.parentId == item.id && child.status.isOpen) {
        throw FormatException('事项「${item.name}」还有进行中的子事项，不能标记完成。');
      }
    }
  }
}

/// Ancestors from the root down to [id], excluding the node itself.
List<Item> itemAncestors(Map<String, Item> items, String id) {
  final result = <Item>[];
  String? cursor = items[id]?.parentId;
  while (cursor != null) {
    final parent = items[cursor];
    if (parent == null) break;
    result.add(parent);
    cursor = parent.parentId;
  }
  return result.reversed.toList();
}

/// Root project of [id], or the node itself when it is already a root.
Item? itemRoot(Map<String, Item> items, String id) {
  final chain = itemAncestors(items, id);
  return chain.isEmpty ? items[id] : chain.first;
}

int compareItemOrder(Item a, Item b) {
  final result = compareUnicode(
    caseFold(a.name.trim()),
    caseFold(b.name.trim()),
  );
  return result != 0 ? result : compareUnicode(a.id, b.id);
}

/// Tree order shared by the project list and every picker: each root followed
/// by its descendants, siblings in case-folded name order.
List<(Item, int)> orderedItems(Map<String, Item> items) {
  final children = <String?, List<Item>>{};
  for (final item in items.values) {
    (children[item.parentId] ??= []).add(item);
  }
  for (final siblings in children.values) {
    siblings.sort(compareItemOrder);
  }
  final result = <(Item, int)>[];
  void visit(String? parentId, int depth) {
    for (final item in children[parentId] ?? const <Item>[]) {
      result.add((item, depth));
      visit(item.id, depth + 1);
    }
  }

  visit(null, 0);
  return result;
}

/// Whether [id] is [ancestorId] or sits below it.
bool itemOwnedBy(Map<String, Item> items, String id, String ancestorId) {
  String? cursor = id;
  final seen = <String>{};
  while (cursor != null && seen.add(cursor)) {
    if (cursor == ancestorId) return true;
    cursor = items[cursor]?.parentId;
  }
  return false;
}

/// Time booked on each item, including everything below it. Records without an
/// end contribute nothing, matching every other duration in the journal.
Map<String, Duration> itemDurations(
  Map<String, Item> items,
  Iterable<Event> events,
) {
  final direct = <String, Duration>{};
  for (final event in events) {
    final end = event.end;
    final id = event.itemId;
    if (end == null || id == null || !items.containsKey(id)) continue;
    direct[id] = (direct[id] ?? Duration.zero) + end.difference(event.start);
  }
  final totals = <String, Duration>{};
  for (final id in items.keys) {
    var sum = Duration.zero;
    for (final entry in direct.entries) {
      if (itemOwnedBy(items, entry.key, id)) sum += entry.value;
    }
    totals[id] = sum;
  }
  return totals;
}
