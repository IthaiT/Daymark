import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../data/store.dart';
import '../domain/event_clipboard.dart';
import '../domain/history.dart';
import '../domain/model.dart';

enum EventColumn { title, start, end, tag }

class JournalSnapshot {
  JournalSnapshot(Map<String, Event> events, Map<String, Event> drafts)
    : events = Map.unmodifiable(events),
      drafts = Map.unmodifiable(drafts);
  final Map<String, Event> events;
  final Map<String, Event> drafts;
  @override
  bool operator ==(Object other) =>
      other is JournalSnapshot &&
      mapEquals(events, other.events) &&
      mapEquals(drafts, other.drafts);
  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(events.values),
    Object.hashAllUnordered(drafts.values),
  );
}

class JournalController extends ChangeNotifier {
  JournalController(this.store, {DateTime? day, DateTime Function()? clock})
    : _day = dayStart(day ?? DateTime.now()),
      clock = clock ?? DateTime.now;
  final Store store;
  final DateTime Function() clock;
  final history = History<JournalSnapshot>();
  DateTime _day;
  DateTime get day => _day;
  Map<String, Event> _drafts = {};
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
    ...store.eventsOn(day).where((event) => event.isUndefined),
  ]..sort(compareEvents);

  JournalSnapshot _capture() => JournalSnapshot(store.events, _drafts);
  Map<String, Event> _reconcile(
    Map<String, Event> events,
    Map<String, Event> drafts,
  ) {
    final storedGaps = {
      for (final item in events.values.where((event) => event.isUndefined))
        item.id: item,
    };
    final regular = {
      for (final item in events.values.where((event) => !event.isUndefined))
        item.id: item,
    };
    final result = {...regular};
    for (final gap in undefinedEvents([...regular.values, ...drafts.values])) {
      var previous = storedGaps[gap.id];
      if (previous == null &&
          dayStart(gap.start).isBefore(dayStart(gap.end!))) {
        // Older versions persisted only the next day's leading portion.
        // Carry its name and notes into the complete cross-day gap once.
        final legacyHead = storedGaps[undefinedHeadId(gap.end!)];
        if (legacyHead?.end == gap.end &&
            legacyHead!.start == dayStart(gap.end!)) {
          previous = legacyHead;
        }
      }
      result[gap.id] =
          previous?.copyWith(
            id: gap.id,
            start: gap.start,
            end: gap.end,
            clearTag: true,
          ) ??
          gap;
    }
    return result;
  }

  Future<void> _apply(
    Map<String, Event> events,
    Map<String, Event> drafts, {
    DateTime? day,
    bool record = true,
  }) async {
    final before = _capture();
    final desiredDay = day ?? _day;
    final desired = _reconcile(events, drafts);
    if (!mapEquals(desired, store.events)) await store.replaceEvents(desired);
    _drafts = Map.of(drafts);
    _day = desiredDay;
    _selected = _selected
        .where((id) => rows.any((row) => row.id == id))
        .toSet();
    if (record) history.record(before, _capture());
    notifyListeners();
  }

  Future<void> initialize() =>
      _run(() => _apply(store.events, _drafts, record: false));
  Future<void> setDay(DateTime value) => _run(() async {
    if (value.year < 1 || value.year > 9999) {
      throw const FormatException('已经到达日期范围边界。');
    }
    await _apply(store.events, {}, day: dayStart(value), record: false);
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
    await _apply(store.events, {..._drafts, id: draft});
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
        clearTag: !store.tags.containsKey(original.tagId),
      );
      store.validateEvent(
        pasted.title.trim().isEmpty ? pasted.copyWith(title: '新事件') : pasted,
        allowIncomplete: true,
      );
      if (pasted.title.trim().isEmpty) {
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
      EventColumn.title => current.copyWith(title: (value! as String).trim()),
      EventColumn.tag => current.copyWith(
        tagId: value as String?,
        clearTag: value == null,
      ),
      EventColumn.start => current.copyWith(start: value! as DateTime),
      EventColumn.end => current.copyWith(end: value! as DateTime),
    };
    if (changed.tagId != null &&
        (changed.title.trim().isEmpty ||
            current.isUndefined && current.title == '未定义')) {
      changed = changed.copyWith(title: store.tagName(changed.tagId));
    }
    final events = {...store.events};
    final drafts = {..._drafts};
    if (current.isUndefined) {
      if (changed.tagId != null) {
        changed = changed.copyWith(id: const Uuid().v4().replaceAll('-', ''));
        events.remove(current.id);
      } else if (changed.title.isEmpty) {
        changed = changed.copyWith(title: '未定义');
      }
      store.validateEvent(changed);
      events[changed.id] = changed;
    } else if (drafts.containsKey(id)) {
      store.validateEvent(
        changed.title.isEmpty ? changed.copyWith(title: '新事件') : changed,
      );
      if (changed.title.isEmpty) {
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
    await _apply(events, drafts);
    select(changed.id);
    return changed.id;
  });

  Future<void> updateEvent(Event changed) => _run(() async {
    final current = event(changed.id);
    if (current == null || current.isUndefined) return;
    if (changed.title.trim().isEmpty && changed.tagId != null) {
      changed = changed.copyWith(title: store.tagName(changed.tagId));
    }
    final drafts = {..._drafts};
    final events = {...store.events};
    if (drafts.containsKey(changed.id)) {
      store.validateEvent(
        changed.copyWith(title: changed.title.isEmpty ? '新事件' : changed.title),
      );
      drafts[changed.id] = changed;
    } else {
      store.validateEvent(changed);
      events[changed.id] = changed;
    }
    await _apply(events, drafts);
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
    Event normalize(Event event) =>
        event.tagId == null || store.tags.containsKey(event.tagId)
        ? event
        : event.copyWith(clearTag: true);
    await _apply(
      {for (final item in snapshot.events.values) item.id: normalize(item)},
      {for (final item in snapshot.drafts.values) item.id: normalize(item)},
      record: false,
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
        item.id: item.tagId == id ? item.copyWith(clearTag: true) : item,
    };
    notifyListeners();
  });
  Future<void> moveTag(String id, String? parentId) =>
      saveTag(store.tags[id]!.name, parentId, id: id);
}
