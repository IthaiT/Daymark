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

    def test_rename_and_move_parent_preserves_history(self):
        self.store.save_event(self.event())
        self.store.save_tag("技术基础", "side", "embedded")
        restored = Store(self.store.directory)
        self.assertEqual(restored.tag_path(restored.events["event"].tag_id), "副业 → 技术基础 → Linux")

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
        self.assertEqual(self.store.summary(date(2026, 10, 7))[0], 1800)
        self.assertEqual(self.store.summary(date(2026, 10, 8))[0], 1800)
        self.assertEqual(self.store.events_on(date(2026, 10, 9)), [])

    def test_overlaps_use_separate_lanes_and_union_coverage(self):
        for event in (
            self.event("a"),
            self.event("b", "2026-10-07T09:30:00", "2026-10-07T10:30:00"),
            self.event("c", "2026-10-07T10:00:00", "2026-10-07T11:00:00"),
        ):
            self.store.save_event(event)
        total, covered, groups = self.store.summary(date(2026, 10, 7))
        self.assertEqual((total, covered, groups["work"]), (10800, 7200, 10800))
        lanes = timeline_lanes(list(self.store.events.values()), date(2026, 10, 7), datetime.now())
        self.assertEqual(len(lanes), 2)
        self.assertEqual([item[0].id for item in lanes[0]], ["a", "c"])

    def test_timer_survives_restart_and_only_one_can_run(self):
        timer = self.store.start_timer("课程学习", "course", now=datetime(2026, 10, 7, 23, 50))
        restored = Store(self.store.directory)
        self.assertEqual(restored.running_event, timer)
        with self.assertRaises(ValueError):
            restored.start_timer("另一个任务", None)
        restored.stop_timer(datetime(2026, 10, 8, 0, 10))
        final = Store(self.store.directory)
        self.assertIsNone(final.running_event)
        self.assertEqual(final.summary(date(2026, 10, 8))[0], 600)

    def test_timer_can_be_stopped_in_the_same_second(self):
        now = datetime(2026, 10, 7, 9)
        timer = self.store.start_timer("短任务", None, now=now)
        self.store.stop_timer(now)
        self.assertEqual((Store(self.store.directory).events[timer.id].end - now).total_seconds(), 1)

    def test_invalid_time_or_missing_tag_does_not_write(self):
        original = self.store.events_path.read_bytes()
        for event in (
            self.event(end="2026-10-07T08:00:00"),
            self.event(tag="missing"),
            self.event(start="2026-10-07T09:00:00+08:00"),
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
