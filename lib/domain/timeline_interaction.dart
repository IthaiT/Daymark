import 'dart:math' as math;

import 'model.dart';

enum DragEdge { start, end, move }

/// Round [minutes] to the closest multiple of the drag [step].
double _snap(double minutes, int step) =>
    (minutes / step).roundToDouble() * step;

int snapInterval(double zoom) => zoom < 2
    ? 15
    : zoom < 4
    ? 5
    : 1;

class DragPreview {
  const DragPreview(this.event, this.snap);
  final Event event;
  final DateTime? snap;
}

DragPreview previewDrag({
  required Event original,
  required DateTime day,
  required DragEdge edge,
  required double deltaMinutes,
  required double dayWidth,
  required Iterable<Event> events,
  bool alt = false,
  int granularity = 1,
}) {
  assert(granularity > 0);
  final origin = dayStart(day);
  // The step applies to the change, not to a global clock grid, so dragging
  // an event that starts at 09:07 by one step keeps its 07-minute offset.
  final startMinute = original.start.difference(origin).inMinutes;
  final moveMinutes =
      _snap(startMinute + deltaMinutes, granularity).round() - startMinute;
  var preview = edge == DragEdge.move
      ? moveEventOnDay(original, day, moveMinutes)
      : original;
  var moment = edge == DragEdge.start ? original.start : original.end!;
  if (edge != DragEdge.move) {
    final minute = _snap(
      moment.difference(origin).inMicroseconds /
              Duration.microsecondsPerMinute +
          deltaMinutes,
      granularity,
    ).clamp(0.0, 1440).round();
    moment = origin.add(Duration(minutes: minute));
    if (moment.isAfter(dayEnd(day))) moment = minuteTime(dayEnd(day));
  }
  DateTime? snap;
  var correction = 0;
  if (!alt) {
    final moments = edge == DragEdge.move
        ? [preview.intervalOn(day)!.start, preview.intervalOn(day)!.end]
        : [moment];
    double? minimum;
    // The step above provides precision independently of ruler ticks.
    // Neighbor alignment stays within half a step and six pixels so a
    // zoomed-out day cannot pull the event through a large time range.
    final alignment = math.max(1, granularity / 2);
    for (final value in moments) {
      final targets = [
        for (final event in events)
          if (event.id != original.id &&
              !event.isUndefined &&
              event.intervalOn(day) != null) ...[
            event.intervalOn(day)!.start,
            event.intervalOn(day)!.end,
          ],
      ];
      for (final target in targets) {
        final difference =
            target.difference(value).inMicroseconds /
            Duration.microsecondsPerMinute;
        if ((minimum == null || difference.abs() < minimum) &&
            difference.abs() <= alignment &&
            difference.abs() * dayWidth / 1440 <= 6) {
          minimum = difference.abs();
          correction = difference.round();
          snap = target;
        }
      }
    }
  }
  if (edge == DragEdge.move) {
    preview = moveEventOnDay(original, day, moveMinutes + correction);
  } else {
    // The shortest event keeps its own length when it is already below the
    // step, so a coarse step cannot stretch or jump an existing record.
    final shortest = math.min(
      granularity,
      math.max(1, original.end!.difference(original.start).inMinutes),
    );
    moment = moment.add(Duration(minutes: correction));
    if (moment.isBefore(origin)) moment = origin;
    if (moment.isAfter(dayEnd(day))) moment = minuteTime(dayEnd(day));
    if (edge == DragEdge.start && !moment.isBefore(original.end!)) {
      moment = minuteTime(original.end!.subtract(Duration(minutes: shortest)));
      if (moment.isBefore(origin)) moment = original.start;
    } else if (edge == DragEdge.end && !moment.isAfter(original.start)) {
      moment = minuteTime(original.start).add(Duration(minutes: shortest));
      if (moment.isAfter(dayEnd(day))) moment = original.end!;
    }
    preview = edge == DragEdge.start
        ? original.copyWith(start: moment)
        : original.copyWith(end: moment);
  }
  return DragPreview(preview, snap);
}
