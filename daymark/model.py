"""Data models and date math, independent of the desktop UI."""

from dataclasses import dataclass
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

    def interval_on(self, day: date, now: datetime) -> tuple[datetime, datetime] | None:
        """Clip an event to a day; a running event ends at `now`."""
        day_start = datetime.combine(day, time.min)
        day_end = day_start + timedelta(days=1)
        left, right = max(self.start, day_start), min(self.end or now, day_end)
        return (left, right) if right > left else None


def duration_text(seconds: float) -> str:
    minutes = max(0, int(seconds // 60))
    hours, minutes = divmod(minutes, 60)
    return f"{hours} 小时 {minutes:02d} 分" if hours else f"{minutes} 分钟"


def covered_seconds(intervals: list[tuple[datetime, datetime]]) -> float:
    """Union of intervals: overlapping records do not inflate covered time."""
    total = 0.0
    right = None
    for start, end in sorted(intervals):
        if right is None or start >= right:
            total += (end - start).total_seconds()
        elif end > right:
            total += (end - right).total_seconds()
        right = max(right, end) if right else end
    return total


def timeline_lanes(
    events: list[Event], day: date, now: datetime
) -> list[list[tuple[Event, datetime, datetime]]]:
    """Place overlapping records in separate lanes, ordered by start time."""
    clipped = [(event, interval) for event in events if (interval := event.interval_on(day, now))]
    lanes: list[list[tuple[Event, datetime, datetime]]] = []
    for event, (start, end) in sorted(clipped, key=lambda item: (item[1][0], item[1][1], item[0].id)):
        for lane in lanes:
            if lane[-1][2] <= start:
                lane.append((event, start, end))
                break
        else:
            lanes.append([(event, start, end)])
    return lanes
