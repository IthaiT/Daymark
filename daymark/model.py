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


def timeline_lanes(
    events: list[Event], day: date
) -> list[list[tuple[Event, datetime, datetime]]]:
    """Place overlapping records in separate lanes, ordered by start time."""
    clipped = [(event, interval) for event in events if (interval := event.interval_on(day))]
    lanes: list[list[tuple[Event, datetime, datetime]]] = []
    for event, (start, end) in sorted(clipped, key=lambda item: (item[1][0], item[1][1], item[0].id)):
        for lane in lanes:
            if lane[-1][2] <= start:
                lane.append((event, start, end))
                break
        else:
            lanes.append([(event, start, end)])
    return lanes
