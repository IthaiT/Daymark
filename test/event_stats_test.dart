import 'package:daymark/domain/event_stats.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final monday = DateTime.utc(2026, 10, 12);
  final week = StatsWindow.days(monday, DateTime.utc(2026, 10, 18));

  Event event(String id, DateTime start, DateTime end, {String? tag}) =>
      Event(id, id, tag, start, end);

  test('stats window counts days and derives the previous equal window', () {
    expect(week.days, 7);
    expect(
      week.previous,
      StatsWindow.days(DateTime.utc(2026, 10, 5), DateTime.utc(2026, 10, 11)),
    );
    expect(
      StatsWindow.days(
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 10, 18),
      ).days,
      18,
    );
  });

  test('clips events at both edges and ignores unfinished records', () {
    final overnight = event(
      'overnight',
      DateTime.utc(2026, 10, 11, 23),
      DateTime.utc(2026, 10, 12, 1),
    );
    final clipped = clippedInterval(overnight, week)!;
    expect(clipped.start, DateTime.utc(2026, 10, 12));
    expect(clipped.duration, const Duration(hours: 1));

    final outside = event(
      'outside',
      DateTime.utc(2026, 10, 19),
      DateTime.utc(2026, 10, 20),
    );
    expect(clippedInterval(outside, week), isNull);
    expect(
      clippedInterval(
        Event('open', 'open', 'linux', DateTime.utc(2026, 10, 12), null),
        week,
      ),
      isNull,
    );
  });

  test('merges overlap and touching intervals exactly once', () {
    final events = [
      event('a', DateTime.utc(2026, 10, 12, 9), DateTime.utc(2026, 10, 12, 11)),
      event(
        'b',
        DateTime.utc(2026, 10, 12, 10),
        DateTime.utc(2026, 10, 12, 12),
      ),
      event(
        'c',
        DateTime.utc(2026, 10, 12, 12),
        DateTime.utc(2026, 10, 12, 13),
      ),
    ];
    final intervals = intervalsIn(week, events);
    expect(intervals.length, 1);
    expect(intervals.single.duration, const Duration(hours: 4));
    expect(durationIn(week, events), const Duration(hours: 4));
  });

  test('filters events by predicate before clipping', () {
    final events = [
      event(
        'tagged',
        DateTime.utc(2026, 10, 13, 9),
        DateTime.utc(2026, 10, 13, 10),
        tag: 'work',
      ),
      event(
        'free',
        DateTime.utc(2026, 10, 13, 11),
        DateTime.utc(2026, 10, 13, 12),
      ),
    ];
    expect(
      durationIn(week, events, where: (event) => event.tagId == 'work'),
      const Duration(hours: 1),
    );
  });

  test('heat buckets merged time by weekday and hour', () {
    final events = [
      event(
        'evening',
        DateTime.utc(2026, 10, 13, 20),
        DateTime.utc(2026, 10, 13, 22, 30),
      ),
    ];
    final grid = heatGrid(week, events);
    expect(grid[1][20], const Duration(hours: 1));
    expect(grid[1][21], const Duration(hours: 1));
    expect(grid[1][22], const Duration(minutes: 30));
    expect(grid[0][20], Duration.zero);
  });

  test('weekly totals end on the week containing the last selected day', () {
    final events = [
      event(
        'last',
        DateTime.utc(2026, 10, 12, 9),
        DateTime.utc(2026, 10, 12, 10),
      ),
      event(
        'older',
        DateTime.utc(2026, 10, 5, 9),
        DateTime.utc(2026, 10, 5, 10),
      ),
    ];
    final totals = weeklyTotals(week, events);
    expect(totals.length, 8);
    expect(totals.last, const Duration(hours: 1));
    expect(totals[6], const Duration(hours: 1));
    expect(totals.take(6), everyElement(Duration.zero));
  });

  test(
    'shared accounting divides an overlapped span between parallel events',
    () {
      final events = [
        for (var index = 0; index < 4; index++)
          event(
            'parallel-$index',
            DateTime.utc(2026, 10, 12, 8),
            DateTime.utc(2026, 10, 12, 12),
            tag: 'tag-$index',
          ),
      ];
      for (final single in events) {
        expect(
          durationIn(week, [single]),
          const Duration(hours: 4),
          reason: 'the default accounting counts the whole span per tag',
        );
      }
      final profile = ConcurrencyProfile.of(week, events);
      expect(profile.hasOverlap, isTrue);
      expect(profile.durationOf(events), const Duration(hours: 4));
      for (final single in events) {
        expect(profile.durationOf([single]), const Duration(hours: 1));
      }
    },
  );

  test('shared accounting only divides the actually overlapped part', () {
    final morning = event(
      'morning',
      DateTime.utc(2026, 10, 12, 8),
      DateTime.utc(2026, 10, 12, 12),
    );
    final noon = event(
      'noon',
      DateTime.utc(2026, 10, 12, 10),
      DateTime.utc(2026, 10, 12, 14),
    );
    final evening = event(
      'evening',
      DateTime.utc(2026, 10, 12, 15),
      DateTime.utc(2026, 10, 12, 16),
    );
    final profile = ConcurrencyProfile.of(week, [morning, noon, evening]);
    expect(profile.durationOf([morning]), const Duration(hours: 3));
    expect(profile.durationOf([noon]), const Duration(hours: 3));
    expect(profile.durationOf([evening]), const Duration(hours: 1));
    expect(
      profile.durationOf([morning, noon, evening]),
      const Duration(hours: 7),
    );
  });

  test('shared heat grid scales every hour by the parallel count', () {
    final events = [
      for (var index = 0; index < 4; index++)
        event(
          'parallel-$index',
          DateTime.utc(2026, 10, 12, 8),
          DateTime.utc(2026, 10, 12, 12),
        ),
    ];
    final profile = ConcurrencyProfile.of(week, events);
    final single = profile.heatOf([events.first]);
    for (var hour = 8; hour < 12; hour++) {
      expect(single[0][hour], const Duration(minutes: 15));
    }
    expect(single[0][7], Duration.zero);
    expect(single[0][12], Duration.zero);
    // The whole group still covers the real wall-clock hour once.
    final all = profile.heatOf(events);
    for (var hour = 8; hour < 12; hour++) {
      expect(all[0][hour], const Duration(hours: 1));
    }
  });

  test('shared weekly totals split the same way', () {
    final events = [
      for (var index = 0; index < 2; index++)
        event(
          'parallel-$index',
          DateTime.utc(2026, 10, 12, 9),
          DateTime.utc(2026, 10, 12, 10),
        ),
    ];
    final totals = splitWeeklyTotals(week, events, [events.first]);
    expect(totals.length, 8);
    expect(totals.last, const Duration(minutes: 30));
    expect(totals[6], Duration.zero);
  });

  test('event list includes overlaps and sorts newest first', () {
    final events = [
      event(
        'old',
        DateTime.utc(2026, 10, 12, 9),
        DateTime.utc(2026, 10, 12, 10),
      ),
      event(
        'new',
        DateTime.utc(2026, 10, 17, 9),
        DateTime.utc(2026, 10, 17, 10),
      ),
      event(
        'next',
        DateTime.utc(2026, 10, 20, 9),
        DateTime.utc(2026, 10, 20, 10),
      ),
    ];
    expect(eventsIn(week, events).map((event) => event.id), ['new', 'old']);
  });
}
