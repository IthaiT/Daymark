import csv
import json
import tempfile
import unittest
from datetime import date, datetime
from pathlib import Path
from unittest.mock import patch

from daymark.model import Event, timeline_lanes
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

    def test_overlaps_use_separate_lanes(self):
        for event in (
            self.event("a"),
            self.event("b", "2026-10-07T09:30:00", "2026-10-07T10:30:00"),
            self.event("c", "2026-10-07T10:00:00", "2026-10-07T11:00:00"),
        ):
            self.store.save_event(event)
        lanes = timeline_lanes(list(self.store.events.values()), date(2026, 10, 7))
        self.assertEqual(len(lanes), 2)
        self.assertEqual([item[0].id for item in lanes[0]], ["a", "c"])

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
