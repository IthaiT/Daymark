import 'package:daymark/domain/event_stats.dart';
import 'package:daymark/domain/event_summary.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 10, 11);
  Event event(String id, String title, String? tag, int start, int end) =>
      Event(
        id,
        title,
        tag,
        day.add(Duration(minutes: start)),
        day.add(Duration(minutes: end)),
      );

  test(
    'stable tag IDs group different titles and preserve all original names',
    () {
      final events = [
        event('a', 'Daymark', 'project', 690, 750),
        event('b', 'Daymark', 'project', 870, 960),
        event('c', 'Daymark开发', 'project', 990, 1050),
        event('d', 'Daymark', 'other', 1260, 1290),
        event('e', 'daymark', 'project', 1300, 1320),
      ];
      final groups = eventGroups(events.reversed, day);
      expect(groups.length, 2);
      expect(groups.first.events.map((event) => event.id), [
        'a',
        'b',
        'c',
        'e',
      ]);
      expect(groups.first.events.map((event) => event.title), [
        'Daymark',
        'Daymark',
        'Daymark开发',
        'daymark',
      ]);
      expect(groups.first.duration, const Duration(minutes: 230));
      expect(groups.first.hasSummary, isTrue);
      expect(groups.skip(1).every((group) => !group.hasSummary), isTrue);
      expect(events.first.title, 'Daymark');
    },
  );

  test(
    'unclassified and renamed derived gaps share the last bucket without losing names',
    () {
      final groups = eventGroups([
        event('undefined:a', '赖床', null, 612, 690),
        event('u', '吃饭 看番', null, 750, 870),
        event('undefined:b', '未定义', null, 1320, 1440),
        event('a', 'Daymark', 'project', 690, 750),
      ], day);
      expect(groups.length, 2);
      expect(groups.last.isUnclassified, isTrue);
      expect(groups.last.events.map((event) => event.title), [
        '赖床',
        '吃饭 看番',
        '未定义',
      ]);
      expect(groups.last.duration, const Duration(minutes: 318));
    },
  );

  test(
    'daily totals clip midnight, union overlaps and keep second precision',
    () {
      final events = [
        event('night', 'Daymark开发', 'project', -110, 10),
        event('a', 'Daymark设计', 'project', 60, 180),
        event('b', 'Daymark排查', 'project', 120, 240),
        event('c', 'Daymark', 'project', 240, 300),
        event('late', 'Daymark', 'project', 1380, 1500),
        Event(
          'seconds',
          'Daymark',
          'project',
          day.add(const Duration(minutes: 350)),
          day.add(const Duration(minutes: 350, seconds: 35)),
        ),
      ];
      final group = eventGroups(events, day).single;
      expect(group.duration, const Duration(minutes: 310, seconds: 35));
      expect(group.hasOverlap, isTrue);
      expect(group.events.first.start.isBefore(day), isTrue);
      expect(group.events.last.end!.isAfter(dayEnd(day)), isTrue);
      expect(
        eventGroups(events, day.add(const Duration(days: 1))).single.duration,
        const Duration(hours: 1),
      );
      expect(
        eventGroups(events, day.subtract(const Duration(days: 2))),
        isEmpty,
      );
    },
  );

  test('shared accounting divides parallel tags inside one day', () {
    final events = [
      for (var index = 0; index < 4; index++)
        event('parallel-$index', '并行 $index', 'tag-$index', 480, 720),
    ];
    final profile = ConcurrencyProfile.of(StatsWindow.days(day, day), events);
    final groups = eventGroups(events, day, profile: profile);
    expect(groups.length, 4);
    for (final group in groups) {
      expect(group.duration, const Duration(hours: 1));
    }
    expect(
      groups.fold(Duration.zero, (sum, group) => sum + group.duration),
      const Duration(hours: 4),
    );
    expect(
      eventGroups(
        events,
        day,
      ).every((group) => group.duration == const Duration(hours: 4)),
      isTrue,
      reason: 'without a profile each tag still claims the whole span',
    );
  });

  test(
    'drafts stay separate and unfinished records contribute no invented time',
    () {
      final groups = eventGroups(
        [
          event('draft-a', '', null, 600, 660),
          event('draft-b', '', null, 660, 720),
          Event(
            'old',
            'Daymark',
            'project',
            day.add(const Duration(hours: 15)),
            null,
          ),
          event('saved', 'Daymark', 'project', 900, 960),
          event('u', '未分类记录', null, 1200, 1260),
        ],
        day,
        draftIds: {'draft-a', 'draft-b'},
      );
      expect(groups.length, 4);
      expect(
        groups.take(2).every((group) => group.isDraft && !group.hasSummary),
        isTrue,
      );
      expect(groups[2].duration, const Duration(hours: 1));
      expect(groups[2].incompleteCount, 1);
      expect(groups.last.isUnclassified, isTrue);
    },
  );
}
