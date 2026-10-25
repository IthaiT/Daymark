import 'dart:math' as math;

import 'model.dart';

class TimelineAxisSpan {
  const TimelineAxisSpan({
    required this.start,
    required this.end,
    required this.left,
    required this.width,
    required this.folded,
  });

  final DateTime start;
  final DateTime end;
  final double left;
  final double width;
  final bool folded;
  double get right => left + width;
  Duration get duration => end.difference(start);
}

/// A monotone piecewise map. Visible time shares one scale; omitted coverage
/// gets bounded break markers. No interval covered by a visible event folds.
class TimelineAxis {
  TimelineAxis._(this.day, this.width, this.spans, this.visibleDuration);

  final DateTime day;
  final double width;
  final List<TimelineAxisSpan> spans;
  final Duration visibleDuration;
  Iterable<TimelineAxisSpan> get folds => spans.where((span) => span.folded);
  bool get isFolded => spans.any((span) => span.folded);
  Duration get foldedDuration =>
      folds.fold(Duration.zero, (total, span) => total + span.duration);

  double get pixelsPerMinute {
    if (!isFolded) return width / 1440;
    final shownWidth = spans
        .where((span) => !span.folded)
        .fold(0.0, (sum, span) => sum + span.width);
    return shownWidth /
        (visibleDuration.inMicroseconds / Duration.microsecondsPerMinute);
  }

  factory TimelineAxis({
    required DateTime day,
    required double width,
    required Iterable<Event> events,
    bool foldEmptyTime = false,
  }) {
    final origin = dayStart(day);
    final limit = dayEnd(day);
    width = math.max(1, width);
    final intervals =
        events.map((event) => event.intervalOn(origin)).nonNulls.toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    final coverage = <Interval>[];
    for (final interval in intervals) {
      if (coverage.isEmpty || interval.start.isAfter(coverage.last.end)) {
        coverage.add(interval);
      } else if (interval.end.isAfter(coverage.last.end)) {
        coverage[coverage.length - 1] = Interval(
          coverage.last.start,
          interval.end,
        );
      }
    }
    final visible = coverage.fold(
      Duration.zero,
      (sum, span) => sum + span.duration,
    );
    if (!foldEmptyTime ||
        coverage.isEmpty ||
        visible == const Duration(days: 1)) {
      return TimelineAxis._(origin, width, [
        TimelineAxisSpan(
          start: origin,
          end: limit,
          left: 0,
          width: width,
          folded: false,
        ),
      ], visible);
    }
    final parts = <({DateTime start, DateTime end, bool folded})>[];
    var cursor = origin;
    for (final interval in coverage) {
      if (interval.start.isAfter(cursor)) {
        parts.add((start: cursor, end: interval.start, folded: true));
      }
      parts.add((start: interval.start, end: interval.end, folded: false));
      cursor = interval.end;
    }
    if (cursor.isBefore(limit)) {
      parts.add((start: cursor, end: limit, folded: true));
    }
    final foldCount = parts.where((part) => part.folded).length;
    final breakWidth = math.min(18.0, width * .20 / foldCount);
    final visibleWidth = width - breakWidth * foldCount;
    var left = 0.0;
    final spans = <TimelineAxisSpan>[];
    for (final (index, part) in parts.indexed) {
      final spanWidth = index == parts.length - 1
          ? width - left
          : part.folded
          ? breakWidth
          : visibleWidth *
                part.end.difference(part.start).inMicroseconds /
                visible.inMicroseconds;
      spans.add(
        TimelineAxisSpan(
          start: part.start,
          end: part.end,
          left: left,
          width: spanWidth,
          folded: part.folded,
        ),
      );
      left += spanWidth;
    }
    return TimelineAxis._(origin, width, List.unmodifiable(spans), visible);
  }

  double x(DateTime value) {
    if (!value.isAfter(day)) return 0;
    if (!value.isBefore(dayEnd(day))) return width;
    final span = spans.firstWhere((span) => value.isBefore(span.end));
    return span.left +
        span.width *
            value.difference(span.start).inMicroseconds /
            span.duration.inMicroseconds;
  }

  TimelineAxisSpan? foldAt(double offset) {
    if (offset < 0 || offset > width) return null;
    for (final span in folds) {
      if (offset >= span.left && offset < span.right) return span;
    }
    return null;
  }

  DateTime timeAt(double offset, {bool snapFold = true}) {
    if (offset <= 0) return day;
    if (offset >= width) return dayEnd(day);
    final span = spans.firstWhere((span) => offset < span.right);
    final fraction = ((offset - span.left) / span.width).clamp(0.0, 1.0);
    if (span.folded && snapFold) {
      return fraction < .5 ? span.start : span.end;
    }
    return span.start.add(
      Duration(microseconds: (span.duration.inMicroseconds * fraction).round()),
    );
  }
}
