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

/// A stretch of [window] covered by exactly [count] events at every instant.
class ConcurrentSpan {
  const ConcurrentSpan(this.start, this.end, this.count);

  final DateTime start;
  final DateTime end;

  /// Events running together inside this span.
  final int count;

  Duration get duration => end.difference(start);
}

/// How a window's time is shared between concurrently running events.
///
/// The default aggregation counts an overlapped instant once per tag, so four
/// parallel events covering the same four hours add up to sixteen hours. A
/// profile built from every event of the window answers how many events are
/// running at any instant, and [durationOf] splits that instant evenly between
/// them, so the same input reports four hours in total.
///
/// Build one profile per window and reuse it for every tag, otherwise a tag
/// cannot see the other tags' events that run in parallel with it.
class ConcurrencyProfile {
  ConcurrencyProfile._(this.window, this.spans);

  factory ConcurrencyProfile.of(StatsWindow window, Iterable<Event> events) {
    final deltas = <DateTime, int>{};
    for (final event in events) {
      final interval = clippedInterval(event, window);
      if (interval == null) continue;
      deltas.update(interval.start, (value) => value + 1, ifAbsent: () => 1);
      deltas.update(interval.end, (value) => value - 1, ifAbsent: () => -1);
    }
    final points = deltas.keys.toList()..sort();
    final spans = <ConcurrentSpan>[];
    var active = 0;
    for (var index = 0; index < points.length - 1; index++) {
      active += deltas[points[index]]!;
      if (active > 0) {
        spans.add(ConcurrentSpan(points[index], points[index + 1], active));
      }
    }
    return ConcurrencyProfile._(window, spans);
  }

  final StatsWindow window;

  /// Disjoint, chronological spans tiling every covered instant of [window].
  final List<ConcurrentSpan> spans;

  /// Whether at least one instant had more than one event running.
  bool get hasOverlap => spans.any((span) => span.count > 1);

  List<Interval> _clipped(
    Iterable<Event> events,
    bool Function(Event event)? where,
  ) {
    final intervals = <Interval>[];
    for (final event in events) {
      if (where != null && !where(event)) continue;
      final interval = clippedInterval(event, window);
      if (interval != null) intervals.add(interval);
    }
    return intervals..sort((a, b) => a.start.compareTo(b.start));
  }

  /// Every span is uniform, so touching a span means covering all of it.
  int _covered(List<Interval> intervals, ConcurrentSpan span) {
    var count = 0;
    for (final interval in intervals) {
      if (!interval.start.isBefore(span.end)) break;
      if (interval.end.isAfter(span.start)) count++;
    }
    return count;
  }

  /// Duration owned by [events] once concurrent events share each instant.
  ///
  /// [events] must come from the same pool the profile was built from,
  /// otherwise a span's [ConcurrentSpan.count] does not describe them.
  Duration durationOf(
    Iterable<Event> events, {
    bool Function(Event event)? where,
  }) {
    final intervals = _clipped(events, where);
    if (intervals.isEmpty) return Duration.zero;
    var microseconds = 0.0;
    for (final span in spans) {
      final covered = _covered(intervals, span);
      if (covered == 0) continue;
      microseconds += span.duration.inMicroseconds * covered / span.count;
    }
    return Duration(microseconds: microseconds.round());
  }

  /// Weekday and hour grid using the same shared accounting as [durationOf].
  List<List<Duration>> heatOf(
    Iterable<Event> events, {
    bool Function(Event event)? where,
  }) {
    final grid = List.generate(
      7,
      (_) => List<Duration>.filled(24, Duration.zero, growable: false),
      growable: false,
    );
    final intervals = _clipped(events, where);
    if (intervals.isEmpty) return grid;
    for (final span in spans) {
      final covered = _covered(intervals, span);
      if (covered == 0) continue;
      final share = covered / span.count;
      var cursor = span.start;
      while (cursor.isBefore(span.end)) {
        final nextHour = DateTime.utc(
          cursor.year,
          cursor.month,
          cursor.day,
          cursor.hour,
        ).add(const Duration(hours: 1));
        final end = nextHour.isBefore(span.end) ? nextHour : span.end;
        grid[cursor.weekday - 1][cursor.hour] += Duration(
          microseconds: (end.difference(cursor).inMicroseconds * share).round(),
        );
        cursor = end;
      }
    }
    return grid;
  }
}

/// [weeklyTotals] under shared accounting, sharing each instant between the
/// concurrent events of [allEvents].
List<Duration> splitWeeklyTotals(
  StatsWindow window,
  Iterable<Event> allEvents,
  Iterable<Event> events, {
  int weeks = 8,
  bool Function(Event event)? where,
}) {
  final pool = allEvents.toList();
  final selected = events.toList();
  final lastDay = dayStart(
    window.toExclusive.subtract(const Duration(days: 1)),
  );
  final lastMonday = lastDay.subtract(Duration(days: lastDay.weekday - 1));
  return [
    for (var index = weeks - 1; index >= 0; index--)
      ConcurrencyProfile.of(
        StatsWindow(
          lastMonday.subtract(Duration(days: index * 7)),
          lastMonday
              .subtract(Duration(days: index * 7))
              .add(const Duration(days: 7)),
        ),
        pool,
      ).durationOf(selected, where: where),
  ];
}
