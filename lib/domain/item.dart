import 'event_stats.dart';
import 'model.dart';
import 'item_source.dart';
export 'item_source.dart';
import 'unicode.dart';

/// Lifecycle of a node. A node carrying one of these states is what the
/// interface calls a project; a leaf without time is a planned item.
enum ItemStatus { active, paused, done, dropped }

extension ItemStatusText on ItemStatus {
  String get label => switch (this) {
    ItemStatus.active => '待办',
    ItemStatus.paused => '暂停',
    ItemStatus.done => '已完成',
    ItemStatus.dropped => '已取消',
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
    this.tagIds = const [],
    this.excludedTagIds = const [],
    this.links = const [],
    this.log = const [],
    this.source,
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

  /// Tags this node adds. Children inherit them unless they exclude them.
  final List<String> tagIds;

  /// Inherited tags this node deliberately drops for itself and its children.
  final List<String> excludedTagIds;

  /// External results: Obsidian URIs, web pages or local files.
  final List<String> links;

  /// Short trail of what happened to the item: created, split, repurposed or
  /// abandoned, with the moment it happened.
  final List<ItemLog> log;

  /// Lossless Markdown source, also retained when the source disappears.
  final ItemSource? source;
  bool get isTodo => status == ItemStatus.active && !(source?.missing ?? false);

  /// Reads one node from `items.json` or an archive backup.
  factory Item.fromJson(Map<String, Object?> row) {
    List<String> strings(Object? value) =>
        (value as List<Object?>? ?? const []).cast<String>().toList();
    if (row['source'] != null && row['source'] is! Map<String, Object?>) {
      throw const FormatException('事项来源格式不正确。');
    }
    final log = <ItemLog>[];
    for (final entry in (row['log'] as List<Object?>? ?? const [])) {
      final item = entry! as Map<String, Object?>;
      log.add(
        ItemLog(
          parseTimestamp(item['at']! as String),
          item['kind']! as String,
          item['text']! as String,
        ),
      );
    }
    return Item(
      id: row['id']! as String,
      name: row['name']! as String,
      parentId: row['parent_id'] as String?,
      status: switch (row['status']) {
        null || 'active' => ItemStatus.active,
        'paused' => ItemStatus.paused,
        'done' => ItemStatus.done,
        'dropped' => ItemStatus.dropped,
        _ => throw const FormatException('事项状态不正确。'),
      },
      startedOn: row['started_on'] == null
          ? null
          : parseDate(row['started_on']! as String),
      endedOn: row['ended_on'] == null
          ? null
          : parseDate(row['ended_on']! as String),
      objective: row['objective'] as String? ?? '',
      outcome: row['outcome'] as String? ?? '',
      tagIds: strings(row['tag_ids']),
      excludedTagIds: strings(row['excluded_tag_ids']),
      links: strings(row['links']),
      log: log,
      source: row['source'] == null
          ? null
          : ItemSource.fromJson(row['source']! as Map<String, Object?>),
    );
  }

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
    List<String>? tagIds,
    List<String>? excludedTagIds,
    List<String>? links,
    List<ItemLog>? log,
    ItemSource? source,
  }) => Item(
    id: id,
    name: name ?? this.name,
    parentId: clearParent ? null : parentId ?? this.parentId,
    status: status ?? this.status,
    startedOn: clearStartedOn ? null : startedOn ?? this.startedOn,
    endedOn: clearEndedOn ? null : endedOn ?? this.endedOn,
    objective: objective ?? this.objective,
    outcome: outcome ?? this.outcome,
    tagIds: tagIds ?? this.tagIds,
    excludedTagIds: excludedTagIds ?? this.excludedTagIds,
    links: links ?? this.links,
    log: log ?? this.log,
    source: source ?? this.source,
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
    'tag_ids': tagIds,
    'excluded_tag_ids': excludedTagIds,
    'links': links,
    'log': [for (final entry in log) entry.toJson()],
    if (source != null) 'source': source!.toJson(),
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
      outcome == other.outcome &&
      source == other.source &&
      sameValues(tagIds, other.tagIds) &&
      sameValues(excludedTagIds, other.excludedTagIds) &&
      sameValues(links, other.links) &&
      sameValues(log, other.log);

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
    source,
    Object.hashAll(tagIds),
    Object.hashAll(excludedTagIds),
    Object.hashAll(links),
    Object.hashAll(log),
  );
}

