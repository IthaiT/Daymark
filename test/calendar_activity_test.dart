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

  final tags = {
    'work': const Tag('work', '工作', null),
    'child': const Tag('child', '子项', 'work'),
    'rest': const Tag('rest', '休息', null),
    'other': const Tag('other', '其他', null),
  };

  test(
    'multi-tag selection includes descendants and ordinary unclassified',
    () {
      final selection = ActivityTagSelection(['work', 'child', 'rest', null]);
      final start = DateTime.utc(2026, 10, 1, 22);
      final events = [
        event('parent', start, start.add(const Duration(hours: 2))),
        event('child', start, start.add(const Duration(hours: 3)), 'child'),
        event('rest', start, start.add(const Duration(hours: 4)), 'rest'),
        event('free', start, start.add(const Duration(hours: 1)), null),
        event('other', start, start.add(const Duration(hours: 4)), 'other'),
        event(
          'undefined:gap',
          start,
          start.add(const Duration(hours: 5)),
          null,
        ),
      ];
      expect(
        events
            .where((event) => selection.includes(event, tags))
            .map((e) => e.id),
        ['parent', 'child', 'rest', 'free'],
      );
      for (final split in [false, true]) {
        final activity = CalendarActivity.of(
          year: 2026,
          events: events,
          where: (event) => selection.includes(event, tags),
          splitOverlap: split,
        );
        expect(
          activity.on(DateTime.utc(2026, 10, 1)),
          split ? const Duration(minutes: 93) : const Duration(hours: 2),
        );
        expect(
          activity.on(DateTime.utc(2026, 10, 2)),
          split ? const Duration(minutes: 70) : const Duration(hours: 2),
        );
      }
      expect(() => selection.ids.clear(), throwsUnsupportedError);
    },
  );

  test('selection keeps remaining stable IDs after tag deletion or a move', () {
    final selection = ActivityTagSelection(['work', 'rest', null]);
    final remaining = selection.validFor({...tags}..remove('rest'));
    expect(remaining.ids, {'work', null});
    expect(remaining.remove('work').ids, {null});
    expect(remaining.remove('work').remove(null).isAll, isTrue);
    expect(ActivityTagSelection(['missing']).validFor(tags).isAll, isTrue);
    final child = event('child', DateTime.utc(2026), null, 'child');
    expect(ActivityTagSelection(['work']).includes(child, tags), isTrue);
    expect(
      ActivityTagSelection([
        'work',
      ]).includes(child, {...tags, 'child': const Tag('child', '子项', 'other')}),
      isFalse,
    );
  });

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

  CalendarActivity distribution(List<int> minutes) => CalendarActivity.of(
    year: 2026,
    events: [
      for (final (index, value) in minutes.indexed)
        event(
          'day-$index',
          DateTime.utc(2026).add(Duration(days: index)),
          DateTime.utc(2026).add(Duration(days: index, minutes: value)),
        ),
    ],
  );

  test('quartiles interpolate active days and exclude zero-activity days', () {
    final activity = distribution([0, 60, 120, 180, 240, 300, 360, 420, 480]);
    expect(
      [
        Duration.zero,
        const Duration(microseconds: 1),
        const Duration(hours: 2, minutes: 45),
        const Duration(hours: 2, minutes: 45, microseconds: 1),
        const Duration(hours: 4, minutes: 30),
        const Duration(hours: 4, minutes: 30, microseconds: 1),
        const Duration(hours: 6, minutes: 15),
        const Duration(hours: 6, minutes: 15, microseconds: 1),
        const Duration(hours: 8),
      ].map(activity.level),
      [0, 1, 1, 2, 2, 3, 3, 4, 4],
    );
  });

  test('quartiles distinguish close work durations despite a long outlier', () {
    final activity = distribution([480, 540, 570, 600, 630, 1440]);
    expect(activity.level(const Duration(minutes: 570)), 2);
    expect(activity.level(const Duration(minutes: 630)), 4);
    expect(activity.level(const Duration(hours: 24)), 4);
  });

  test(
    'equal durations stay together and small samples remain deterministic',
    () {
      final repeated = distribution([360, 480, 480, 480, 480, 600]);
      expect(repeated.level(const Duration(hours: 8)), 1);
      expect(repeated.level(const Duration(hours: 10)), 4);
      expect(distribution([480]).level(const Duration(hours: 8)), 1);
      expect(distribution([480, 480]).level(const Duration(hours: 8)), 1);
      final pair = distribution([360, 600]);
      expect(pair.level(const Duration(hours: 6)), 1);
      expect(pair.level(const Duration(hours: 10)), 4);
    },
  );

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
