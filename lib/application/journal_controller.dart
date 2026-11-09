import 'dart:io';

import 'package:flutter/foundation.dart';
import '../data/obsidian_sync.dart';
import 'package:uuid/uuid.dart';

import '../data/archive_store.dart';
import '../data/store.dart';
import '../domain/event_clipboard.dart';
import '../domain/history.dart';
import '../domain/item.dart';
import '../domain/journal_archive.dart';
import '../domain/model.dart';
import '../domain/settings.dart';

enum EventColumn { title, start, end, tag }

class JournalSnapshot {
  JournalSnapshot(
    Map<String, Event> events,
    Map<String, Event> drafts, {
    Set<String> suggestedEndIds = const {},
  }) : events = Map.unmodifiable(events),
       drafts = Map.unmodifiable(drafts),
       suggestedEndIds = Set.unmodifiable(suggestedEndIds);
  final Map<String, Event> events;
  final Map<String, Event> drafts;
  final Set<String> suggestedEndIds;
  @override
  bool operator ==(Object other) =>
      other is JournalSnapshot &&
      mapEquals(events, other.events) &&
      mapEquals(drafts, other.drafts) &&
      setEquals(suggestedEndIds, other.suggestedEndIds);
  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(events.values),
    Object.hashAllUnordered(drafts.values),
    Object.hashAllUnordered(suggestedEndIds),
  );
}

class JournalController extends ChangeNotifier {
  JournalController(
    this.store, {
    this.archive,
    DateTime? day,
    DateTime Function()? clock,
    AppSettings settings = const AppSettings(),
  }) : _day = dayStart(day ?? DateTime.now()),
       _settings = settings,
       clock = clock ?? DateTime.now;
  final Store store;
  final ArchiveStore? archive;
  bool _allowHistoryEditing = false;
  bool get allowHistoryEditing => _allowHistoryEditing;
  final _editedArchivedIds = <String>{};

  void setAllowHistoryEditing(bool value) {
    if (_allowHistoryEditing == value) return;
    _allowHistoryEditing = value;
    notifyListeners();
  }

  bool isArchived(Event event) =>
      archive != null && eventTouchesDays(event, archive!.days);
  bool canEditEvent(Event event) => allowHistoryEditing || !isArchived(event);
  bool canEditDay(DateTime day) =>
      allowHistoryEditing || !(archive?.days.contains(dayStart(day)) ?? false);
  bool canEditCell(Event event, EventColumn column) =>
      column == EventColumn.tag || canEditEvent(event);

  void _checkHistoryChanges(
    Map<String, Event> before,
    Map<String, Event> after, {
    Set<String> tagConversionIds = const {},
  }) {
    if (allowHistoryEditing) return;
    for (final id in {...before.keys, ...after.keys}) {
      final previous = before[id];
      final next = after[id];
      if (previous == next || tagConversionIds.contains(id)) continue;
      if (!(previous != null && isArchived(previous)) &&
          !(next != null && isArchived(next))) {
        continue;
      }
      if (previous != null &&
          next != null &&
          previous.copyWith(
                tagIds: next.tagIds,
                itemId: next.itemId,
                clearItem: next.itemId == null,
              ) ==
              next) {
        continue;
      }
      throw const FormatException('事件已归档，仅可修改标签。请在设置中开启「允许修改已归档事件」。');
    }
  }

  final DateTime Function() clock;
  final history = History<JournalSnapshot>();
  AppSettings _settings;
  AppSettings get settings => _settings;
  bool get autoUndefined => _settings.autoUndefined;
  int get dragMinutes => _settings.dragMinutes;
  bool get splitOverlap => _settings.splitOverlap;
  DateTime _day;
  DateTime get day => _day;
  Map<String, Event> _drafts = {};
  // Only fresh, automatically assigned ends follow edits to the start time.
  // This input state stays in memory and participates in undo/redo.
  Set<String> _suggestedEndIds = {};
  Map<String, Event> get drafts => Map.unmodifiable(_drafts);
  Set<String> _selected = {};
  Set<String> get selected => Set.unmodifiable(_selected);
  String? _selectionAnchor;
  Future<void> _tail = Future.value();

