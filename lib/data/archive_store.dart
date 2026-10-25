import 'dart:convert';
import 'dart:io';

import '../domain/journal_archive.dart';
import '../domain/model.dart';
import 'atomic_file.dart';
import 'store.dart';

/// One cumulative backup. Existing history is replaced only after an explicit
/// edit in this session; opening the app never refreshes old backup records.
class ArchiveStore {
  ArchiveStore._(this.directory, this._writer);
  final Directory directory;
  final FileWriter _writer;
  Set<DateTime> _days = {};
  Map<String, Event> _events = {};
  Map<String, Tag> _tags = {};
  Set<DateTime> get days => Set.unmodifiable(_days);
  Map<String, Event> get events => Map.unmodifiable(_events);
  Map<String, Tag> get tags => Map.unmodifiable(_tags);
  File get file => File('${directory.path}/archive.json');

  static Future<ArchiveStore> open(
    Directory directory, {
    FileWriter writer = AtomicFile.write,
  }) async {
    final archive = ArchiveStore._(directory.absolute, writer);
    if (!await archive.file.exists()) return archive;
    try {
      final source = jsonDecode(await archive.file.readAsString());
      if (source is! Map<String, Object?> ||
          source['version'] != 1 ||
          source['days'] is! List<Object?> ||
          source['tags'] is! List<Object?> ||
          source['events'] is! List<Object?>) {
        throw const FormatException('不支持的归档文件格式。');
      }
      for (final value in source['days']! as List<Object?>) {
        if (value is! String || !archive._days.add(parseDate(value))) {
          throw const FormatException('归档日期格式不正确或重复。');
        }
      }
      for (final value in source['tags']! as List<Object?>) {
        if (value is! Map<String, Object?> ||
            value['id'] is! String ||
            value['name'] is! String ||
            (value['parent_id'] != null && value['parent_id'] is! String)) {
          throw const FormatException('归档标签格式不正确。');
        }
        final tag = Tag(
          value['id']! as String,
          value['name']! as String,
          value['parent_id'] as String?,
        );
        if (archive._tags.containsKey(tag.id)) {
          throw const FormatException('归档标签 ID 重复。');
        }
        archive._tags[tag.id] = tag;
      }
      Store.validateTags(archive._tags);
      for (final value in source['events']! as List<Object?>) {
        if (value is! Map<String, Object?> ||
            value['id'] is! String ||
            value['title'] is! String ||
            value['start'] is! String ||
            value['notes'] is! String ||
            (value['end'] != null && value['end'] is! String) ||
            (value['tag_id'] != null && value['tag_id'] is! String)) {
          throw const FormatException('归档事件格式不正确。');
        }
        final event = Event(
          value['id']! as String,
          value['title']! as String,
          value['tag_id'] as String?,
          parseTimestamp(value['start']! as String),
          value['end'] == null ? null : parseTimestamp(value['end']! as String),
          value['notes']! as String,
        );
        Store.validateEventData(event, archive._tags, allowIncomplete: true);
        if (archive._events.containsKey(event.id) ||
            !eventTouchesDays(event, archive._days)) {
          throw const FormatException('归档事件重复或不属于归档日期。');
        }
        archive._events[event.id] = event;
      }
    } on FormatException catch (error) {
      throw DataError('无法读取 ${archive.file.path}：${error.message}');
    }
    return archive;
  }

  Future<void> capture(
    Store store,
    DateTime now, {
    Set<String> editedIds = const {},
  }) async {
    final completed = completedJournalDays(store.events.values, now);
    final addedDays = completed.difference(_days);
    final desiredDays = {..._days, ...completed};
    if (desiredDays.isEmpty) return;
    final current = store.events;
    final desiredEvents = {..._events};
    for (final id in editedIds) {
      desiredEvents.remove(id);
      final event = current[id];
      if (event != null && eventTouchesDays(event, desiredDays)) {
        desiredEvents[id] = event;
      }
    }
    for (final event in current.values) {
      if (eventTouchesDays(event, addedDays)) {
        desiredEvents.putIfAbsent(event.id, () => event);
      }
    }
    final desiredTags = {..._tags, ...store.tags};
    bool same<K, V>(Map<K, V> left, Map<K, V> right) =>
        left.length == right.length &&
        left.entries.every((entry) => right[entry.key] == entry.value);
    if (addedDays.isEmpty &&
        same(desiredEvents, _events) &&
        same(desiredTags, _tags)) {
      return;
    }
    final sortedDays = desiredDays.toList()..sort();
    final sortedEvents = desiredEvents.values.toList()..sort(compareEvents);
    await _writer(
      file,
      utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'days': sortedDays.map(dateText).toList(),
          'tags': desiredTags.values.map((tag) => tag.toJson()).toList(),
          'events': [
            for (final event in sortedEvents) {'id': event.id, 'title': event.title, 'tag_id': event.tagId, 'start': timestampText(event.start), 'end': event.end == null ? null : timestampText(event.end!), 'notes': event.notes},
          ],
        })}\n',
      ),
    );
    _days = desiredDays;
    _events = desiredEvents;
    _tags = desiredTags;
  }
}
