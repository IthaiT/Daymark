import 'dart:convert';
import 'dart:io';

import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

final day = DateTime.utc(2026, 10, 7);
Event event(String id, String start, String? end) => Event(
  id,
  '事件',
  'linux',
  parseTimestamp('2026-10-07T$start'),
  end == null ? null : parseTimestamp('2026-10-07T$end'),
);

void main() {
  test('empty-day drafts start now for one hour, including midnight', () {
    for (final entry in [
      (0, 0, '00:00', '01:00'),
      (0, 10, '00:10', '01:10'),
      (12, 34, '12:34', '13:34'),
    ]) {
      final interval = defaultEventInterval(
        day,
        now: DateTime.utc(2026, 10, 7, entry.$1, entry.$2, 59),
      );
      expect(clockText(interval.start), entry.$3);
      expect(clockText(interval.end), entry.$4);
    }
    final past = defaultEventInterval(day, now: DateTime.utc(2026, 10, 8));
    expect(clockText(past.start), '09:00');
    final late = defaultEventInterval(
      day,
      start: DateTime.utc(2026, 10, 7, 23, 55),
    );
    expect(late.start, DateTime.utc(2026, 10, 7, 23, 55));
    expect(late.end, DateTime.utc(2026, 10, 8, 0, 55));
    final lastDay = defaultEventInterval(
      DateTime.utc(9999, 12, 31),
      start: DateTime.utc(9999, 12, 31, 23, 55),
    );
    expect(lastDay.end.year, 9999);
    expect(lastDay.duration, const Duration(hours: 1));
  });

  test('drafts follow the latest completed end and retain legacy seconds', () {
    final long = event('long', '09:00:00', '14:00:35');
    final short = event('short', '12:00:00', '13:00:00');
    final unfinished = event('unfinished', '16:00:00', null);
    final gap = Event(
      'undefined:ignored',
      '未定义',
      null,
      day.add(const Duration(hours: 18)),
      day.add(const Duration(hours: 19)),
    );
    final interval = defaultEventInterval(
      day,
      events: [short, gap, long, unfinished],
    );
    expect(interval.start, long.end);
    expect(interval.duration, const Duration(hours: 1));
    final late = event('late', '22:00:00', '23:45:00');
    expect(
      defaultEventInterval(day, events: [late]).end,
      DateTime.utc(2026, 10, 8, 0, 45),
    );
    final overnight = late.copyWith(end: DateTime.utc(2026, 10, 8, 8));
    expect(
      defaultEventInterval(day, events: [overnight]).start,
      DateTime.utc(2026, 10, 7, 23),
    );
    expect(
      defaultEventInterval(
        DateTime.utc(2026, 10, 8),
        events: [overnight],
      ).start,
      overnight.end,
    );
    expect(defaultEventInterval(day, events: [long], start: day).start, day);
  });

  test('calendar parsing rejects normalization and zone suffixes', () {
    for (final invalid in [
      '2026-02-29T00:00:00',
      '2026-13-01T00:00:00',
      '2026-10-07T24:00:00',
      '2026-10-07T09:60:00',
      '0000-01-01T00:00:00',
      '2026-10-07T09:00:00Z',
      '2026-10-07T09:00:00+08:00',
    ]) {
      expect(() => parseTimestamp(invalid), throwsFormatException);
    }
    expect(parseDate('2024-02-29'), DateTime.utc(2024, 2, 29));
  });

  test('editor preserves legacy seconds when minute text is unchanged', () {
    final original = parseTimestamp('2026-10-07T09:10:35.123456');
    expect(parseEditorTime('09:10', original), original);
    expect(parseEditorTime('2026-10-07 09:10', original), original);
    expect(
      parseEditorTime('09:11', original),
      DateTime.utc(2026, 10, 7, 9, 11),
    );
  });

  test(
    'overnight clips each day, excludes unfinished records and end at midnight',
    () {
      final night = Event(
        'night',
        '夜间',
        null,
        DateTime.utc(2026, 10, 6, 23),
        DateTime.utc(2026, 10, 7, 2),
      );
      expect(night.intervalOn(day)!.duration, const Duration(hours: 2));
      expect(
        night.intervalOn(day.subtract(const Duration(days: 1)))!.duration,
        const Duration(hours: 1),
      );
      expect(night.intervalOn(day.add(const Duration(days: 1))), isNull);
      expect(event('unfinished', '09:00:00', null).intervalOn(day), isNull);
      // Civil days have 24 hours, irrespective of the machine's DST zone.
      expect(
        dayEnd(DateTime.utc(2026, 3, 8)).difference(DateTime.utc(2026, 3, 8)),
        const Duration(days: 1),
      );
    },
  );

  test(
    'move retains full duration and seconds while clamping visible interval',
    () {
      final original = Event(
        'night',
        '夜间',
        null,
        DateTime.utc(2026, 10, 6, 23, 0, 30),
        DateTime.utc(2026, 10, 7, 2, 0, 30),
      );
      expect(moveEventOnDay(original, day, -60), original);
      final moved = moveEventOnDay(original, day, 60);
      expect(
        moved.end!.difference(moved.start),
        original.end!.difference(original.start),
      );
      expect(moved.start.second, 30);
      expect(
        moveEventOnDay(original, day, 10000).end,
        DateTime.utc(2026, 10, 7, 23, 59, 30),
      );
    },
  );

  test(
    'bounded gap IDs and boundaries match exported Python compatibility fixtures',
    () {
      final cases =
          jsonDecode(
                File(
                  'test/fixtures/model_compatibility.json',
                ).readAsStringSync(),
              )
              as List<Object?>;
      for (final raw in cases) {
        final fixture = raw! as Map<String, Object?>;
        final events = (fixture['events']! as List<Object?>).map((raw) {
          final row = raw! as Map<String, Object?>;
          return Event(
            row['id']! as String,
            '事件',
            null,
            parseTimestamp(row['start']! as String),
            row['end'] == null ? null : parseTimestamp(row['end']! as String),
          );
        }).toList();
        final fixtureDay = parseDate(fixture['day']! as String);
        final gaps = undefinedEvents(events, fixtureDay);
        // Historical fixtures retain the old day-head rule. Only interior
        // gaps remain valid; their IDs and boundaries must stay compatible.
        final expectedGaps = (fixture['gaps']! as List<Object?>)
            .where(
              (raw) =>
                  (raw! as Map<String, Object?>)['id'] !=
                  undefinedHeadId(fixtureDay),
            )
            .toList();
        expect(
          [
            for (final gap in gaps)
              {
                'id': gap.id,
                'start': timestampText(gap.start),
                'end': timestampText(gap.end!),
              },
          ],
          expectedGaps,
          reason: fixture['name']! as String,
        );
        expect(
          undefinedEvents(
            events.reversed,
            parseDate(fixture['day']! as String),
          ),
          gaps,
        );
      }
    },
  );

  test(
    'overlap splits height only during concurrency, conserving each duration',
    () {
      final events = [
        event('a', '13:00:00', '15:00:00'),
        event('b', '13:00:00', '14:00:00'),
        event('c', '13:30:00', '14:30:00'),
      ];
      final segments = timelineSegments(events, day);
      expect(segments.last.event.id, 'a');
      expect(segments.last.total, 1);
      expect(segments.any((piece) => piece.total == 3), isTrue);
      for (final item in events) {
        final duration = segments
            .where((piece) => piece.event.id == item.id)
            .fold(
              Duration.zero,
              (total, piece) => total + piece.end.difference(piece.start),
            );
        expect(duration, item.end!.difference(item.start));
      }
      expect(
        [
          for (final piece in timelineSegments(events.reversed, day))
            (piece.event.id, piece.start, piece.end, piece.slot, piece.total),
        ],
        [
          for (final piece in segments)
            (piece.event.id, piece.start, piece.end, piece.slot, piece.total),
        ],
      );
    },
  );

  test('duration labels retain minute accounting', () {
    expect(durationText(const Duration(seconds: 30)), '不足 1 分钟');
    expect(durationText(const Duration(minutes: 61)), '1 小时 01 分');
    expect(durationText(Duration.zero), '0 分钟');
  });

  test('the first overnight event has no inferred head or tail gap', () {
    final sleep = Event(
      'sleep',
      '睡觉',
      'rest',
      day.add(const Duration(hours: 23, minutes: 49)),
      day.add(const Duration(days: 1, hours: 7, minutes: 40)),
    );
    final oldHead = Event(undefinedHeadId(day), '未定义', null, day, sleep.start);
    expect(undefinedHeadId(day), 'undefined:cd030d559a60589f816b9157161c30bb');
    expect(undefinedEvents([sleep, oldHead]), isEmpty);
    for (final date in [
      day.subtract(const Duration(days: 1)),
      day,
      day.add(const Duration(days: 1)),
    ]) {
      expect(undefinedEvents([sleep, oldHead], date), isEmpty);
    }
  });

  test(
    'a midnight gap keeps one complete interval and identity on both days',
    () {
      final evening = DateTime.utc(2026, 10, 9);
      final nextDay = DateTime.utc(2026, 10, 10);
      final video = Event(
        'video',
        '视频',
        'life',
        evening.add(const Duration(hours: 22)),
        evening.add(const Duration(hours: 23, minutes: 50)),
      );
      final sleep = Event(
        'sleep',
        '睡觉',
        'rest',
        nextDay.add(const Duration(minutes: 6)),
        nextDay.add(const Duration(hours: 8)),
      );
      final gaps = undefinedEvents([video, sleep], evening);
      final gap = gaps.singleWhere((gap) => gap.start == video.end);
      expect(gap.end, sleep.start);
      expect(gap.intervalOn(evening)!.duration, const Duration(minutes: 10));
      expect(gap.intervalOn(nextDay)!.duration, const Duration(minutes: 6));
      expect(undefinedEvents([sleep, video], nextDay), [gap]);
      expect(undefinedEvents([video], nextDay), isEmpty);
    },
  );

  test(
    'bounded gaps cover empty intervening days and merge overnight overlaps',
    () {
      final first = Event(
        'first',
        '第一条',
        null,
        day.add(const Duration(hours: 9)),
        day.add(const Duration(hours: 10)),
      );
      final later = Event(
        'later',
        '之后',
        null,
        day.add(const Duration(days: 3, hours: 8)),
        day.add(const Duration(days: 3, hours: 9)),
      );
      final gap = undefinedEvents([
        first,
        later,
      ], day.add(const Duration(days: 1))).single;
      expect(gap.start, first.end);
      expect(gap.end, later.start);
      expect(
        gap.intervalOn(day.add(const Duration(days: 2)))!.duration,
        const Duration(days: 1),
      );
      final night = Event(
        'night',
        '跨午夜',
        null,
        day.add(const Duration(hours: 23)),
        day.add(const Duration(days: 1, hours: 2)),
      );
      final overlap = Event(
        'overlap',
        '重叠',
        null,
        day.add(const Duration(days: 1, hours: 1)),
        day.add(const Duration(days: 1, hours: 3)),
      );
      final morning = Event(
        'morning',
        '清晨',
        null,
        day.add(const Duration(days: 1, hours: 4)),
        day.add(const Duration(days: 1, hours: 5)),
      );
      final unfinished = Event(
        'unfinished',
        '待补全',
        null,
        day.add(const Duration(days: 1, hours: 3, minutes: 30)),
        null,
      );
      final merged = undefinedEvents([
        night,
        overlap,
        morning,
        unfinished,
      ], day.add(const Duration(days: 1))).single;
      expect(merged.start, overlap.end);
      expect(merged.end, morning.start);
      expect(
        undefinedEvents([
          night,
          night.copyWith(
            id: 'touching',
            start: night.end!,
            end: day.add(const Duration(days: 1, hours: 3)),
          ),
        ], day.add(const Duration(days: 1))),
        isEmpty,
      );
    },
  );
}