  /// Serialize all mutations, including their disk writes and history updates.
  Future<T> _run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Event? event(String id) => _drafts[id] ?? store.events[id];
  List<Event> get regularEvents => [
    ...store.events.values.where((event) => !event.isUndefined),
    ..._drafts.values,
  ];
  List<Event> get visibleEvents => [
    for (final event in regularEvents)
      if (event.intervalOn(day) != null ||
          event.end == null && dayStart(event.start) == day)
        event,
  ]..sort(compareEvents);
  List<Event> get rows => [
    ...visibleEvents,
    if (_settings.autoUndefined)
      ...store.eventsOn(day).where((event) => event.isUndefined),
  ]..sort(compareEvents);

  JournalSnapshot _capture() =>
      JournalSnapshot(store.events, _drafts, suggestedEndIds: _suggestedEndIds);
  Map<String, Event> _reconcile(Map<String, Event> events) {
    final regular = {
      for (final item in events.values.where((event) => !event.isUndefined))
        item.id: item,
    };
    final result = {...regular};
    for (final gap in currentGaps(events.values)) {
      result[gap.id] = gap;
    }
    return result;
  }

  Future<void> _apply(
    Map<String, Event> events,
    Map<String, Event> drafts, {
    DateTime? day,
    bool record = true,
    Set<String>? suggestedEndIds,
    Set<String> tagConversionIds = const {},
  }) async {
    final before = _capture();
    // Validate requested edits before derived gaps are reconciled. Automatic
    // gap behavior is unchanged, including startup and settings transitions.
    _checkHistoryChanges(
      store.events,
      events,
      tagConversionIds: tagConversionIds,
    );
    _checkHistoryChanges(_drafts, drafts);
    final edited = {
      for (final id in {...before.events.keys, ...events.keys})
        if (before.events[id] != events[id] &&
            (before.events[id] != null && isArchived(before.events[id]!) ||
                events[id] != null && isArchived(events[id]!)))
          id,
    };
    final desiredDay = day ?? _day;
    // New formal records always need a tag or an item. Preserve imported
    // legacy unclassified rows until the user explicitly classifies them.
    for (final event in events.values) {
      if (record &&
          !event.isUndefined &&
          event.owner == null &&
          (store.events[event.id] == null ||
              store.events[event.id]!.owner != null)) {
        throw const FormatException('请至少选择一个标签或关联事项。');
      }
    }
    final desired = _reconcile(events);
    if (!mapEquals(desired, store.events)) await store.replaceEvents(desired);
    _editedArchivedIds.addAll(edited);
    _drafts = Map.of(drafts);
    _suggestedEndIds = {
      for (final id in suggestedEndIds ?? _suggestedEndIds)
        if (events.containsKey(id) || drafts.containsKey(id)) id,
    };
    _day = desiredDay;
    _selected = _selected
        .where((id) => rows.any((row) => row.id == id))
        .toSet();
    if (record) history.record(before, _capture());
    notifyListeners();
  }

  Future<void> _archiveCompletedDays() async {
    await archive?.capture(store, clock(), editedIds: _editedArchivedIds);
    _editedArchivedIds.clear();
  }

  Future<void> initialize() => _run(() async {
    await _archiveCompletedDays();
    await _apply(store.events, _drafts, record: false);
  });

  /// Runs behind every pending event write; blank drafts remain in memory.
  Future<void> archiveForClose() => _run(() async {
    await _archiveCompletedDays();
    await store.captureTreeBackup();
  });
  Future<void> backupTree() => _run(store.captureTreeBackup);
  Future<int> syncObsidian(String path) => _run(() async {
    if (path.trim().isEmpty) {
      throw const FormatException('请先选择 Obsidian 事项文件夹。');
    }
    final count = await const ObsidianSync().synchronize(
      store,
      Directory(path.trim()),
    );
    notifyListeners();
    return count;
  });

  /// Applies a new recording policy. Disabling derived undefined records only
  /// hides them; stored gaps and their user-edited names are never discarded.
  Future<void> applySettings(AppSettings value) => _run(() async {
    if (value == _settings) return;
    final previous = _settings;
    _settings = value;
    if (previous.autoUndefined == value.autoUndefined) {
      notifyListeners();
      return;
    }
    try {
      await _apply(store.events, _drafts, record: false);
    } catch (error) {
      _settings = previous;
      notifyListeners();
      rethrow;
    }
  });

