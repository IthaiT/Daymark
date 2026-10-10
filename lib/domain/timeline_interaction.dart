import 'model.dart';

enum DragEdge { start, end, move }

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
  required double zoom,
  required double dayWidth,
  required Iterable<Event> events,
  bool alt = false,
}) {
  final origin = dayStart(day);
  var preview = edge == DragEdge.move
      ? moveEventOnDay(original, day, deltaMinutes.round())
      : original;
  var moment = edge == DragEdge.start ? original.start : original.end!;
  if (edge != DragEdge.move) {
    final minute =
        (moment.difference(origin).inMicroseconds /
                    Duration.microsecondsPerMinute +
                deltaMinutes)
            .round()
            .clamp(0, 1440);
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
    for (final value in moments) {
      final minutes =
          value.difference(origin).inMicroseconds /
          Duration.microsecondsPerMinute;
      final step = snapInterval(zoom);
      final grid = (minutes / step).round() * step;
      final targets = [
        origin.add(Duration(minutes: grid.clamp(0, 1440))),
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
            difference.abs() * dayWidth / 1440 <= 6) {
          minimum = difference.abs();
          correction = difference.round();
          snap = target;
        }
      }
    }
  }
  if (edge == DragEdge.move) {
    preview = moveEventOnDay(original, day, deltaMinutes.round() + correction);
  } else {
    moment = moment.add(Duration(minutes: correction));
    if (moment.isBefore(origin)) moment = origin;
    if (moment.isAfter(dayEnd(day))) moment = minuteTime(dayEnd(day));
    if (edge == DragEdge.start && !moment.isBefore(original.end!)) {
      moment = minuteTime(original.end!.subtract(const Duration(minutes: 1)));
      if (moment.isBefore(origin)) moment = original.start;
    } else if (edge == DragEdge.end && !moment.isAfter(original.start)) {
      moment = minuteTime(original.start).add(const Duration(minutes: 1));
      if (moment.isAfter(dayEnd(day))) moment = original.end!;
    }
    preview = edge == DragEdge.start
        ? original.copyWith(start: moment)
        : original.copyWith(end: moment);
  }
  return DragPreview(preview, snap);
}
