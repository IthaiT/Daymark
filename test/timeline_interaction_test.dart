import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/timeline_interaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 10, 7);
  final event = Event(
    'a',
    '事件',
    'work',
    day.add(const Duration(hours: 9)),
    day.add(const Duration(hours: 10)),
  );
  DragPreview drag(
    DragEdge edge,
    double minutes, {
    bool alt = false,
    List<Event>? events,
    int granularity = 1,
  }) => previewDrag(
    original: event,
    day: day,
    edge: edge,
    deltaMinutes: minutes,
    dayWidth: 1440,
    events: events ?? [event],
    alt: alt,
    granularity: granularity,
  );
  test('resize, move and boundary clamps preserve valid intervals', () {
    expect(drag(DragEdge.move, 60).event.start.hour, 10);
    expect(drag(DragEdge.move, 60).event.end!.hour, 11);
    expect(
      drag(DragEdge.start, 300).event.start,
      day.add(const Duration(hours: 9, minutes: 59)),
    );
    expect(
      drag(DragEdge.end, -300).event.end,
      day.add(const Duration(hours: 9, minutes: 1)),
    );
    expect(drag(DragEdge.move, -10000).event.start, day);
    expect(drag(DragEdge.move, 10000).event.end, dayEnd(day));
  });
  test(
    'minute precision keeps neighbor alignment within one minute and six pixels',
    () {
      expect(
        drag(DragEdge.end, 13).event.end,
        day.add(const Duration(hours: 10, minutes: 13)),
      );
      expect(
        drag(DragEdge.end, 13, alt: true).event.end,
        day.add(const Duration(hours: 10, minutes: 13)),
      );
      final neighbor = Event(
        'b',
        '相邻',
        null,
        day.add(const Duration(hours: 10, minutes: 20)),
        day.add(const Duration(hours: 11)),
      );
      expect(
        drag(DragEdge.end, 19, events: [event, neighbor]).event.end,
        neighbor.start,
      );
      expect(
        drag(DragEdge.end, 18, events: [event, neighbor]).event.end,
        day.add(const Duration(hours: 10, minutes: 18)),
      );
      expect(
        drag(DragEdge.end, 19, events: [event, neighbor], alt: true).event.end,
        day.add(const Duration(hours: 10, minutes: 19)),
      );
    },
  );
  test(
    'cross day moves retain full duration and resize preserves hidden endpoint',
    () {
      final overnight = Event(
        'night',
        '夜间',
        null,
        day.subtract(const Duration(hours: 1)),
        day.add(const Duration(hours: 2)),
      );
      final moved = previewDrag(
        original: overnight,
        day: day,
        edge: DragEdge.move,
        deltaMinutes: 60,
        dayWidth: 1440,
        events: [overnight],
      ).event;
      expect(moved.end!.difference(moved.start), const Duration(hours: 3));
      final resized = previewDrag(
        original: overnight,
        day: day,
        edge: DragEdge.end,
        deltaMinutes: 60,
        dayWidth: 1440,
        events: [overnight],
      ).event;
      expect(resized.start, overnight.start);
      expect(resized.end, day.add(const Duration(hours: 3)));
      expect([snapInterval(1), snapInterval(2), snapInterval(4)], [15, 5, 1]);
    },
  );

  test(
    'moving and resizing retain minute precision at every visible scale',
    () {
      for (final width in [650.0, 1440.0, 5760.0]) {
        for (var minute = 1; minute < 15; minute++) {
          for (final edge in DragEdge.values) {
            final result = previewDrag(
              original: event,
              day: day,
              edge: edge,
              deltaMinutes: minute.toDouble(),
              dayWidth: width,
              events: [event],
            );
            expect(result.snap, isNull);
            expect(
              result.event.start,
              edge == DragEdge.end
                  ? event.start
                  : event.start.add(Duration(minutes: minute)),
            );
            expect(
              result.event.end,
              edge == DragEdge.start
                  ? event.end
                  : event.end!.add(Duration(minutes: minute)),
            );
          }
        }
      }
      final legacy = event.copyWith(
        start: event.start.add(const Duration(seconds: 37)),
        end: event.end!.add(const Duration(seconds: 42)),
      );
      final moved = previewDrag(
        original: legacy,
        day: day,
        edge: DragEdge.move,
        deltaMinutes: 7,
        dayWidth: 650,
        events: [legacy],
      ).event;
      expect(moved.start, legacy.start.add(const Duration(minutes: 7)));
      expect(moved.end, legacy.end!.add(const Duration(minutes: 7)));
    },
  );

  test('granularity rounds moves and resizes to the selected step', () {
    expect(
      drag(DragEdge.move, 8, granularity: 15).event.start,
      event.start.add(const Duration(minutes: 15)),
    );
    expect(drag(DragEdge.move, 7, granularity: 15).event.start, event.start);
    expect(drag(DragEdge.end, 7, granularity: 15).event.end, event.end);
    expect(
      drag(DragEdge.end, 22, granularity: 15).event.end,
      event.end!.add(const Duration(minutes: 15)),
    );
    expect(
      drag(DragEdge.end, 24, granularity: 15).event.end,
      event.end!.add(const Duration(minutes: 30)),
    );
    expect(
      drag(DragEdge.start, 8, granularity: 15).event.start,
      event.start.add(const Duration(minutes: 15)),
    );
    final hourly = drag(DragEdge.move, 40, granularity: 60).event;
    expect(hourly.start, event.start.add(const Duration(hours: 1)));
    expect(hourly.end, event.end!.add(const Duration(hours: 1)));
    expect(drag(DragEdge.move, 29, granularity: 60).event.start, event.start);
  });

  test('granularity keeps events valid at the day edges', () {
    expect(
      drag(DragEdge.start, 300, granularity: 15).event.start,
      event.end!.subtract(const Duration(minutes: 15)),
    );
    expect(
      drag(DragEdge.end, -300, granularity: 15).event.end,
      event.start.add(const Duration(minutes: 15)),
    );
    final short = Event(
      'short',
      '短事件',
      null,
      day.add(const Duration(hours: 9)),
      day.add(const Duration(hours: 9, minutes: 20)),
    );
    final resized = previewDrag(
      original: short,
      day: day,
      edge: DragEdge.end,
      deltaMinutes: -10,
      dayWidth: 1440,
      events: [short],
      granularity: 60,
    ).event;
    expect(resized.end, short.end);
    final moved = previewDrag(
      original: short,
      day: day,
      edge: DragEdge.move,
      deltaMinutes: -10000,
      dayWidth: 1440,
      events: [short],
      granularity: 15,
    ).event;
    expect(moved.start, day);
    expect(moved.end, day.add(const Duration(minutes: 20)));
  });

  test('coarse granularity still aligns to a nearby neighbor', () {
    final neighbor = Event(
      'b',
      '相邻',
      null,
      day.add(const Duration(hours: 10, minutes: 3)),
      day.add(const Duration(hours: 11)),
    );
    final preview = drag(
      DragEdge.end,
      4,
      granularity: 10,
      events: [event, neighbor],
    );
    expect(preview.event.end, neighbor.start);
    expect(preview.snap, neighbor.start);
  });
}