  Future<void> setDay(DateTime value) => _run(() async {
    if (value.year < 1 || value.year > 9999) {
      throw const FormatException('已经到达日期范围边界。');
    }
    await _apply(
      store.events,
      {},
      day: dayStart(value),
      record: false,
      suggestedEndIds: {},
    );
    clearSelection();
  });
  Future<void> shiftDay(int amount) => setDay(day.add(Duration(days: amount)));

  void select(
    String? id, {
    bool toggle = false,
    bool range = false,
    Iterable<String>? orderedIds,
  }) {
    if (id == null) {
      clearSelection();
      return;
    }
    if (event(id) == null) return;
    if (range && _selectionAnchor != null) {
      final ids = (orderedIds ?? rows.map((row) => row.id)).toList();
      final first = ids.indexOf(_selectionAnchor!);
      final last = ids.indexOf(id);
      if (first >= 0 && last >= 0) {
        _selected = ids
            .sublist(
              first < last ? first : last,
              (first > last ? first : last) + 1,
            )
            .toSet();
      } else {
        _selected = {id};
      }
    } else if (toggle) {
      _selected = {..._selected};
      if (!_selected.add(id)) _selected.remove(id);
      _selectionAnchor = id;
    } else {
      _selected = {id};
      _selectionAnchor = id;
    }
    notifyListeners();
  }

  void clearSelection() {
    _selected = {};
    _selectionAnchor = null;
    notifyListeners();
  }

  Future<String> addDraft({DateTime? start}) => _run(() async {
    final interval = defaultEventInterval(
      day,
      start: start,
      now: clock(),
      events: regularEvents,
    );
    final id = const Uuid().v4().replaceAll('-', '');
    final draft = Event(id, '', null, interval.start, interval.end);
    await _apply(
      store.events,
      {..._drafts, id: draft},
      suggestedEndIds: {..._suggestedEndIds, id},
    );
    select(id);
    return id;
  });
  Future<void> discardDraft(String id) =>
      _run(() => _apply(store.events, {..._drafts}..remove(id)));

  EventClipboard? copySelected() {
    final events = rows.where((event) => _selected.contains(event.id)).toList();
    return events.isEmpty ? null : EventClipboard(day, events);
  }

  Future<List<String>> pasteEvents(EventClipboard clipboard) => _run(() async {
    if (clipboard.events.isEmpty) return [];
    final offset = day.difference(clipboard.day);
    final events = {...store.events};
    final drafts = {..._drafts};
    final ids = <String>[];
    for (final original in clipboard.events) {
      final id = const Uuid().v4().replaceAll('-', '');
      final pasted = original.copyWith(
        id: id,
        start: civilTime(original.start).add(offset),
        end: original.end == null ? null : civilTime(original.end!).add(offset),
        tagIds: [
          for (final id in original.tagIds)
            if (store.tags.containsKey(id)) id,
        ],
        clearItem: !store.items.containsKey(original.itemId),
      );
      store.validateEvent(
        pasted.title.trim().isEmpty ? pasted.copyWith(title: '新事件') : pasted,
        allowIncomplete: true,
      );
      if (pasted.title.trim().isEmpty || pasted.owner == null) {
        drafts[id] = pasted;
      } else {
        events[id] = pasted;
      }
      ids.add(id);
    }
    await _apply(events, drafts);
    _selected = ids.toSet();
    _selectionAnchor = ids.first;
    notifyListeners();
    return ids;
  });

