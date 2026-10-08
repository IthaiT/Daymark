"""Data models and date math, independent of the desktop UI."""

from dataclasses import dataclass, replace
from datetime import date, datetime, time, timedelta


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
