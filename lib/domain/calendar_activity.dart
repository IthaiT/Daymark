import 'event_stats.dart';
import 'model.dart';

/// Daily civil-time totals for one year, independent of the visible day.
class CalendarActivity {
  CalendarActivity._(this.year, Map<DateTime, Duration> durations)
    : durations = Map.unmodifiable(durations);

  factory CalendarActivity.of({
    required int year,
    required Iterable<Event> events,
    bool Function(Event)? where,
    bool splitOverlap = false,
  }) {
    final window = StatsWindow(DateTime.utc(year), DateTime.utc(year + 1));
    final pool = events.where((event) => !event.isUndefined).toList();
    final selected = pool
        .where((event) => where == null || where(event))
        .toList();
    final totals = <DateTime, double>{};

    void add(Interval interval, double share) {
      var cursor = interval.start;
      while (cursor.isBefore(interval.end)) {
        final day = dayStart(cursor);
        final midnight = day.add(const Duration(days: 1));
        final end = midnight.isBefore(interval.end) ? midnight : interval.end;
        totals.update(
          day,
          (value) => value + end.difference(cursor).inMicroseconds * share,
          ifAbsent: () => end.difference(cursor).inMicroseconds * share,
        );
        cursor = end;
      }
    }

    if (splitOverlap) {
      final profile = ConcurrencyProfile.of(window, pool);
      final intervals = [
        for (final event in selected)
          if (clippedInterval(event, window) case final Interval interval)
            interval,
      ];
      for (final span in profile.spans) {
        final count = intervals
            .where(
              (interval) =>
                  !interval.start.isAfter(span.start) &&
                  !interval.end.isBefore(span.end),
            )
            .length;
        if (count > 0) add(Interval(span.start, span.end), count / span.count);
      }
    } else {
      for (final interval in intervalsIn(window, selected)) {
        add(interval, 1);
      }
    }
    return CalendarActivity._(year, {
      for (final entry in totals.entries)
        entry.key: Duration(microseconds: entry.value.round()),
    });
  }

  final int year;
  final Map<DateTime, Duration> durations;
  late final Duration maximum = durations.values.fold(
    Duration.zero,
    (maximum, value) => value > maximum ? value : maximum,
  );
  late final Duration total = durations.values.fold(
    Duration.zero,
    (sum, value) => sum + value,
  );
  int get activeDays =>
      durations.values.where((value) => value > Duration.zero).length;
  Duration on(DateTime day) => durations[dayStart(day)] ?? Duration.zero;

  /// Nine positive levels keep 9, 11 and 12 hours distinct at a 12-hour peak.
  /// Every tag/year uses its own peak; half the peak sits in the middle.
  int level(Duration value) =>
      value <= Duration.zero || maximum <= Duration.zero
      ? 0
      : 1 +
            (value.inMicroseconds / maximum.inMicroseconds * 8).round().clamp(
              0,
              8,
            );
}
