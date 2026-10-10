"""Undo/redo history over the event table, without opening windows."""

import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from daymark.history import History
from daymark.model import Event
from daymark.storage import Store


class HistoryTests(unittest.TestCase):
    def setUp(self):
        artifacts = Path(__file__).resolve().parents[1] / ".test-artifacts"
        artifacts.mkdir(exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=artifacts)
        self.addCleanup(self.directory.cleanup)
        self.store = Store(Path(self.directory.name))
        self.history = History()
        self.store.on_events_change = self.history.record

    def event(self, key="event", title="学习", tag="linux"):
        start = datetime(2026, 10, 7, 9)
        return Event(key, title, tag, start, start.replace(hour=10), "备注")

    def test_undo_and_redo_revert_and_reapply_edits(self):
        event = self.event()
        self.store.save_event(event)
        self.store.save_event(Event(event.id, "新名称", "linux", event.start, event.end, "备注"))
        self.assertTrue(self.history.undo(self.store.restore_events))
        self.assertEqual(self.store.events[event.id].title, "学习")
        self.assertTrue(self.history.redo(self.store.restore_events))
        self.assertEqual(self.store.events[event.id].title, "新名称")
        self.assertFalse(self.history.can_redo())

    def test_undo_restores_deleted_events_and_persists(self):
        event = self.event()
        self.store.save_event(event)
        self.store.delete_events([event.id])
        self.assertTrue(self.history.undo(self.store.restore_events))
        self.assertEqual(self.store.events[event.id], event)
        self.assertEqual(Store(self.store.directory).events, self.store.events)

    def test_undo_of_a_delete_keeps_later_unrelated_events(self):
        first, second = self.event("first"), self.event("second")
        self.store.save_event(first)
        self.store.save_event(second)
        self.store.delete_events([first.id])
        self.assertTrue(self.history.undo(self.store.restore_events))
        self.assertEqual(set(self.store.events), {"first", "second"})

    def test_new_change_discards_the_redo_branch(self):
        event = self.event()
        self.store.save_event(event)
        self.store.save_event(Event(event.id, "第一次修改", "linux", event.start, event.end, "备注"))
        self.history.undo(self.store.restore_events)
        self.store.save_event(Event(event.id, "第二次修改", "linux", event.start, event.end, "备注"))
        self.assertFalse(self.history.redo(self.store.restore_events))
        self.assertEqual(self.store.events[event.id].title, "第二次修改")

    def test_undo_after_tag_deletion_restores_the_event_unclassified(self):
        event = self.event(tag="linux")
        self.store.save_event(event)
        self.store.delete_events([event.id])
        self.store.delete_tag("linux")
        self.assertTrue(self.history.undo(self.store.restore_events))
        self.assertIsNone(self.store.events[event.id].tag_id)
        restored = Store(self.store.directory).events[event.id]
        self.assertEqual((restored.title, restored.tag_id), ("学习", None))

    def test_identical_rewrite_is_not_recorded(self):
        event = self.event()
        self.store.save_event(event)
        self.store.save_event(event)
        self.assertTrue(self.history.undo(self.store.restore_events))
        self.assertFalse(self.store.events)
        self.assertFalse(self.history.undo(self.store.restore_events))

    def test_restores_are_not_recorded_as_new_changes(self):
        event = self.event()
        self.store.save_event(event)
        self.history.undo(self.store.restore_events)
        self.assertFalse(self.store.events)
        self.assertTrue(self.history.can_redo())
        self.assertFalse(self.history.can_undo())


if __name__ == "__main__":
    unittest.main()
