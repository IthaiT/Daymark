import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';

import '../domain/item.dart';
import '../domain/obsidian.dart';
import 'tree_backup_store.dart';
import '../domain/model.dart';
import '../domain/unicode.dart';
import 'atomic_file.dart';

const csvFields = ['id', 'title', 'tag_id', 'start', 'end', 'notes', 'item_id'];

/// Records written before projects existed keep the original six columns.
const legacyCsvFields = ['id', 'title', 'tag_id', 'start', 'end', 'notes'];
const defaultTags = [
  Tag('work', '主业'),
  Tag('embedded', '嵌入式', 'work'),
  Tag('linux', 'Linux', 'embedded'),
  Tag('side', '副业'),
  Tag('agent', 'Agent', 'side'),
  Tag('learning', '学习', 'agent'),
  Tag('course', '某一门课程', 'learning'),
  Tag('explore', '探索'),
  Tag('life', '生活'),
  Tag('rest', '休息', 'life'),
];

typedef FileWriter = Future<void> Function(File destination, List<int> bytes);

class DataError implements Exception {
  const DataError(this.message);
  final String message;
  @override
  String toString() => message;
}

class Store {
  Store._(this.directory, this._writer, this.clock);
  final DateTime Function() clock;
  final Directory directory;
  final FileWriter _writer;
  Map<String, Tag> _tags = {};
  Map<String, Item> _items = {};
  Map<String, Event> _events = {};
  Map<String, Tag> get tags => Map.unmodifiable(_tags);
  Map<String, Item> get items => Map.unmodifiable(_items);
  Map<String, Event> get events => Map.unmodifiable(_events);
  File get tagsFile => File('${directory.path}/tags.json');
  File get itemsFile => File('${directory.path}/items.json');
  File get eventsFile => File('${directory.path}/events.csv');

  static Future<Store> open(
    Directory directory, {
    FileWriter writer = AtomicFile.write,
    DateTime Function()? clock,
  }) async {
    await directory.create(recursive: true);
    final store = Store._(directory.absolute, writer, clock ?? DateTime.now);
    final hasTags = await store.tagsFile.exists();
    final hasItems = await store.itemsFile.exists();
    final hasEvents = await store.eventsFile.exists();
    // Fully validate all existing data before creating either missing file.
    // Items load before events, which are validated against them.
    store._tags = hasTags
        ? await store._readTags()
        : {for (final tag in defaultTags) tag.id: tag};
    store._items = hasItems ? await store._readItems() : {};
    store._events = hasEvents ? await store._readEvents() : {};
    if (!hasTags) await store._writeTags(store._tags);
    if (!hasItems) await store._writeItems(store._items);
    if (!hasEvents) await store._writeEvents(store._events);
    await store.captureTreeBackup();
    return store;
  }

  List<Tag> ancestors(String? id) {
    final result = <Tag>[];
    while (id != null) {
      final tag = _tags[id]!;
      result.add(tag);
      id = tag.parentId;
    }
    return result.reversed.toList();
  }

  String tagName(String? id) => id == null ? '未分类' : _tags[id]!.name;
  String tagOutline(String? id) => id == null
      ? '未分类'
      : [
          for (final (index, tag) in ancestors(id).indexed)
            '${List.filled(index, '  ').join()}${tag.name}',
        ].join('\n');
  String itemPath(String id) {
    final item = _items[id];
    if (item == null) return '';
    return [
      for (final node in itemAncestors(_items, id)) node.name,
      item.name,
    ].join(' / ');
  }

  /// Full path of an owner, used while editing so siblings stay
  /// distinguishable.
  String ownerLabel(OwnerRef? owner) {
    if (owner == null) return '未归类';
    return owner.isItem ? itemPath(owner.id) : tagName(owner.id);
  }

  /// Leaf name of an owner, used as a default record title.
  String ownerTitle(OwnerRef owner) =>
      owner.isItem ? (_items[owner.id]?.name ?? '') : tagName(owner.id);

  /// Tags an item inherits from its ancestors plus its own, minus the ones a
  /// level dropped, filtered to tags that still exist.
  List<String> effectiveItemTagIds(String id) => [
    for (final tag in itemEffectiveTagIds(_items, id))
      if (_tags.containsKey(tag)) tag,
  ];

