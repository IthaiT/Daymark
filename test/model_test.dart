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
  test(
    'default drafts use recent hour, including early morning and midnight',
    () {
      for (final entry in [
        (0, 0, '00:00', '00:01'),
        (0, 10, '00:00', '00:10'),
        (12, 34, '11:34', '12:34'),
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
      expect(late.start, DateTime.utc(2026, 10, 7, 23));
      expect(late.end, DateTime.utc(2026, 10, 8));
    },
  );

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
    'gap IDs and boundaries match exported Python compatibility fixtures',
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
        final gaps = undefinedEvents(
          events,
          parseDate(fixture['day']! as String),
        );
        expect(
          [
            for (final gap in gaps)
              {
                'id': gap.id,
                'start': timestampText(gap.start),
                'end': timestampText(gap.end!),
              },
          ],
          fixture['gaps'],
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
}