  Future<String> editCell(
    String id,
    EventColumn column,
    Object? value,
  ) => _run(() async {
    final current = event(id);
    if (current == null) throw const FormatException('事件不存在。');
    if (current.isUndefined &&
        (column == EventColumn.start || column == EventColumn.end)) {
      return id;
    }
    var changed = switch (column) {
      EventColumn.title => switch (value) {
        // A name suggestion carries the classification chosen with it.
        (
          title: String title,
          itemId: String? itemId,
          tagIds: List<String> tagIds,
        ) =>
          current.copyWith(
            title: title.trim(),
            itemId: itemId,
            clearItem: itemId == null,
            tagIds: tagIds,
          ),
        _ => current.copyWith(title: (value! as String).trim()),
      },
      // The editor sends the whole classification; a bare owner keeps working
      // for older callers.
      EventColumn.tag => switch (value) {
        (itemId: String? itemId, tagIds: List<String> tagIds) =>
          current.copyWith(
            itemId: itemId,
            clearItem: itemId == null,
            tagIds: tagIds,
          ),
        OwnerRef owner => current.withOwner(owner),
        null => current.copyWith(clearTags: true, clearItem: true),
        _ => throw const FormatException('归属格式不正确。'),
      },
      EventColumn.start => current.copyWith(start: value! as DateTime),
      EventColumn.end => current.copyWith(end: value! as DateTime),
    };
    if (column == EventColumn.start &&
        _suggestedEndIds.contains(id) &&
        current.end != null) {
      changed = changed.copyWith(
        end: changed.start.add(current.end!.difference(current.start)),
      );
    }
    final owner = changed.owner;
    if (owner != null &&
        (changed.title.trim().isEmpty ||
            current.isUndefined && gapPlaceholders.contains(current.title)) &&
        canEditEvent(current)) {
      changed = changed.copyWith(title: store.ownerTitle(owner));
    }
    final events = {...store.events};
    final drafts = {..._drafts};
    if (current.isUndefined) {
      if (changed.owner != null) {
        changed = changed.copyWith(id: const Uuid().v4().replaceAll('-', ''));
        events.remove(current.id);
      } else if (changed.title.isEmpty) {
        changed = changed.copyWith(title: '空档');
      }
      store.validateEvent(changed);
      events[changed.id] = changed;
    } else if (drafts.containsKey(id)) {
      store.validateEvent(
        changed.title.isEmpty ? changed.copyWith(title: '新事件') : changed,
      );
      if (changed.title.isEmpty || changed.owner == null) {
        drafts[id] = changed;
      } else {
        drafts.remove(id);
        events[id] = changed;
      }
    } else {
      // A legacy unfinished record remains editable until its end is supplied.
      store.validateEvent(
        changed,
        allowIncomplete: current.end == null && changed.end == null,
      );
      events[id] = changed;
    }
    await _apply(
      events,
      drafts,
      suggestedEndIds: column == EventColumn.end
          ? ({..._suggestedEndIds}..remove(id))
          : null,
      tagConversionIds:
          current.isUndefined &&
              column == EventColumn.tag &&
              changed.owner != null
          ? {current.id, changed.id}
          : const {},
    );
    select(changed.id);
    return changed.id;
  });

  Future<void> updateEvent(Event changed) => _run(() async {
    final current = event(changed.id);
    if (current == null) return;
    if (current.isUndefined) {
      // An annotation cannot change a derived interval or its classification.
      final annotated = current.copyWith(
        title: changed.title.trim().isEmpty ? '空档' : changed.title.trim(),
        notes: changed.notes,
      );
      store.validateEvent(annotated);
      await _apply({...store.events, current.id: annotated}, _drafts);
      return;
    }
    final owner = changed.owner;
    if (changed.title.trim().isEmpty && owner != null) {
      changed = changed.copyWith(title: store.ownerTitle(owner));
    }
    final drafts = {..._drafts};
    final events = {...store.events};
    if (drafts.containsKey(changed.id)) {
      store.validateEvent(
        changed.copyWith(title: changed.title.isEmpty ? '新事件' : changed.title),
      );
      if (changed.title.trim().isNotEmpty && changed.owner != null) {
        drafts.remove(changed.id);
        events[changed.id] = changed;
      } else {
        drafts[changed.id] = changed;
      }
    } else {
      store.validateEvent(changed);
      events[changed.id] = changed;
    }
    await _apply(
      events,
      drafts,
      suggestedEndIds: {..._suggestedEndIds}..remove(changed.id),
    );
  });

