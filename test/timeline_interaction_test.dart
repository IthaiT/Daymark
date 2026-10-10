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
  }) => previewDrag(
    original: event,
    day: day,
    edge: edge,
    deltaMinutes: minutes,
    zoom: 1,
    dayWidth: 1440,
    events: events ?? [event],
    alt: alt,
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
    'grid and neighbor snap use six pixel tolerance and Alt disables snap',
    () {
      expect(
        drag(DragEdge.end, 13).event.end,
        day.add(const Duration(hours: 10, minutes: 15)),
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
        zoom: 1,
        dayWidth: 1440,
        events: [overnight],
      ).event;
      expect(moved.end!.difference(moved.start), const Duration(hours: 3));
      final resized = previewDrag(
        original: overnight,
        day: day,
        edge: DragEdge.end,
        deltaMinutes: 60,
        zoom: 1,
        dayWidth: 1440,
        events: [overnight],
      ).event;
      expect(resized.start, overnight.start);
      expect(resized.end, day.add(const Duration(hours: 3)));
      expect([snapInterval(1), snapInterval(2), snapInterval(4)], [15, 5, 1]);
    },
  );
}
