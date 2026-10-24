import 'package:daymark/domain/calendar_activity.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Event event(
    String id,
    DateTime start,
    DateTime? end, [
    String? tag = 'work',
  ]) => Event(id, id, tag, start, end);

  test(
    'clips year edges, splits midnight and preserves leap day and seconds',
    () {
      final activity = CalendarActivity.of(
        year: 2024,
        events: [
          event(
            'head',
            DateTime.utc(2023, 12, 31, 23),
            DateTime.utc(2024, 1, 1, 1),
          ),
          event(
            'leap',
            DateTime.utc(2024, 2, 28, 23, 59, 30),
            DateTime.utc(2024, 2, 29, 1),
          ),
          event(
            'tail',
            DateTime.utc(2024, 12, 31, 23),
            DateTime.utc(2025, 1, 1, 1),
          ),
          event('open', DateTime.utc(2024, 3, 1), null),
          event(
            'undefined:gap',
            DateTime.utc(2024, 3, 1),
            DateTime.utc(2024, 4, 1),
          ),
        ],
      );
      expect(activity.on(DateTime.utc(2024)), const Duration(hours: 1));
      expect(
        activity.on(DateTime.utc(2024, 2, 28)),
        const Duration(seconds: 30),
      );
      expect(activity.on(DateTime.utc(2024, 2, 29)), const Duration(hours: 1));
      expect(activity.on(DateTime.utc(2024, 12, 31)), const Duration(hours: 1));
      expect(activity.on(DateTime.utc(2025)), Duration.zero);
      expect(activity.activeDays, 4);
      expect(activity.total, const Duration(hours: 3, seconds: 30));
    },
  );

  test('unions selected parent and child intervals, filters other tags', () {
    final activity = CalendarActivity.of(
      year: 2026,
      events: [
        event(
          'parent',
          DateTime.utc(2026, 10, 1, 9),
          DateTime.utc(2026, 10, 1, 18),
        ),
        event(
          'child',
          DateTime.utc(2026, 10, 1, 17),
          DateTime.utc(2026, 10, 1, 20),
          'child',
        ),
        event(
          'other',
          DateTime.utc(2026, 10, 1, 20),
          DateTime.utc(2026, 10, 2),
          'other',
        ),
        event(
          'free',
          DateTime.utc(2026, 10, 2, 9),
          DateTime.utc(2026, 10, 2, 10),
          null,
        ),
      ],
      where: (event) => {'work', 'child'}.contains(event.tagId),
    );
    expect(activity.on(DateTime.utc(2026, 10, 1)), const Duration(hours: 11));
    expect(activity.activeDays, 1);
  });

  test('split accounting shares time with other tags across midnight', () {
    final activity = CalendarActivity.of(
      year: 2026,
      events: [
        event(
          'work',
          DateTime.utc(2026, 10, 1, 22),
          DateTime.utc(2026, 10, 2, 2),
        ),
        event(
          'other',
          DateTime.utc(2026, 10, 1, 23),
          DateTime.utc(2026, 10, 2, 1),
          'other',
        ),
      ],
      where: (event) => event.tagId == 'work',
      splitOverlap: true,
    );
    expect(activity.on(DateTime.utc(2026, 10, 1)), const Duration(minutes: 90));
    expect(activity.on(DateTime.utc(2026, 10, 2)), const Duration(minutes: 90));
    expect(activity.total, const Duration(hours: 3));
  });

  test('scale separates overtime and rescales when the maximum increases', () {
    CalendarActivity peak(int hours) => CalendarActivity.of(
      year: 2026,
      events: [
        event(
          'peak',
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1, hours),
        ),
      ],
    );
    final twelve = peak(12);
    expect(
      [
        9,
        11,
        12,
      ].map((hours) => twelve.level(Duration(hours: hours))).toSet().length,
      3,
    );
    expect(peak(10).level(const Duration(hours: 10)), 9);
    expect(peak(20).level(const Duration(hours: 10)), 5);
    expect(peak(20).level(const Duration(hours: 20)), 9);
    expect(twelve.level(Duration.zero), 0);
  });

  test('empty and unclassified selections have independent totals', () {
    final empty = CalendarActivity.of(year: 2026, events: []);
    expect(empty.maximum, Duration.zero);
    expect(empty.total, Duration.zero);
    expect(empty.activeDays, 0);
    expect(empty.level(const Duration(hours: 1)), 0);
    final free = CalendarActivity.of(
      year: 2026,
      events: [
        event(
          'free',
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1, 2),
          null,
        ),
        event('work', DateTime.utc(2026, 1, 2), DateTime.utc(2026, 1, 2, 9)),
      ],
      where: (event) => event.tagId == null,
    );
    expect(free.total, const Duration(hours: 2));
    expect(() => free.durations.clear(), throwsUnsupportedError);
  });
}