  /// The single project item whose name matches [title], if exactly one does.
  /// Typing a planned item's name therefore attaches the record without a
  /// second step, and repeated names stay unassigned instead of guessing.
  String? itemIdForTitle(String title) {
    final needle = caseFold(title.trim());
    if (needle.isEmpty) return null;
    String? found;
    for (final item in _items.values) {
      if (caseFold(item.name.trim()) != needle) continue;
      if (found != null) return null;
      found = item.id;
    }
    return found;
  }

  /// Labels shown in a record's owner column: the project it belongs to first,
  /// then every tag it carries. A sub-item shows its root project, so the name
  /// already printed in the title column is not repeated.
  List<String> ownerLabels(Event event) => [
    if (event.itemId != null)
      itemRoot(_items, event.itemId!)?.name ??
          ownerLabel((id: event.itemId!, isItem: true)),
    for (final id in event.tagIds)
      if (_tags.containsKey(id)) tagName(id),
  ];

  /// Single-line form of [ownerLabels].
  String ownerName(Event event) {
    final labels = ownerLabels(event);
    return labels.isEmpty ? '未归类' : labels.join(' · ');
  }

  List<Tag> orderedTags() => _tags.values.toList()
    ..sort((a, b) {
      final left = ancestors(a.id).map((tag) => caseFold(tag.name)).toList();
      final right = ancestors(b.id).map((tag) => caseFold(tag.name)).toList();
      for (var i = 0; i < left.length && i < right.length; i++) {
        final result = compareUnicode(left[i], right[i]);
        if (result != 0) return result;
      }
      return left.length.compareTo(right.length);
    });
  Set<String> descendants(String id) {
    final result = <String>{id};
    final pending = [id];
    while (pending.isNotEmpty) {
      final parent = pending.removeLast();
      for (final tag in _tags.values.where((tag) => tag.parentId == parent)) {
        if (result.add(tag.id)) pending.add(tag.id);
      }
    }
    return result;
  }

  static void validateTags(Map<String, Tag> tags) {
    for (final tag in tags.values) {
      if (tag.parentId != null && !tags.containsKey(tag.parentId)) {
        throw FormatException('标签「${tag.name}」的父标签不存在。');
      }
    }
    final siblings = <(String?, String)>{};
    for (final tag in tags.values) {
      if (tag.id.isEmpty || tag.name.trim().isEmpty) {
        throw const FormatException('标签 ID 和名称不能为空。');
      }
      if (!siblings.add((tag.parentId, caseFold(tag.name.trim())))) {
        throw const FormatException('同一个父标签下不能有重名标签。');
      }
      final visited = <String>{tag.id};
      var parent = tag.parentId;
      while (parent != null) {
        if (!visited.add(parent)) {
          throw const FormatException('不能把标签移动到自己或自己的子标签中。');
        }
        parent = tags[parent]!.parentId;
      }
    }
  }

  void validateEvent(Event event, {bool allowIncomplete = false}) =>
      validateEventData(
        event,
        _tags,
        items: _items,
        allowIncomplete: allowIncomplete,
      );

  static void validateEventData(
    Event event,
    Map<String, Tag> tags, {
    Map<String, Item> items = const {},
    bool allowIncomplete = false,
  }) {
    if (event.id.isEmpty) throw const FormatException('事件 ID 不能为空。');
    if (event.title.trim().isEmpty) throw const FormatException('请输入事件名称。');
    for (final id in event.tagIds) {
      if (!tags.containsKey(id)) throw const FormatException('所选标签不存在。');
    }
    if (event.itemId != null && !items.containsKey(event.itemId)) {
      throw const FormatException('所选事项不存在。');
    }
    if (event.end == null && !allowIncomplete) {
      throw const FormatException('请填写事件的结束时间。');
    }
    if (event.start.year < 1 ||
        event.start.year > 9999 ||
        (event.end != null &&
            (event.end!.year < 1 || event.end!.year > 9999))) {
      throw const FormatException('日期超出范围。');
    }
    if (event.end != null && !event.end!.isAfter(event.start)) {
      throw const FormatException('结束时间必须晚于开始时间；跨天事件请修改结束日期。');
    }
    if (event.isUndefined && (event.tagId != null || event.itemId != null)) {
      throw const FormatException('空档行不能关联标签或事项，请将它转换为普通事件。');
    }
  }