  /// Moves regular events to [tagId] in one transaction: a single atomic
  /// write and a single undo entry. Undefined gap rows cannot carry a tag and
  /// are skipped, as are ids that are not stored events.
  /// Replaces the tags of [ids]. The project association is left alone, so a
  /// tag may be added to or removed from records that belong to a project.
  Future<void> setEventTags(Iterable<String> ids, List<String> tagIds) =>
      _run(() async {
        final tags = normalizeTagIds(tagIds);
        for (final id in tags) {
          if (!store.tags.containsKey(id)) {
            throw const FormatException('目标标签不存在。');
          }
        }
        final wanted = ids.toSet();
        if (wanted.isEmpty) return;
        final events = {...store.events};
        var changed = false;
        for (final id in wanted) {
          final event = events[id];
          if (event == null || event.isUndefined) continue;
          if (sameTagIds(event.tagIds, tags)) continue;
          final next = event.copyWith(tagIds: tags);
          store.validateEvent(next, allowIncomplete: event.end == null);
          events[id] = next;
          changed = true;
        }
        if (changed) await _apply(events, _drafts);
      });

  Future<void> setEventTag(Iterable<String> ids, String? tagId) =>
      setEventTags(ids, tagId == null ? const [] : [tagId]);

  /// Associates [ids] with a project node, or clears it when [itemId] is null.
  /// The tags the item inherits are added and tags the user set by hand are
  /// kept, so choosing a project never silently unfiles a record.
  Future<void> setEventItem(Iterable<String> ids, String? itemId) =>
      _run(() async {
        if (itemId != null && !store.items.containsKey(itemId)) {
          throw const FormatException('目标事项不存在。');
        }
        final defaults = itemId == null
            ? const <String>[]
            : store.effectiveItemTagIds(itemId);
        final wanted = ids.toSet();
        if (wanted.isEmpty) return;
        final events = {...store.events};
        var changed = false;
        for (final id in wanted) {
          final event = events[id];
          if (event == null || event.isUndefined) continue;
          final next = event.copyWith(
            itemId: itemId,
            clearItem: itemId == null,
            tagIds: normalizeTagIds([...event.tagIds, ...defaults]),
          );
          if (next == event) continue;
          store.validateEvent(next, allowIncomplete: event.end == null);
          events[id] = next;
          changed = true;
        }
        if (changed) await _apply(events, _drafts);
      });

  /// Historical reclassification replaces tags, including when moving to an
  /// item. Unlike recording-time defaults, obsolete tags must not accumulate.
  /// A tag move preserves an existing item association.
  Future<void> moveEventsTo(Iterable<String> ids, OwnerRef owner) =>
      _run(() async {
        if (owner.isItem
            ? !store.items.containsKey(owner.id)
            : !store.tags.containsKey(owner.id)) {
          throw const FormatException('目标标签或事项不存在。');
        }
        final tags = owner.isItem
            ? store.effectiveItemTagIds(owner.id)
            : [owner.id];
        final events = {...store.events};
        var changed = false;
        for (final id in ids.toSet()) {
          final event = events[id];
          if (event == null || event.isUndefined) continue;
          final next = event.copyWith(
            tagIds: tags,
            itemId: owner.isItem ? owner.id : event.itemId,
          );
          if (next == event) continue;
          store.validateEvent(next, allowIncomplete: event.end == null);
          events[id] = next;
          changed = true;
        }
        if (changed) await _apply(events, _drafts);
      });

  /// Unreferenced branches only: keep ancestors of any tag used by a saved
  /// event, a draft or an item's additions/exclusions.
  Set<String> get unusedTagIds {
    final used = <String>{
      for (final event in [...store.events.values, ..._drafts.values])
        ...event.tagIds,
      for (final item in store.items.values) ...[
        ...item.tagIds,
        ...item.excludedTagIds,
      ],
    };
    for (final id in used.toList()) {
      used.addAll(store.ancestors(id).map((tag) => tag.id));
    }
    return store.tags.keys.toSet().difference(used);
  }

  Future<void> deleteUnusedTags(Set<String> ids) => _run(() async {
    if (ids.isEmpty) return;
    if (!unusedTagIds.containsAll(ids)) {
      throw const FormatException('部分标签正在使用，请重新检查后再清理。');
    }
    await store.replaceTags(
      {...store.tags}..removeWhere((id, _) => ids.contains(id)),
    );
    // Event snapshots can reference these tags; never offer a partial restore.
    history.clear();
    notifyListeners();
  });

  Future<void> deleteSelected() => _run(() async {
    final ids = {..._selected};
    final events = {...store.events}
      ..removeWhere((id, event) => ids.contains(id) && !event.isUndefined);
    final drafts = {..._drafts}..removeWhere((id, event) => ids.contains(id));
    await _apply(events, drafts);
    clearSelection();
  });

