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
    this.outcome = '',
  });

  final String id;
  final String name;
  final String? parentId;
  final ItemStatus status;
  final DateTime? startedOn;
  final DateTime? endedOn;

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
    String? outcome,
  }) => Item(
    id: id,
    name: name ?? this.name,
    parentId: clearParent ? null : parentId ?? this.parentId,
    status: status ?? this.status,
    startedOn: clearStartedOn ? null : startedOn ?? this.startedOn,
    endedOn: clearEndedOn ? null : endedOn ?? this.endedOn,
    outcome: outcome ?? this.outcome,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'parent_id': parentId,
    'status': status.name,
    'started_on': startedOn == null ? null : dateText(startedOn!),
    'ended_on': endedOn == null ? null : dateText(endedOn!),
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
      outcome == other.outcome;

  @override
  int get hashCode =>
      Object.hash(id, name, parentId, status, startedOn, endedOn, outcome);
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