  Future<Map<String, Tag>> _readTags() async {
    try {
      final payload = jsonDecode(
        (await tagsFile.readAsString()).replaceFirst(RegExp(r'^\uFEFF'), ''),
      );
      if (payload is! Map<String, Object?> ||
          payload['version'] != 1 ||
          payload['tags'] is! List<Object?>) {
        throw const FormatException('不支持的标签文件格式。');
      }
      final tags = <String, Tag>{};
      for (final row in payload['tags']! as List<Object?>) {
        if (row is! Map<String, Object?> ||
            row['id'] is! String ||
            row['name'] is! String ||
            (row['parent_id'] != null && row['parent_id'] is! String) ||
            row.keys.any((key) => !['id', 'name', 'parent_id'].contains(key))) {
          throw const FormatException('标签记录格式不正确。');
        }
        final tag = Tag(
          row['id']! as String,
          row['name']! as String,
          row['parent_id'] as String?,
        );
        if (tags.containsKey(tag.id)) throw const FormatException('标签 ID 重复。');
        tags[tag.id] = tag;
      }
      validateTags(tags);
      return tags;
    } on FormatException catch (error) {
      throw DataError('无法读取 ${tagsFile.path}：${error.message}');
    }
  }

  Future<Map<String, Item>> _readItems() async {
    try {
      final payload = jsonDecode(
        (await itemsFile.readAsString()).replaceFirst(RegExp(r'^\uFEFF'), ''),
      );
      if (payload is! Map<String, Object?> ||
          payload['version'] != 1 ||
          payload['items'] is! List<Object?>) {
        throw const FormatException('不支持的事项文件格式。');
      }
      final keys = {
        'id',
        'name',
        'parent_id',
        'status',
        'started_on',
        'ended_on',
        'objective',
        'outcome',
        'tag_ids',
        'excluded_tag_ids',
        'links',
        'log',
        'source',
      };
      final items = <String, Item>{};
      for (final row in payload['items']! as List<Object?>) {
        if (row is! Map<String, Object?> ||
            row['id'] is! String ||
            row['name'] is! String ||
            (row['parent_id'] != null && row['parent_id'] is! String) ||
            (row['started_on'] != null && row['started_on'] is! String) ||
            (row['ended_on'] != null && row['ended_on'] is! String) ||
            (row['objective'] != null && row['objective'] is! String) ||
            (row['outcome'] != null && row['outcome'] is! String) ||
            !_stringList(row['tag_ids']) ||
            !_stringList(row['excluded_tag_ids']) ||
            !_stringList(row['links']) ||
            !_logList(row['log']) ||
            row.keys.any((key) => !keys.contains(key))) {
          throw const FormatException('事项记录格式不正确。');
        }
        final item = Item.fromJson(row);
        if (items.containsKey(item.id)) {
          throw const FormatException('事项 ID 重复。');
        }
        items[item.id] = item;
      }
      validateItems(items);
      _checkItemTags(items);
      return items;
    } on FormatException catch (error) {
      throw DataError('无法读取 ${itemsFile.path}：${error.message}');
    }
  }

