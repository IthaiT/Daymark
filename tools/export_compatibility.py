"""Export synthetic Python-model fixtures without accessing personal data."""
import json
from dataclasses import asdict
from datetime import date, datetime
from pathlib import Path

from daymark.model import Event, undefined_events

day = date(2026, 10, 7)

def event(key, start, end):
    return Event(key, "事件", None, datetime.fromisoformat(start),
                 datetime.fromisoformat(end) if end else None)

cases = {
    "empty": [],
    "leading and interior": [event("a", "2026-10-07T09:00:00", "2026-10-07T10:00:00"),
                             event("b", "2026-10-07T12:00:00", "2026-10-07T13:00:00")],
    "overlap": [event("a", "2026-10-07T09:00:00", "2026-10-07T11:00:00"),
                event("b", "2026-10-07T10:00:00", "2026-10-07T12:00:00"),
                event("c", "2026-10-07T13:00:00", "2026-10-07T14:00:00")],
    "overnight": [event("night", "2026-10-06T23:00:00", "2026-10-07T02:00:00"),
                  event("late", "2026-10-07T23:00:00", "2026-10-08T02:00:00"),
                  event("unfinished", "2026-10-07T06:00:00", None)],
    "quoted Unicode IDs": [event("中文'双引号\"\\", "2026-10-07T09:00:30", "2026-10-07T10:00:30"),
                            event("另一行\n", "2026-10-07T12:00:00", "2026-10-07T13:00:00")],
}
fixtures = []
for name, events in cases.items():
    fixtures.append({"name": name, "day": day.isoformat(),
                     "events": [{"id": item.id, "start": item.start.isoformat(),
                                 "end": item.end.isoformat() if item.end else None} for item in events],
                     "gaps": [{"id": item.id, "start": item.start.isoformat(), "end": item.end.isoformat()}
                              for item in undefined_events(events, day)]})
target = Path("test/fixtures/model_compatibility.json")
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(json.dumps(fixtures, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
