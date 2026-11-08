import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'unicode.dart';

const undefinedIdPrefix = 'undefined:';

/// Default titles of derived gaps. Rows written before the rename keep the old
/// wording, so both spellings still count as unfilled until someone edits them.
const gapPlaceholders = {'未定义', '空档'};

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
  final compact = RegExp(
    r'^(?:(\d{4}-\d{2}-\d{2})[T ])?(\d{2})(\d{2})$',
  ).firstMatch(text);
  if (compact != null) {
    text =
        '${compact.group(1) ?? dateText(original)} '
        '${compact.group(2)}:${compact.group(3)}';
  }
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

/// Tags of one record, in a stable order without duplicates.
///
/// The third positional argument keeps accepting a single tag id so every
/// existing call site keeps working, and it also accepts a list once a record
/// carries several tags.
List<String> normalizeTagIds(Object? value) {
  final result = <String>[];
  void add(Object? id) {
    if (id is String && id.isNotEmpty && !result.contains(id)) result.add(id);
  }

  if (value is Iterable) {
    for (final id in value) {
      add(id);
    }
  } else {
    add(value);
  }
  return List.unmodifiable(result);
}

bool sameTagIds(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class Event {
  Event(
    this.id,
    this.title,
    Object? tags,
    this.start,
    this.end, [
    this.notes = '',
    this.itemId,
  ]) : tagIds = normalizeTagIds(tags);
  final String id;
  final String title;

  /// Every tag this record was filed under. A record keeps its own copy so a
  /// later change to a project's defaults never rewrites history.
  final List<String> tagIds;
  final DateTime start;
  final DateTime? end;
  final String notes;

  /// Node of the project tree this record belongs to. Independent from
  /// [tagIds]: a record may belong to a project and carry tags at once.
  final String? itemId;
  bool get isUndefined => id.startsWith(undefinedIdPrefix);

  /// First tag, for call sites that only need one label.
  String? get tagId => tagIds.isEmpty ? null : tagIds.first;
  Event copyWith({
    String? id,
    String? title,
    List<String>? tagIds,
    bool clearTags = false,
    DateTime? start,
    DateTime? end,
    String? notes,
    String? itemId,
    bool clearItem = false,
  }) => Event(
    id ?? this.id,
    title ?? this.title,
    clearTags ? const <String>[] : tagIds ?? this.tagIds,
    start ?? this.start,
    end ?? this.end,
    notes ?? this.notes,
    clearItem ? null : itemId ?? this.itemId,
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
      sameTagIds(tagIds, other.tagIds) &&
      start == other.start &&
      end == other.end &&
      notes == other.notes &&
      itemId == other.itemId;
  @override
  int get hashCode =>
      Object.hash(id, title, Object.hashAll(tagIds), start, end, notes, itemId);
}

/// A tag or a project node, used while choosing where a record belongs.
typedef OwnerRef = ({String id, bool isItem});

extension EventOwner on Event {
  /// True when the record is filed somewhere, by project or by tag.
  OwnerRef? get owner => itemId != null
      ? (id: itemId!, isItem: true)
      : tagIds.isEmpty
      ? null
      : (id: tagIds.first, isItem: false);

  /// Adds [value] without removing the other side. Clearing passes null.
  Event withOwner(OwnerRef? value) {
    if (value == null) {
      return copyWith(clearTags: true, clearItem: true);
    }
    return value.isItem
        ? copyWith(itemId: value.id)
        : copyWith(tagIds: [value.id]);
  }
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

Interval defaultEventInterval(
  DateTime day, {
  DateTime? start,
  DateTime? now,
  Iterable<Event> events = const [],
}) {
  final origin = dayStart(day);
  if (start != null) start = minuteTime(civilTime(start));
  if (start == null) {
    for (final event in events) {
      if (event.isUndefined) continue;
      final end = event.intervalOn(origin)?.end;
      if (end != null && (start == null || end.isAfter(start))) {
        start = end;
      }
    }
    if (start == null) {
      now = civilTime(now ?? DateTime.now());
      start = dayStart(now) == origin
          ? minuteTime(now)
          : origin.add(const Duration(hours: 9));
    }
  }
  // A full day has no remaining start time; keep its new draft visible.
  start = start.isBefore(origin)
      ? origin
      : !start.isBefore(dayEnd(day))
      ? dayEnd(day).subtract(const Duration(hours: 1))
      : start;
  if (start.add(const Duration(hours: 1)).year > 9999) {
    start = dayEnd(day).subtract(const Duration(hours: 1));
  }
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
          '空档',
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

/// Recompute gap boundaries from saved classified events; stored rows supply
/// annotations only. Never pass in-memory drafts to this function.
List<Event> currentGaps(Iterable<Event> savedEvents) {
  final saved = savedEvents.toList();
  final previous = {
    for (final event in saved)
      if (event.isUndefined) event.id: event,
  };
  return [
    for (final gap in undefinedEvents(
      saved.where((event) => event.owner != null),
    ))
      _annotatedGap(gap, previous),
  ];
}

Event _annotatedGap(Event gap, Map<String, Event> previous) {
  var annotation = previous[gap.id];
  if (annotation == null && dayStart(gap.start).isBefore(dayStart(gap.end!))) {
    final legacy = previous[undefinedHeadId(gap.end!)];
    if (legacy?.end == gap.end && legacy!.start == dayStart(gap.end!)) {
      annotation = legacy;
    }
  }
  return annotation?.copyWith(
        id: gap.id,
        start: gap.start,
        end: gap.end,
        clearTags: true,
        clearItem: true,
      ) ??
      gap;
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