  Future<Map<String, Event>> _readEvents() async {
    try {
      final source = (await eventsFile.readAsString()).replaceFirst(
        RegExp(r'^\uFEFF'),
        '',
      );
      final eol =
          source.startsWith('${csvFields.join(',')}\r\n') ||
              source.startsWith('${legacyCsvFields.join(',')}\r\n')
          ? '\r\n'
          : '\n';
      final rows = CsvToListConverter(
        shouldParseNumbers: false,
        allowInvalid: false,
        eol: eol,
      ).convert(source);
      if (rows.isEmpty) throw const FormatException('CSV 列名不匹配。');
      final header = rows.first;
      bool matches(List<String> fields) =>
          header.length == fields.length &&
          Iterable<int>.generate(
            fields.length,
          ).every((i) => header[i] == fields[i]);
      final legacy = matches(legacyCsvFields);
      if (!legacy && !matches(csvFields)) {
        throw const FormatException('CSV 列名不匹配。');
      }
      final width = header.length;
      final events = <String, Event>{};
      for (final (index, row) in rows.skip(1).indexed) {
        try {
          if (row.length != width || row.any((field) => field is! String)) {
            throw const FormatException('CSV 列数不匹配。');
          }
          final fields = row.cast<String>();
          final event = Event(
            fields[0],
            fields[1],
            fields[2].isEmpty ? null : fields[2].split(','),
            parseTimestamp(fields[3]),
            fields[4].isEmpty ? null : parseTimestamp(fields[4]),
            fields[5],
            !legacy && fields[6].isNotEmpty ? fields[6] : null,
          );
          validateEvent(event, allowIncomplete: true);
          if (events.containsKey(event.id)) {
            throw const FormatException('事件 ID 重复。');
          }
          events[event.id] = event;
        } on FormatException catch (error) {
          throw FormatException('第 ${index + 2} 行：${error.message}');
        }
      }
      return events;
    } on FormatException catch (error) {
      throw DataError('无法读取 ${eventsFile.path}：${error.message}');
    }
  }

