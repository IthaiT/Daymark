import 'event_stats.dart';
import 'model.dart';

/// An empty selection means all tags; null selects ordinary unclassified rows.
class ActivityTagSelection {
  ActivityTagSelection(Iterable<String?> ids) : ids = Set.unmodifiable(ids);
  const ActivityTagSelection.all() : ids = const {};

  final Set<String?> ids;
  bool get isAll => ids.isEmpty;

  ActivityTagSelection add(String? id) => ActivityTagSelection({...ids, id});
  ActivityTagSelection remove(String? id) =>
      ActivityTagSelection(ids.where((value) => value != id));

  ActivityTagSelection validFor(Map<String, Tag> tags) {
    final valid = ids.where((id) => id == null || tags.containsKey(id));
    if (valid.length == ids.length) return this;
    return valid.isEmpty
        ? const ActivityTagSelection.all()
        : ActivityTagSelection(valid);
  }

  bool includes(Event event, Map<String, Tag> tags) {
    if (event.isUndefined) return false;
    if (isAll) return true;
    var id = event.tagId;
    if (id == null) return ids.contains(null);
    while (id != null) {
      if (ids.contains(id)) return true;
      id = tags[id]?.parentId;
    }
    return false;
  }
}

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

  late final List<double> _quartiles = () {
    final values =
        durations.values
            .where((value) => value > Duration.zero)
            .map((value) => value.inMicroseconds.toDouble())
            .toList()
          ..sort();
    if (values.isEmpty) return <double>[];

    // R-7 interpolation, also used by D3 and the default R quantile function.
    double quantile(double probability) {
      final rank = (values.length - 1) * probability;
      final lower = rank.floor();
      final upper = rank.ceil();
      return values[lower] + (values[upper] - values[lower]) * (rank - lower);
    }

    return [quantile(.25), quantile(.5), quantile(.75)];
  }();

  /// Zero is separate; equal values always share a right-inclusive quartile.
  int level(Duration value) {
    if (value <= Duration.zero || _quartiles.isEmpty) return 0;
    return 1 + _quartiles.where((bound) => value.inMicroseconds > bound).length;
  }
}
