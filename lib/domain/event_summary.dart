import 'model.dart';

typedef EventGroupKey = ({String? tagId, String? draftId});

class EventGroup {
  EventGroup(this.key, Iterable<Event> events, DateTime day)
    : events = List.unmodifiable(events) {
    final intervals =
        this.events.map((event) => event.intervalOn(day)).nonNulls.toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    var total = Duration.zero;
    var sum = Duration.zero;
    DateTime? start;
    DateTime? end;
    for (final interval in intervals) {
      sum += interval.duration;
      if (end == null || interval.start.isAfter(end)) {
        if (end != null) total += end.difference(start!);
        start = interval.start;
        end = interval.end;
      } else if (interval.end.isAfter(end)) {
        end = interval.end;
      }
    }
    if (end != null) total += end.difference(start!);
    duration = total;
    hasOverlap = sum > total;
  }

  final EventGroupKey key;
  final List<Event> events;
  late final Duration duration;
  late final bool hasOverlap;
  bool get isDraft => key.draftId != null;
  bool get isUnclassified => key.tagId == null && !isDraft;
  bool get hasSummary => !isDraft && (isUnclassified || events.length > 1);
  int get incompleteCount => events.where((event) => event.end == null).length;
}

/// Group stable tag identities while preserving each record's original name.
List<EventGroup> eventGroups(
  Iterable<Event> events,
  DateTime day, {
  Set<String> draftIds = const {},
}) {
  final buckets = <EventGroupKey, List<Event>>{};
  final ordered =
      events
          .where(
            (event) =>
                event.intervalOn(day) != null ||
                event.end == null && dayStart(event.start) == dayStart(day),
          )
          .toList()
        ..sort(compareEvents);
  for (final event in ordered) {
    final draft = draftIds.contains(event.id);
    final unclassified = event.isUndefined || event.tagId == null;
    final key = (
      tagId: draft || unclassified ? null : event.tagId,
      draftId: draft ? event.id : null,
    );
    (buckets[key] ??= []).add(event);
  }
  return [
    for (final entry in buckets.entries)
      EventGroup(entry.key, entry.value, day),
  ]..sort((a, b) {
    if (a.isDraft != b.isDraft) return a.isDraft ? -1 : 1;
    if (a.isUnclassified != b.isUnclassified) return a.isUnclassified ? 1 : -1;
    if (!a.isDraft) {
      final duration = b.duration.compareTo(a.duration);
      if (duration != 0) return duration;
    }
    return compareEvents(a.events.first, b.events.first);
  });
}