  Future<void> _writeTags(Map<String, Tag> tags) => _writeData(
    tagsFile,
    utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert({'version': 1, 'tags': tags.values.map((tag) => tag.toJson()).toList()})}\n',
    ),
    tags: tags,
  );
  Future<void> _writeItems(Map<String, Item> items) {
    final sorted = items.values.toList()
      ..sort((a, b) {
        final name = compareUnicode(caseFold(a.name), caseFold(b.name));
        return name != 0 ? name : compareUnicode(a.id, b.id);
      });
    return _writeData(
      itemsFile,
      utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert({'version': 1, 'items': sorted.map((item) => item.toJson()).toList()})}\n',
      ),
      items: items,
    );
  }

  Future<void> _writeEvents(Map<String, Event> events) {
    final sorted = events.values.toList()..sort(compareEvents);
    final rows = <List<String>>[
      csvFields,
      for (final event in sorted)
        [
          event.id,
          event.title,
          event.tagIds.join(','),
          timestampText(event.start),
          event.end == null ? '' : timestampText(event.end!),
          event.notes,
          event.itemId ?? '',
        ],
    ];
    return _writeData(
      eventsFile,
      utf8.encode('\uFEFF${const ListToCsvConverter().convert(rows)}\r\n'),
      events: events,
    );
  }

  Future<void> captureTreeBackup() => TreeBackupStore(
    directory,
    writer: _writer,
  ).capture(items: _items, tags: _tags, events: _events, now: clock());

  /// Backups are part of a save: failure restores the prior canonical bytes.
  Future<void> _writeData(
    File file,
    List<int> bytes, {
    Map<String, Item>? items,
    Map<String, Tag>? tags,
    Map<String, Event>? events,
  }) async {
    await captureTreeBackup();
    final previous = await file.exists() ? await file.readAsBytes() : null;
    await _writer(file, bytes);
    try {
      await TreeBackupStore(directory, writer: _writer).capture(
        items: items ?? _items,
        tags: tags ?? _tags,
        events: events ?? _events,
        now: clock(),
      );
    } on Object {
      if (previous != null) {
        await _writer(file, previous);
      } else if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  /// Merge by identity. Source removals are retained and hidden from recording.
  Future<void> importObsidian(
    ObsidianImport imported, {
    required String directory,
    Future<void> Function()? beforeSave,
  }) async {
    final tags = {..._tags};
    String resolveTag(String name) {
      String pathOf(Tag tag) {
        final parts = <String>[tag.name];
        var parent = tag.parentId;
        while (parent != null) {
          final node = tags[parent]!;
          parts.insert(0, node.name);
          parent = node.parentId;
        }
        return parts.join('/');
      }

      final exact = tags.values
          .where((t) => caseFold(pathOf(t)) == caseFold(name))
          .toList();
      if (exact.length == 1) return exact.single.id;
      final leaf = tags.values
          .where((t) => caseFold(t.name) == caseFold(name))
          .toList();
      if (leaf.length == 1) return leaf.single.id;
      if (leaf.length > 1)
        throw FormatException('标签「$name」有重名，请在 Markdown 中使用完整标签路径。');
      String? parent;
      for (final part in name.split('/')) {
        if (part.trim().isEmpty) throw const FormatException('标签路径不能为空。');
        final existing = tags.values.where(
          (t) => t.parentId == parent && caseFold(t.name) == caseFold(part),
        );
        if (existing.isNotEmpty) {
          parent = existing.single.id;
        } else {
          final tag = Tag(const Uuid().v4().replaceAll('-', ''), part, parent);
          tags[tag.id] = tag;
          parent = tag.id;
        }
      }
      return parent!;
    }

    final items = {
      for (final item in _items.values)
        item.id:
            item.source?.directory == directory &&
                !imported.items.containsKey(item.id)
            ? item.copyWith(source: item.source!.asMissing())
            : item,
    };
    for (final item in imported.items.values) {
      final previous = _items[item.id];
      if (previous != null && previous.source == null) {
        throw FormatException('导入 ID 与本地事项冲突：${item.id}。');
      }
      final tagIds = [
        for (final name in imported.tagNames[item.id] ?? const <String>[])
          resolveTag(name),
      ];
      items[item.id] = (previous ?? item).copyWith(
        name: item.name,
        parentId: item.parentId,
        clearParent: item.parentId == null,
        objective: item.objective,
        outcome: item.outcome,
        status: item.status,
        tagIds: normalizeTagIds(tagIds),
        excludedTagIds: const [],
        source: item.source,
      );
    }
    validateTags(tags);
    validateItems(items);
    await beforeSave?.call();
    final previousTags = _tags;
    final changedTags = tags.length != _tags.length;
    if (changedTags) await _writeTags(tags);
    _tags = tags;
    try {
      await _writeItems(items);
    } on Object {
      _tags = previousTags;
      if (changedTags) await _writeTags(previousTags);
      rethrow;
    }
    _items = items;
  }

  Future<Tag> saveTag(String name, String? parentId, {String? id}) async {
    if (id != null && !_tags.containsKey(id)) {
      throw const FormatException('标签不存在。');
    }
    final tag = Tag(
      id ?? const Uuid().v4().replaceAll('-', ''),
      name.trim(),
      parentId,
    );
    final desired = {..._tags, tag.id: tag};
    validateTags(desired);
    await _writeTags(desired);
    _tags = desired;
    return tag;
  }

  Future<void> deleteTag(String id) async {
    if (!_tags.containsKey(id)) throw const FormatException('标签不存在。');
    if (_tags.values.any((tag) => tag.parentId == id)) {
      throw const FormatException('此标签还有子标签，请先移动或删除子标签。');
    }
    if (_events.values.any((event) => event.tagIds.contains(id))) {
      throw const FormatException('此标签还有事件，请先给这些事件更换标签。');
    }
    if (_items.values.any(
      (item) => item.tagIds.contains(id) || item.excludedTagIds.contains(id),
    )) {
      throw const FormatException('此标签还有事项在用，请先调整这些事项的标签。');
    }
    final desired = {..._tags}..remove(id);
    await _writeTags(desired);
    _tags = desired;
  }

  /// Replaces the complete tag hierarchy in one atomic write. The tag map
  /// edits a tree in memory; nothing reaches disk until the whole hierarchy
  /// has been validated here.
  Future<void> replaceTags(Map<String, Tag> tags) async {
    for (final entry in tags.entries) {
      if (entry.key != entry.value.id) {
        throw const FormatException('标签 ID 与记录键不匹配。');
      }
    }
    validateTags(tags);
    for (final removed in _tags.keys.where((id) => !tags.containsKey(id))) {
      if (_events.values.any((event) => event.tagIds.contains(removed))) {
        throw FormatException('标签「${_tags[removed]!.name}」还有事件，请先给这些事件更换标签。');
      }
      if (_items.values.any(
        (item) =>
            item.tagIds.contains(removed) ||
            item.excludedTagIds.contains(removed),
      )) {
        throw FormatException('标签「${_tags[removed]!.name}」还有事项在用，请先调整这些事项的标签。');
      }
    }
    final desired = {for (final tag in tags.values) tag.id: tag};
    await _writeTags(desired);
    _tags = desired;
  }

  /// Replaces the complete project tree in one atomic write.
  Future<void> replaceItems(Map<String, Item> items) async {
    for (final entry in items.entries) {
      if (entry.key != entry.value.id) {
        throw const FormatException('事项 ID 与记录键不匹配。');
      }
    }
    validateItems(items);
    _checkItemTags(items);
    for (final removed in _items.keys.where((id) => !items.containsKey(id))) {
      if (_events.values.any((event) => event.itemId == removed)) {
        throw FormatException('事项「${_items[removed]!.name}」还有事件，请先移动这些事件。');
      }
    }
    final desired = {for (final item in items.values) item.id: item};
    await _writeItems(desired);
    _items = desired;
  }

  Future<Item> saveItem(Item item) async {
    final desired = {..._items, item.id: item};
    validateItems(desired);
    _checkItemTags(desired);
    await _writeItems(desired);
    _items = desired;
    return item;
  }

  /// Rejects tags an item no longer has, so a deleted tag cannot leave a
  /// dangling reference on disk.
  void _checkItemTags(Map<String, Item> items) {
    for (final item in items.values) {
      for (final tag in [...item.tagIds, ...item.excludedTagIds]) {
        if (!_tags.containsKey(tag)) {
          throw FormatException('事项「${item.name}」引用了不存在的标签。');
        }
      }
    }
  }

  /// Removes one leaf node. Its records move to the parent node, so time is
  /// never lost together with a project; only a root project sends its records
  /// back to the unclassified state.
  Future<void> deleteItem(String id) async {
    final item = _items[id];
    if (item == null) throw const FormatException('事项不存在。');
    if (_items.values.any((child) => child.parentId == id)) {
      throw const FormatException('此事项还有子事项，请先移动或删除子事项。');
    }
    final parentId = item.parentId;
    final nextItems = {..._items}..remove(id);
    final nextEvents = {
      for (final event in _events.values)
        event.id: event.itemId == id
            ? event.copyWith(itemId: parentId, clearItem: parentId == null)
            : event,
    };
    validateItems(nextItems);
    for (final event in nextEvents.values) {
      validateEventData(event, _tags, items: nextItems, allowIncomplete: true);
    }
    // Two files are involved, so the first write is rolled back when the
    // second fails: a failed delete must leave disk and memory unchanged.
    final previousEvents = _events;
    await _writeEvents(nextEvents);
    try {
      await _writeItems(nextItems);
    } on Object {
      await _writeEvents(previousEvents);
      rethrow;
    }
    _events = nextEvents;
    _items = nextItems;
  }

  Future<void> replaceEvents(Map<String, Event> events) async {
    for (final entry in events.entries) {
      if (entry.key != entry.value.id) {
        throw const FormatException('事件 ID 与记录键不匹配。');
      }
      validateEvent(entry.value, allowIncomplete: true);
    }
    await _writeEvents(events);
    _events = Map.of(events);
  }

  Future<void> saveEvent(Event event) async {
    validateEvent(event);
    await replaceEvents({..._events, event.id: event});
  }

  List<Event> eventsOn(DateTime day) =>
      _events.values
          .where(
            (event) =>
                event.intervalOn(day) != null ||
                event.end == null && dayStart(event.start) == dayStart(day),
          )
          .toList()
        ..sort(compareEvents);
}

bool _stringList(Object? value) =>
    value == null ||
    (value is List<Object?> && value.every((item) => item is String));

bool _logList(Object? value) =>
    value == null ||
    (value is List<Object?> &&
        value.every(
          (entry) =>
              entry is Map<String, Object?> &&
              entry['at'] is String &&
              entry['kind'] is String &&
              entry['text'] is String,
        ));
