import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'unicode.dart';

const undefinedIdPrefix = 'undefined:';

/// Local calendar fields stored in a zone-neutral container. Never convert
/// these values with toLocal/toUtc: persisted timestamps have no time zone.
DateTime civilTime(DateTime value) => DateTime.utc(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute,
  value.second,
  value.millisecond,
  value.microsecond,
);
DateTime dayStart(DateTime day) => DateTime.utc(day.year, day.month, day.day);
DateTime dayEnd(DateTime day) =>
    day.year == 9999 && day.month == 12 && day.day == 31
    ? DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999)
    : dayStart(day).add(const Duration(days: 1));
DateTime minuteTime(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day, value.hour, value.minute);
String dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String clockText(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';
String timestampText(DateTime value) =>
    '${dateText(value)}T${clockText(value)}:'
    '${value.second.toString().padLeft(2, '0')}';

DateTime parseTimestamp(String text) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?$',
  ).firstMatch(text);
  if (match == null) throw const FormatException('时间格式不正确，时间不能带时区后缀。');
  final fields = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final micro = int.parse((match.group(7) ?? '').padRight(6, '0'));
  final result = DateTime.utc(
    fields[0],
    fields[1],
    fields[2],
    fields[3],
    fields[4],
    fields[5],
    micro ~/ 1000,
    micro % 1000,
  );
  if (fields[0] < 1 ||
      fields[0] > 9999 ||
      result.year != fields[0] ||
      result.month != fields[1] ||
      result.day != fields[2] ||
      result.hour != fields[3] ||
      result.minute != fields[4] ||
      result.second != fields[5]) {
    throw const FormatException('日期或时间超出范围。');
  }
  return result;
}

DateTime parseDate(String text) =>
    dayStart(parseTimestamp('${text.trim()}T00:00:00'));
DateTime parseEditorTime(String text, DateTime original) {
  text = text.trim();
  if (RegExp(r'^\d{2}:\d{2}$').hasMatch(text)) {
    text = '${dateText(original)} $text';
  }
  final value = parseTimestamp('$text:00');
  return value == minuteTime(original) ? original : value;
}

class Tag {
  const Tag(this.id, this.name, [this.parentId]);
  final String id;
  final String name;
  final String? parentId;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'parent_id': parentId,
  };
  @override
  bool operator ==(Object other) =>
      other is Tag &&
      id == other.id &&
      name == other.name &&
      parentId == other.parentId;
  @override
  int get hashCode => Object.hash(id, name, parentId);
}