/// Order-sensitive list equality for persisted small lists.
bool sameValues<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// One entry of an item's short trail.
class ItemLog {
  const ItemLog(this.at, this.kind, this.text);
  final DateTime at;

  /// `created`, `status`, `parent` or `note`.
  final String kind;
  final String text;

  Map<String, Object?> toJson() => {
    'at': timestampText(at),
    'kind': kind,
    'text': text,
  };

  @override
  bool operator ==(Object other) =>
      other is ItemLog &&
      at == other.at &&
      kind == other.kind &&
      text == other.text;

  @override
  int get hashCode => Object.hash(at, kind, text);
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
    if (item.source == null &&
        item.status == ItemStatus.done &&
        item.outcome.trim().isEmpty &&
        item.endedOn == null) {
      throw FormatException('事项「${item.name}」完成前需要填写结果或结束日期。');
    }
    if (item.source == null &&
        item.status == ItemStatus.dropped &&
        item.outcome.trim().isEmpty) {
      throw FormatException('事项「${item.name}」放弃时请填写原因。');
    }
  }

  final siblings = <(String?, String), Item>{};
  for (final item in items.values) {
    final key = (item.parentId, caseFold(item.name.trim()));
    final sibling = siblings[key];
    if (sibling != null && sibling.source == null && item.source == null) {
      throw const FormatException('同一个父事项下不能有重名事项。');
    }
    if (sibling == null || item.source == null) siblings[key] = item;
    final visited = <String>{item.id};
    var parent = item.parentId;
    while (parent != null) {
      if (!visited.add(parent)) {
        throw const FormatException('事项不能挂在自己或自己的子事项下。');
      }
      parent = items[parent]!.parentId;
    }
  }

  for (final item in items.values) {
    if (item.source != null || item.status != ItemStatus.done) continue;
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
  final left = a.source;
  final right = b.source;
  if (left != null || right != null) {
    if (left == null) return -1;
    if (right == null) return 1;
    for (final pair in [
      (left.directory, right.directory),
      (left.path, right.path),
      (left.kind, right.kind),
    ]) {
      final result = compareUnicode(caseFold(pair.$1), caseFold(pair.$2));
      if (result != 0) return result;
    }
    final order = left.order.compareTo(right.order);
    if (order != 0) return order;
  }
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

/// Tags a node inherits from its ancestors plus its own, minus the ones a
/// level explicitly dropped. A deeper node may add a tag back by listing it.
List<String> itemEffectiveTagIds(Map<String, Item> items, String id) {
  final node = items[id];
  if (node == null) return const [];
  final tags = <String>[];
  for (final item in [...itemAncestors(items, id), node]) {
    for (final tag in item.tagIds) {
      if (!tags.contains(tag)) tags.add(tag);
    }
    tags.removeWhere(item.excludedTagIds.contains);
  }
  return List.unmodifiable(tags);
}

Duration _mergedDuration(Iterable<Event> events) {
  final intervals = [
    for (final event in events)
      if (event.end != null) Interval(event.start, event.end!),
  ];
  return mergedIntervals(
    intervals,
  ).fold(Duration.zero, (sum, interval) => sum + interval.duration);
}

/// Time booked on each item, including everything below it.
///
/// Overlapping records are counted once, exactly like the statistics screen:
/// without shared accounting the union of the intervals is used, and with it
/// the same concurrency profile splits parallel records. Records without an
/// end contribute nothing, matching every other duration in the journal.
Map<String, Duration> itemDurations(
  Map<String, Item> items,
  Iterable<Event> events, {
  bool splitOverlap = false,
}) {
  final completed = [
    for (final event in events)
      if (!event.isUndefined && event.end != null) event,
  ];
  final direct = <String, List<Event>>{};
  for (final event in completed) {
    final id = event.itemId;
    if (id == null || !items.containsKey(id)) continue;
    (direct[id] ??= []).add(event);
  }
  final profile = splitOverlap
      ? ConcurrencyProfile.of(
          StatsWindow(
            DateTime.utc(1),
            DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999),
          ),
          completed,
        )
      : null;
  final totals = <String, Duration>{};
  for (final id in items.keys) {
    final records = <String, Event>{
      for (final entry in direct.entries)
        if (itemOwnedBy(items, entry.key, id))
          for (final event in entry.value) event.id: event,
    }.values;
    totals[id] = profile != null
        ? profile.durationOf(records)
        : _mergedDuration(records);
  }
  return totals;
}
