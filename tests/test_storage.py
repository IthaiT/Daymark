import csv
import json
import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from daymark.model import Event, default_event_interval, move_event_on_day, timeline_segments, undefined_events
from daymark.storage import DataError, Store


class StorageTests(unittest.TestCase):
    def setUp(self):
        artifacts = Path(__file__).resolve().parents[1] / ".test-artifacts"
        artifacts.mkdir(exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=artifacts)
        self.addCleanup(self.directory.cleanup)
        self.store = Store(Path(self.directory.name))

    def event(self, key="event", start="2026-10-07T09:00:00", end="2026-10-07T10:00:00", tag="linux"):
        return Event(key, '学习 Linux, "驱动"', tag, datetime.fromisoformat(start),
                     datetime.fromisoformat(end) if end else None, "第一行\n第二行")

    def test_csv_round_trip_chinese_quotes_and_newlines(self):
        event = self.event()
        self.store.save_event(event)
        restored = Store(self.store.directory)
        self.assertEqual(restored.events[event.id], event)
        with restored.events_path.open(encoding="utf-8-sig", newline="") as stream:
            self.assertEqual(len(list(csv.DictReader(stream))), 1)

    def test_default_event_interval_stays_in_day_and_uses_minute_precision(self):
        day = date(2026, 10, 7)
        self.assertEqual(default_event_interval(day, now=datetime(2026, 10, 8, 12)),
                         (datetime(2026, 10, 7, 9), datetime(2026, 10, 7, 10)))
        self.assertEqual(default_event_interval(day, now=datetime(2026, 10, 7, 12, 34, 56)),
                         (datetime(2026, 10, 7, 11, 34), datetime(2026, 10, 7, 12, 34)))
        self.assertEqual(default_event_interval(day, now=datetime(2026, 10, 7, 0, 10)),
                         (datetime(2026, 10, 7), datetime(2026, 10, 7, 1)))
        self.assertEqual(default_event_interval(day, datetime(2026, 10, 7, 23, 55)),
                         (datetime(2026, 10, 7, 23), datetime(2026, 10, 8)))
        for boundary in (datetime.min, datetime.max):
            for start in (None, boundary):
                left, right = default_event_interval(boundary.date(), start, now=boundary)
                self.assertEqual(left.date(), boundary.date())
                self.assertEqual(right - left, timedelta(hours=1))
                self.assertEqual((left.second, right.second, left.microsecond, right.microsecond), (0, 0, 0, 0))

    def test_moves_preserve_seconds_and_duration_at_datetime_limits(self):
        for start, end, blocked, allowed in (
            (datetime.min + timedelta(seconds=30), datetime.min + timedelta(seconds=90), -120, 2),
            (datetime.max - timedelta(seconds=90), datetime.max - timedelta(seconds=30), 120, -2),
        ):
            with self.subTest(start=start):
                event = Event("limit", "边界", "linux", start, end, "备注")
                self.assertEqual(move_event_on_day(event, start.date(), blocked), event)
                moved = move_event_on_day(event, start.date(), allowed)
                self.assertEqual(moved.start, start + timedelta(minutes=allowed))
                self.assertEqual(moved.end, end + timedelta(minutes=allowed))
                self.assertEqual(moved.end - moved.start, end - start)
                self.assertEqual((moved.id, moved.title, moved.tag_id, moved.notes), (event.id, event.title, event.tag_id, event.notes))

    def test_undefined_events_only_fill_internal_gaps_and_merge_overlaps(self):
        day = date(2026, 10, 7)
        events = [self.event("a", end="2026-10-07T11:00:00"),
                  self.event("b", start="2026-10-07T10:00:00", end="2026-10-07T12:00:00"),
                  self.event("nested", start="2026-10-07T10:30:00", end="2026-10-07T11:30:00"),
                  self.event("c", start="2026-10-07T13:00:00", end="2026-10-07T14:00:00"),
                  self.event("touching", start="2026-10-07T14:00:00", end="2026-10-07T15:00:00")]
        gaps = undefined_events(events, day)
        self.assertEqual([(gap.start, gap.end, gap.tag_id) for gap in gaps],
                         [(datetime(2026, 10, 7, 12), datetime(2026, 10, 7, 13), None)])
        self.assertEqual(gaps, undefined_events(list(reversed(events)), day))
        self.assertFalse(undefined_events([], day))
        self.assertFalse(undefined_events(events[:1], day))

    def test_undefined_boundaries_follow_neighbors_with_stable_identity(self):
        day = date(2026, 10, 7)
        first = self.event("a")
        second = self.event("b", start="2026-10-07T12:00:00", end="2026-10-07T13:00:00")
        gap = undefined_events([first, second], day)[0]
        moved = move_event_on_day(first, day, 30)
        updated = undefined_events([moved, second], day)[0]
        self.assertEqual(updated.id, gap.id)
        self.assertEqual((updated.start, updated.end), (moved.end, second.start))
        self.assertFalse(undefined_events([move_event_on_day(first, day, 120), second], day))

    def test_undefined_events_clip_midnight_and_ignore_unfinished_or_other_days(self):
        day = date(2026, 10, 7)
        events = [self.event("night", start="2026-10-06T23:00:00", end="2026-10-07T02:00:00"),
                  self.event("late", start="2026-10-07T23:00:00", end="2026-10-08T02:00:00"),
                  self.event("unfinished", start="2026-10-07T06:00:00", end=None),
                  self.event("outside", start="2026-10-08T09:00:00", end="2026-10-08T10:00:00")]
        gaps = undefined_events(events, day)
        self.assertEqual([(gap.start, gap.end) for gap in gaps],
                         [(datetime(2026, 10, 7, 2), datetime(2026, 10, 7, 23))])
        self.assertFalse(undefined_events(events[:1], date(2026, 10, 6)))

    def test_events_accept_any_tag_level_and_unclassified_records(self):
        events = [self.event(f"event-{index}", tag=tag)
                  for index, tag in enumerate((None, "work", "embedded", "linux"))]
        for event in events:
            self.store.save_event(event)
        self.assertEqual(Store(self.store.directory).events, {event.id: event for event in events})
        self.store.reassign_events([event.id for event in events], "embedded")
        self.assertTrue(all(event.tag_id == "embedded" for event in Store(self.store.directory).events.values()))

    def test_tag_with_events_can_receive_new_and_moved_children(self):
        self.store.save_event(self.event())
        original = self.store.events_path.read_bytes()
        child = self.store.save_tag("专题", "linux")
        self.store.save_tag("课程", "linux", "course")
        restored = Store(self.store.directory)
        self.assertEqual(restored.tags[child.id].parent_id, "linux")
        self.assertEqual(restored.tags["course"].parent_id, "linux")
        self.assertEqual(restored.events["event"].tag_id, "linux")
        self.assertEqual(self.store.events_path.read_bytes(), original)

    def test_rename_and_move_parent_preserves_history(self):
        self.store.save_event(self.event())
        self.store.save_tag("技术基础", "side", "embedded")
        restored = Store(self.store.directory)
        self.assertEqual([tag.name for tag in restored.tag_ancestors(restored.events["event"].tag_id)], ["副业", "技术基础", "Linux"])

    def test_tag_cycles_and_duplicate_siblings_are_rejected(self):
        original = self.store.tags_path.read_bytes()
        with self.assertRaises(ValueError):
            self.store.save_tag("主业", "linux", "work")
        with self.assertRaises(ValueError):
            self.store.save_tag("linux", "embedded")
        self.assertEqual(self.store.tags_path.read_bytes(), original)

    def test_in_use_or_parent_tags_cannot_be_deleted(self):
        self.store.save_event(self.event())
        with self.assertRaises(ValueError):
            self.store.delete_tag("work")
        with self.assertRaises(ValueError):
            self.store.delete_tag("linux")
        self.store.reassign_events(["event"], "explore")
        self.store.delete_tag("linux")
        self.assertEqual(Store(self.store.directory).events["event"].tag_id, "explore")

    def test_cross_midnight_clips_each_day(self):
        event = self.event(start="2026-10-07T23:30:00", end="2026-10-08T00:30:00")
        self.store.save_event(event)
        for day in (date(2026, 10, 7), date(2026, 10, 8)):
            start, end = event.interval_on(day)
            self.assertEqual((end - start).total_seconds(), 1800)
        self.assertEqual(self.store.events_on(date(2026, 10, 9)), [])

    def test_partial_overlaps_share_height_only_while_both_events_are_active(self):
        cooking = self.event("cooking", "2026-10-07T13:00:00", "2026-10-07T15:00:00")
        podcast = self.event("podcast", "2026-10-07T13:00:00", "2026-10-07T14:00:00")
        segments = timeline_segments([cooking, podcast], date(2026, 10, 7))
        self.assertEqual([(item.event.id, item.start.hour, item.end.hour, item.slot, item.total) for item in segments],
                         [("cooking", 13, 14, 0, 2), ("podcast", 13, 14, 1, 2), ("cooking", 14, 15, 0, 1)])

    def test_three_way_segments_preserve_each_duration_and_are_order_independent(self):
        events = [self.event("a", "2026-10-07T09:00:00", "2026-10-07T12:00:00"),
                  self.event("b", "2026-10-07T10:00:00", "2026-10-07T13:00:00"),
                  self.event("c", "2026-10-07T11:00:00", "2026-10-07T12:00:00")]
        segments = timeline_segments(events, date(2026, 10, 7))
        self.assertEqual(segments, timeline_segments(list(reversed(events)), date(2026, 10, 7)))
        for event in events:
            seconds = sum((item.end - item.start).total_seconds() for item in segments if item.event.id == event.id)
            self.assertEqual(seconds, (event.end - event.start).total_seconds())
        self.assertEqual([item.total for item in segments if item.start.hour == 11], [3, 3, 3])
        self.assertEqual([item.event.id for item in segments if item.start.hour == 12], ["b"])

    def test_segments_clip_cross_midnight_and_ignore_unfinished_events(self):
        events = [self.event("late", "2026-10-07T23:30:00", "2026-10-08T00:30:00"),
                  self.event("morning", "2026-10-08T00:15:00", "2026-10-08T01:00:00"), self.event("unfinished", end=None)]
        segments = timeline_segments(events, date(2026, 10, 8))
        self.assertEqual([(item.event.id, item.start.minute, item.total) for item in segments],
                         [("late", 0, 1), ("late", 15, 2), ("morning", 15, 2), ("morning", 30, 1)])

    def test_legacy_missing_end_is_visible_without_accumulating_time(self):
        with self.store.events_path.open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=("id", "title", "tag_id", "start", "end", "notes"))
            writer.writeheader()
            writer.writerow({"id": "old", "title": "旧记录", "tag_id": "linux",
                             "start": "2026-10-07T09:00:32", "end": "", "notes": ""})
        original = self.store.events_path.read_bytes()
        restored = Store(self.store.directory)
        self.assertEqual([event.id for event in restored.events_on(date(2026, 10, 7))], ["old"])
        self.assertIsNone(restored.events["old"].interval_on(date(2026, 10, 7)))
        self.assertEqual(restored.events_on(date(2026, 10, 8)), [])
        self.assertEqual(restored.events_path.read_bytes(), original)

    def test_invalid_time_or_missing_tag_does_not_write(self):
        original = self.store.events_path.read_bytes()
        for event in (
            self.event(end="2026-10-07T08:00:00"),
            self.event(tag="missing"),
            self.event(start="2026-10-07T09:00:00+08:00"),
            self.event(end=None),
        ):
            with self.assertRaises(ValueError):
                self.store.save_event(event)
        self.assertEqual(self.store.events_path.read_bytes(), original)

    def test_failed_write_keeps_file_and_memory_unchanged(self):
        original = self.store.events_path.read_bytes()
        with patch("daymark.storage.os.replace", side_effect=PermissionError("文件正在使用")):
            with self.assertRaises(PermissionError):
                self.store.save_event(self.event())
        self.assertEqual(self.store.events, {})
        self.assertEqual(self.store.events_path.read_bytes(), original)
        self.assertEqual(list(self.store.directory.glob("*.tmp")), [])

    def test_corrupt_csv_is_reported_without_overwriting(self):
        original = b"id,title\nwrong,data\n"
        self.store.events_path.write_bytes(original)
        with self.assertRaises(DataError):
            Store(self.store.directory)
        self.assertEqual(self.store.events_path.read_bytes(), original)

    def test_corrupt_tags_are_reported_without_overwriting(self):
        payload = {"version": 1, "tags": [{"id": "a", "name": "循环", "parent_id": "a"}]}
        original = json.dumps(payload).encode()
        self.store.tags_path.write_bytes(original)
        with self.assertRaises(DataError):
            Store(self.store.directory)
        self.assertEqual(self.store.tags_path.read_bytes(), original)

    def test_batch_reassignment_and_delete_survive_restart(self):
        self.store.save_event(self.event("a"))
        self.store.save_event(self.event("b"))
        self.store.reassign_events(["a", "b"], None)
        self.assertTrue(all(event.tag_id is None for event in Store(self.store.directory).events.values()))
        self.store.delete_events(["a", "b"])
        self.assertEqual(Store(self.store.directory).events, {})


if __name__ == "__main__":
    unittest.main()