class Event {
  const Event(
    this.id,
    this.title,
    this.tagId,
    this.start,
    this.end, [
    this.notes = '',
  ]);
  final String id;
  final String title;
  final String? tagId;
  final DateTime start;
  final DateTime? end;
  final String notes;
  bool get isUndefined => id.startsWith(undefinedIdPrefix);
  Event copyWith({
    String? id,
    String? title,
    String? tagId,
    bool clearTag = false,
    DateTime? start,
    DateTime? end,
    String? notes,
  }) => Event(
    id ?? this.id,
    title ?? this.title,
    clearTag ? null : tagId ?? this.tagId,
    start ?? this.start,
    end ?? this.end,
    notes ?? this.notes,
  );
  Interval? intervalOn(DateTime day) {
    if (end == null) return null;
    final left = start.isAfter(dayStart(day)) ? start : dayStart(day);
    final right = end!.isBefore(dayEnd(day)) ? end! : dayEnd(day);
    return right.isAfter(left) ? Interval(left, right) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is Event &&
      id == other.id &&
      title == other.title &&
      tagId == other.tagId &&
      start == other.start &&
      end == other.end &&
      notes == other.notes;
  @override
  int get hashCode => Object.hash(id, title, tagId, start, end, notes);
}

class Interval {
  const Interval(this.start, this.end);
  final DateTime start;
  final DateTime end;
  Duration get duration => end.difference(start);
}

int compareEvents(Event a, Event b) {
  final result = a.start.compareTo(b.start);
  return result == 0 ? compareUnicode(a.id, b.id) : result;
}

String durationText(Duration duration) {
  if (duration > Duration.zero && duration.inMinutes == 0) return '不足 1 分钟';
  final minutes = math.max(0, duration.inMinutes);
  return minutes >= 60
      ? '${minutes ~/ 60} 小时 ${(minutes % 60).toString().padLeft(2, '0')} 分'
      : '$minutes 分钟';
}

Interval defaultEventInterval(DateTime day, {DateTime? start, DateTime? now}) {
  final origin = dayStart(day);
  if (start == null) {
    now = civilTime(now ?? DateTime.now());
    if (dayStart(now) == origin) {
      final end = minuteTime(now);
      if (end == origin) {
        return Interval(origin, origin.add(const Duration(minutes: 1)));
      }
      final left = end.subtract(const Duration(hours: 1));
      return Interval(left.isBefore(origin) ? origin : left, end);
    }
    start = origin.add(const Duration(hours: 9));
  }
  final latest = minuteTime(dayEnd(day).subtract(const Duration(hours: 1)));
  start = minuteTime(start);
  start = start.isBefore(origin)
      ? origin
      : start.isAfter(latest)
      ? latest
      : start;
  return Interval(start, start.add(const Duration(hours: 1)));
}

Event moveEventOnDay(Event event, DateTime day, int minutes) {
  final interval = event.intervalOn(day);
  if (interval == null) return event;
  final lower = math.max(
    -interval.start.difference(dayStart(day)).inMinutes,
    -event.start.difference(DateTime.utc(1)).inMinutes,
  );
  final upper = math.min(
    dayEnd(day).difference(interval.end).inMinutes,
    DateTime.utc(
      9999,
      12,
      31,
      23,
      59,
      59,
      999,
      999,
    ).difference(event.end!).inMinutes,
  );
  final offset = Duration(minutes: minutes.clamp(lower, upper));
  return event.copyWith(
    start: event.start.add(offset),
    end: event.end!.add(offset),
  );
}

String _gapId(List<String> parts) =>
    '$undefinedIdPrefix${const Uuid().v5(Namespace.url.value, '(${parts.map(pythonStringRepr).join(', ')})').replaceAll('-', '')}';

/// Legacy leading-gap identity, used only to upgrade bounded overnight gaps.
String undefinedHeadId(DateTime day) =>
    _gapId(['daymark:undefined', 'head', dateText(day)]);

/// Derive only gaps bounded by ordinary events. Merge the complete journal
/// before filtering by day, preserving cross-midnight intervals and identities.
List<Event> undefinedEvents(Iterable<Event> events, [DateTime? day]) {
  final intervals =
      <Event>[
        for (final event in events)
          if (!event.isUndefined && event.end != null) event,
      ]..sort((a, b) {
        var result = a.start.compareTo(b.start);
        if (result == 0) result = a.end!.compareTo(b.end!);
        return result == 0 ? compareUnicode(a.id, b.id) : result;
      });
  final gaps = <Event>[];
  DateTime? end;
  String? previousId;
  for (final item in intervals) {
    final left = item.start;
    final right = item.end!;
    if (end != null && left.isAfter(end)) {
      gaps.add(
        Event(
          _gapId(['daymark:undefined', previousId!, item.id]),
          '未定义',
          null,
          end,
          left,
        ),
      );
    }
    if (end == null || !right.isBefore(end)) {
      end = right;
      previousId = item.id;
    }
  }
  return day == null
      ? gaps
      : gaps.where((gap) => gap.intervalOn(day) != null).toList();
}

class TimelineSegment {
  const TimelineSegment(
    this.event,
    this.start,
    this.end,
    this.slot,
    this.total,
  );
  final Event event;
  final DateTime start;
  final DateTime end;
  final int slot;
  final int total;
}

List<TimelineSegment> timelineSegments(Iterable<Event> events, DateTime day) {
  final starts = <DateTime, List<Event>>{};
  final ends = <DateTime, List<String>>{};
  for (final event in events) {
    final interval = event.intervalOn(day);
    if (interval == null) continue;
    (starts[interval.start] ??= []).add(event);
    (ends[interval.end] ??= []).add(event.id);
  }
  final boundaries = {...starts.keys, ...ends.keys}.toList()..sort();
  final active = <String, Event>{};
  final segments = <TimelineSegment>[];
  for (var i = 0; i < boundaries.length - 1; i++) {
    final left = boundaries[i];
    for (final id in ends[left] ?? <String>[]) {
      active.remove(id);
    }
    for (final event in starts[left] ?? <Event>[]) {
      active[event.id] = event;
    }
    final ordered = active.values.toList()..sort(compareEvents);
    for (var slot = 0; slot < ordered.length; slot++) {
      segments.add(
        TimelineSegment(
          ordered[slot],
          left,
          boundaries[i + 1],
          slot,
          ordered.length,
        ),
      );
    }
  }
  return segments;
}
