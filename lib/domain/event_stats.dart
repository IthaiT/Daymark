import 'model.dart';

/// Half-open civil-time window used by every statistics view.
///
/// [from] is the start of the first day and [toExclusive] is the start of the
/// day after the last selected day, so day arithmetic never depends on the
/// machine's time zone.
class StatsWindow {
  const StatsWindow(this.from, this.toExclusive);

  factory StatsWindow.days(DateTime from, DateTime toInclusive) =>
      StatsWindow(dayStart(from), dayEnd(toInclusive));

  final DateTime from;
  final DateTime toExclusive;

  int get days => toExclusive.difference(from).inDays;

  /// The immediately preceding window of the same length.
  StatsWindow get previous {
    final length = toExclusive.difference(from);
    return StatsWindow(from.subtract(length), from);
  }

  bool contains(DateTime value) =>
      !value.isBefore(from) && value.isBefore(toExclusive);

  @override
  bool operator ==(Object other) =>
      other is StatsWindow &&
      from == other.from &&
      toExclusive == other.toExclusive;

  @override
  int get hashCode => Object.hash(from, toExclusive);

  @override
  String toString() => 'StatsWindow($from, $toExclusive)';
}

/// Intersection of an event with a window, or null when they do not overlap.
/// Incomplete events and drafts without an end never contribute duration.
Interval? clippedInterval(Event event, StatsWindow window) {
  final end = event.end;
  if (end == null) return null;
  final start = event.start.isAfter(window.from) ? event.start : window.from;
  final clippedEnd = end.isBefore(window.toExclusive)
      ? end
      : window.toExclusive;
  return clippedEnd.isAfter(start) ? Interval(start, clippedEnd) : null;
}

/// Merge touching or overlapping intervals so sibling events are counted once.
List<Interval> mergedIntervals(Iterable<Interval> intervals) {
  final sorted =
      intervals.where((interval) => interval.duration > Duration.zero).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final merged = <Interval>[];
  for (final interval in sorted) {
    if (merged.isEmpty || interval.start.isAfter(merged.last.end)) {
      merged.add(interval);
      continue;
    }
    if (interval.end.isAfter(merged.last.end)) {
      merged[merged.length - 1] = Interval(merged.last.start, interval.end);
    }
  }
  return merged;
}

/// Clipped, merged intervals for the events accepted by [where].
List<Interval> intervalsIn(
  StatsWindow window,
  Iterable<Event> events, {
  bool Function(Event event)? where,
}) {
  final clipped = <Interval>[];
  for (final event in events) {
    if (where != null && !where(event)) continue;
    final interval = clippedInterval(event, window);
    if (interval != null) clipped.add(interval);
  }
  return mergedIntervals(clipped);
}

Duration durationIn(
  StatsWindow window,
  Iterable<Event> events, {
  bool Function(Event event)? where,
}) => intervalsIn(
  window,
  events,
  where: where,
).fold(Duration.zero, (sum, interval) => sum + interval.duration);

/// Events that overlap the window, newest first, for the right-hand list.
List<Event> eventsIn(
  StatsWindow window,
  Iterable<Event> events, {
  bool Function(Event event)? where,
}) {
  final result = <Event>[
    for (final event in events)
      if ((where == null || where(event)) &&
          clippedInterval(event, window) != null)
        event,
  ];
  result.sort((a, b) => b.start.compareTo(a.start));
  return result;
}

/// Minutes per weekday (Monday first) and hour, from merged intervals so an
/// overlapping pair never produces a darker cell than the actual time spent.
List<List<Duration>> heatGrid(
  StatsWindow window,
  Iterable<Event> events, {
  bool Function(Event event)? where,
}) {
  final grid = List.generate(
    7,
    (_) => List<Duration>.filled(24, Duration.zero, growable: false),
    growable: false,
  );
  for (final interval in intervalsIn(window, events, where: where)) {
    var cursor = interval.start;
    while (cursor.isBefore(interval.end)) {
      final nextHour = DateTime.utc(
        cursor.year,
        cursor.month,
        cursor.day,
        cursor.hour,
      ).add(const Duration(hours: 1));
      final end = nextHour.isBefore(interval.end) ? nextHour : interval.end;
      grid[cursor.weekday - 1][cursor.hour] += end.difference(cursor);
      cursor = end;
    }
  }
  return grid;
}

/// Eight Monday-to-Sunday buckets ending with the week that contains the last
/// day of [window]. The last entry is always the visible week.
List<Duration> weeklyTotals(
  StatsWindow window,
  Iterable<Event> events, {
  int weeks = 8,
  bool Function(Event event)? where,
}) {
  final lastDay = dayStart(
    window.toExclusive.subtract(const Duration(days: 1)),
  );
  final lastMonday = lastDay.subtract(Duration(days: lastDay.weekday - 1));
  return [
    for (var index = weeks - 1; index >= 0; index--)
      durationIn(
        StatsWindow(
          lastMonday.subtract(Duration(days: index * 7)),
          lastMonday
              .subtract(Duration(days: index * 7))
              .add(const Duration(days: 7)),
        ),
        events,
        where: where,
      ),
  ];
}
