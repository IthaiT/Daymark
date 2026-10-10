"""Data models and date math, independent of the desktop UI."""

from dataclasses import dataclass, replace
from datetime import date, datetime, time, timedelta
from uuid import NAMESPACE_URL, uuid5

# Rows with this id prefix mirror derived undefined gaps; they are persisted
# so gap titles survive restarts but never behave as regular records.
UNDEFINED_ID_PREFIX = "undefined:"


@dataclass(frozen=True)
class Tag:
    id: str
    name: str
    parent_id: str | None = None


@dataclass(frozen=True)
class Event:
    id: str
    title: str
    tag_id: str | None
    start: datetime
    end: datetime | None
    notes: str = ""

    def interval_on(self, day: date) -> tuple[datetime, datetime] | None:
        """Clip a completed event to a day without inferring a missing end."""
        if self.end is None:
            return None
        day_start = datetime.combine(day, time.min)
        day_end = datetime.max if day == date.max else day_start + timedelta(days=1)
        left, right = max(self.start, day_start), min(self.end, day_end)
        return (left, right) if right > left else None


def duration_text(seconds: float) -> str:
    if 0 < seconds < 60:
        return "不足 1 分钟"
    minutes = max(0, int(seconds // 60))
    hours, minutes = divmod(minutes, 60)
    return f"{hours} 小时 {minutes:02d} 分" if hours else f"{minutes} 分钟"


def default_event_interval(day: date, start: datetime | None = None,
                           now: datetime | None = None) -> tuple[datetime, datetime]:
    """Choose a one-hour draft interval within the displayed day."""
    origin = datetime.combine(day, time.min)
    limit = datetime.max if day == date.max else origin + timedelta(days=1)
    if start is None:
        now = now or datetime.now()
        if day == now.date():
            end = now.replace(second=0, microsecond=0)
            start = end - min(timedelta(hours=1), end - origin)
        else:
            start = origin + timedelta(hours=9)
    latest = (limit - timedelta(hours=1)).replace(second=0, microsecond=0)
    start = min(latest, max(origin, start.replace(second=0, microsecond=0)))
    return start, start + timedelta(hours=1)


def move_event_on_day(event: Event, day: date, minutes: int) -> Event:
    """Shift both endpoints equally, keeping the visible interval inside the day."""
    interval = event.interval_on(day)
    if interval is None:
        return event
    start, end = interval
    origin = datetime.combine(day, time.min)
    limit = datetime.max if day == date.max else origin + timedelta(days=1)
    minute = timedelta(minutes=1)
    lower = max(-((start - origin) // minute), -((event.start - datetime.min) // minute))
    upper = min((limit - end) // minute, (datetime.max - event.end) // minute)
    offset = timedelta(minutes=min(upper, max(lower, minutes)))
    return replace(event, start=event.start + offset, end=event.end + offset)


def undefined_events(events: list[Event], day: date) -> list[Event]:
    """Derive gaps between the union of completed intervals, without storing them.

    The day's leading span counts as a gap too, so overnight boundary time can be
    named; time after the last event stays blank by design (the next day's leading
    gap covers the boundary), as do days without a covered interval.
    """
    intervals = sorted((*interval, event.id) for event in events if (interval := event.interval_on(day)))
    origin = datetime.combine(day, time.min)

    def leading_gap(start: datetime, end: datetime) -> Event:
        # Anchored to the day alone: adding or moving edge events resizes the
        # row instead of replacing it, so custom titles survive.
        key = uuid5(NAMESPACE_URL, repr(("daymark:undefined", "head", day.isoformat()))).hex
        return Event(f"{UNDEFINED_ID_PREFIX}{key}", "未定义", None, start, end)

    result, end, previous_id = [], None, None
    for left, right, event_id in intervals:
        if end is None:
            if left > origin:
                result.append(leading_gap(origin, left))
        elif left > end:
            key = uuid5(NAMESPACE_URL, repr(("daymark:undefined", previous_id, event_id))).hex
            result.append(Event(f"{UNDEFINED_ID_PREFIX}{key}", "未定义", None, end, left))
        if end is None or right >= end:
            end, previous_id = right, event_id
    return result


@dataclass(frozen=True)
class TimelineSegment:
    event: Event
    start: datetime
    end: datetime
    slot: int
    total: int


def timeline_segments(events: list[Event], day: date) -> list[TimelineSegment]:
    """Divide each interval equally among the events active at that time."""
    starts, ends = {}, {}
    for event in events:
        if interval := event.interval_on(day):
            start, end = interval
            starts.setdefault(start, []).append(event)
            ends.setdefault(end, []).append(event.id)
    boundaries = sorted(starts.keys() | ends.keys())
    active, segments = {}, []
    for left, right in zip(boundaries, boundaries[1:]):
        for event_id in ends.get(left, ()):
            active.pop(event_id, None)
        for event in starts.get(left, ()):
            active[event.id] = event
        ordered = sorted(active.values(), key=lambda event: (event.start, event.id))
        for slot, event in enumerate(ordered):
            segments.append(TimelineSegment(event, left, right, slot, len(ordered)))
    return segments
