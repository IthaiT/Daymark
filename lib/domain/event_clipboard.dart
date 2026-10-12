import 'dart:convert';

import 'model.dart';

/// A clipboard snapshot, independent of event identities and storage files.
class EventClipboard {
  EventClipboard(DateTime day, Iterable<Event> events)
    : day = dayStart(day),
      events = List.unmodifiable(events);

  static const _prefix = 'Daymark events 1\n';
  final DateTime day;
  final List<Event> events;

  String encode() {
    String timestamp(DateTime value) =>
        civilTime(value).toIso8601String().replaceFirst(RegExp(r'Z$'), '');
    return _prefix +
        jsonEncode({
          'day': dateText(day),
          'events': [
            for (final event in events)
              {
                'title': event.title,
                'tag_id': event.tagId,
                'start': timestamp(event.start),
                'end': event.end == null ? null : timestamp(event.end!),
                'notes': event.notes,
              },
          ],
        });
  }

  /// Ignore unrelated text; reject damaged Daymark payloads before any write.
  static EventClipboard? tryDecode(String? text) {
    if (text == null || !text.startsWith(_prefix)) return null;
    try {
      final payload = jsonDecode(text.substring(_prefix.length));
      if (payload is! Map<String, Object?> ||
          payload['day'] is! String ||
          payload['events'] is! List<Object?>) {
        throw const FormatException();
      }
      final events = <Event>[];
      for (final row in payload['events']! as List<Object?>) {
        if (row is! Map<String, Object?> ||
            row['title'] is! String ||
            (row['tag_id'] != null && row['tag_id'] is! String) ||
            row['start'] is! String ||
            (row['end'] != null && row['end'] is! String) ||
            row['notes'] is! String) {
          throw const FormatException();
        }
        final start = parseTimestamp(row['start']! as String);
        final end = row['end'] == null
            ? null
            : parseTimestamp(row['end']! as String);
        if (end != null && !end.isAfter(start)) {
          throw const FormatException();
        }
        events.add(
          Event(
            events.length.toString(),
            row['title']! as String,
            row['tag_id'] as String?,
            start,
            end,
            row['notes']! as String,
          ),
        );
      }
      return EventClipboard(parseDate(payload['day']! as String), events);
    } on FormatException {
      throw const FormatException('剪贴板中的事件格式不正确，请重新复制。');
    }
  }
}
