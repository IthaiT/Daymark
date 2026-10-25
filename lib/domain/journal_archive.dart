import 'model.dart';

/// Bounded gaps fill the span between saved, completed ordinary events.
/// Neither drafts nor stored legacy gap rows establish coverage.
Set<DateTime> completedJournalDays(Iterable<Event> events, DateTime now) {
  DateTime? first;
  DateTime? last;
  for (final event in events) {
    if (event.isUndefined || event.end == null) continue;
    if (first == null || event.start.isBefore(first)) first = event.start;
    if (last == null || event.end!.isAfter(last)) last = event.end;
  }
  if (first == null || last == null) return {};
  var day = dayStart(first);
  if (first.isAfter(day)) day = day.add(const Duration(days: 1));
  final today = dayStart(now);
  final end = last.isBefore(today) ? dayStart(last) : today;
  return {
    for (; day.isBefore(end); day = day.add(const Duration(days: 1))) day,
  };
}

bool eventTouchesDays(Event event, Set<DateTime> days) {
  var day = dayStart(event.start);
  if (event.end == null) return days.contains(day);
  while (day.isBefore(event.end!)) {
    if (days.contains(day)) return true;
    day = day.add(const Duration(days: 1));
  }
  return false;
}