  Future<void> _restore(JournalSnapshot snapshot) async {
    // A restored snapshot may point at a tag or project removed afterwards.
    // Dropping only the missing references keeps undo/redo usable instead of
    // failing validation for the rest of the session.
    Event normalize(Event event) {
      final tags = [
        for (final id in event.tagIds)
          if (store.tags.containsKey(id)) id,
      ];
      final itemId =
          event.itemId != null && store.items.containsKey(event.itemId)
          ? event.itemId
          : null;
      if (itemId == event.itemId && sameTagIds(tags, event.tagIds)) {
        return event;
      }
      return Event(
        event.id,
        event.title,
        tags,
        event.start,
        event.end,
        event.notes,
        itemId,
      );
    }

    final restored = {
      for (final item in snapshot.events.values) item.id: normalize(item),
    };
    final current = store.events;
    final removed = current.values.where(
      (event) => !restored.containsKey(event.id),
    );
    final added = restored.values.where(
      (event) => !current.containsKey(event.id),
    );
    final tagConversions = <String>{};
    for (final previous in removed) {
      for (final next in added) {
        if (previous.isUndefined != next.isUndefined &&
            previous.copyWith(
                  id: next.id,
                  tagIds: next.tagIds,
                  itemId: next.itemId,
                  clearItem: next.itemId == null,
                ) ==
                next) {
          tagConversions.addAll([previous.id, next.id]);
        }
      }
    }
    await _apply(
      restored,
      {for (final item in snapshot.drafts.values) item.id: normalize(item)},
      record: false,
      suggestedEndIds: snapshot.suggestedEndIds,
      tagConversionIds: tagConversions,
    );
  }

  Future<bool> undo() => _run(() => history.undo(_restore));
  Future<bool> redo() => _run(() => history.redo(_restore));

  Future<Tag> saveTag(String name, String? parentId, {String? id}) =>
      _run(() async {
        final tag = await store.saveTag(name, parentId, id: id);
        notifyListeners();
        return tag;
      });
  Future<void> deleteTag(String id) => _run(() async {
    await store.deleteTag(id);
    _drafts = {
      for (final item in _drafts.values)
        item.id: item.tagIds.contains(id)
            ? item.copyWith(
                tagIds: [
                  for (final tag in item.tagIds)
                    if (tag != id) tag,
                ],
              )
            : item,
    };
    notifyListeners();
  });
  Future<void> moveTag(String id, String? parentId) =>
      saveTag(store.tags[id]!.name, parentId, id: id);

  Future<Item> saveItem(Item item) => _run(() async {
    // The trail keeps what happened to an item, not just its final state. It
    // is owned here because callers rebuild an item from a form and would
    // otherwise drop the entries written by earlier saves.
    final previous = store.items[item.id];
    final trail = previous?.log ?? const <ItemLog>[];
    var next = item;
    if (previous == null) {
      next = item.copyWith(
        log: [...trail, ItemLog(civilTime(clock()), 'created', item.name)],
      );
    } else if (previous.status != item.status) {
      final note = item.outcome.trim().isEmpty ? '' : '：${item.outcome.trim()}';
      next = item.copyWith(
        log: [
          ...trail,
          ItemLog(
            civilTime(clock()),
            'status',
            '${previous.status.label} → ${item.status.label}$note',
          ),
        ],
      );
    }
    final saved = await store.saveItem(next);
    notifyListeners();
    return saved;
  });

  /// Identifier for an item that has not been saved yet, so dialogs can build
  /// a complete node before the store sees it.
  String newItemId() => const Uuid().v4().replaceAll('-', '');

  Future<Item> createItem(String name, String? parentId) =>
      saveItem(Item(id: newItemId(), name: name.trim(), parentId: parentId));

  Future<void> deleteItem(String id) => _run(() async {
    final item = store.items[id];
    if (item?.parentId == null &&
        store.events.values.any(
          (event) => event.itemId == id && event.tagIds.isEmpty,
        )) {
      throw const FormatException('此事项仍有未带标签的记录，请先为这些记录选择标签或其他事项。');
    }
    await store.deleteItem(id);
    notifyListeners();
  });
}
