"""Undo/redo history over events, drafts and gap titles, without windows."""

import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from daymark.history import History
from daymark.model import Event
from daymark.storage import Store


class HistoryTests(unittest.TestCase):
    """Mirror the application's recording: full state before and after each action."""

    def setUp(self):
        artifacts = Path(__file__).resolve().parents[1] / ".test-artifacts"
        artifacts.mkdir(exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=artifacts)
        self.addCleanup(self.directory.cleanup)
        self.store = Store(Path(self.directory.name))
        self.history = History()
        self.drafts = {}
        self.undefined_names = {}

    def event(self, key="event", title="学习", tag="linux"):
        start = datetime(2026, 10, 7, 9)
        return Event(key, title, tag, start, start.replace(hour=10), "备注")

    def capture(self):
        return (self.store.events, dict(self.drafts), dict(self.undefined_names))

    def run_action(self, action):
        before = self.capture()
        result = action()
        self.history.record(before, self.capture())
        return result

    def restore(self, snapshot):
        events, drafts, undefined_names = snapshot
        self.store.restore_events(events)
        self.drafts = dict(drafts)
        self.undefined_names = dict(undefined_names)
        return True

    def undo(self):
        return self.history.undo(self.restore)

    def redo(self):
        return self.history.redo(self.restore)

    def test_undo_and_redo_revert_and_reapply_edits(self):
        event = self.event()
        self.run_action(lambda: self.store.save_event(event))
        self.run_action(lambda: self.store.save_event(
            Event(event.id, "新名称", "linux", event.start, event.end, "备注")))
        self.assertTrue(self.undo())
        self.assertEqual(self.store.events[event.id].title, "学习")
        self.assertTrue(self.redo())
        self.assertEqual(self.store.events[event.id].title, "新名称")
        self.assertFalse(self.history.can_redo())

    def test_undo_restores_deleted_events_and_persists(self):
        event = self.event()
        self.run_action(lambda: self.store.save_event(event))
        self.run_action(lambda: self.store.delete_events([event.id]))
        self.assertTrue(self.undo())
        self.assertEqual(self.store.events[event.id], event)
        self.assertEqual(Store(self.store.directory).events, self.store.events)

    def test_undo_removes_created_drafts_one_by_one(self):
        def add_draft(key):
            self.drafts[key] = self.event(key)
        self.run_action(lambda: add_draft("first"))
        self.run_action(lambda: add_draft("second"))
        self.assertEqual(set(self.drafts), {"first", "second"})
        self.assertTrue(self.undo())
        self.assertEqual(set(self.drafts), {"first"})
        self.assertTrue(self.undo())
        self.assertFalse(self.drafts)
        self.assertTrue(self.redo())
        self.assertEqual(set(self.drafts), {"first"})

    def test_undo_restores_a_discarded_draft(self):
        self.drafts["draft"] = self.event("draft")
        self.run_action(lambda: self.drafts.clear())
        self.assertTrue(self.undo())
        self.assertEqual(self.drafts["draft"].title, "学习")

    def test_undo_returns_a_promoted_draft_to_draft_state(self):
        draft = self.event("draft", title="新记录")

        def promote():
            self.store.save_event(draft)
            self.drafts.pop("draft")
        self.drafts["draft"] = draft
        self.run_action(promote)
        self.assertNotIn("draft", self.drafts)
        self.assertTrue(self.undo())
        self.assertEqual(self.drafts["draft"], draft)
        self.assertNotIn("draft", self.store.events)

    def test_undo_reverts_a_draft_move(self):
        self.drafts["draft"] = self.event("draft")
        moved = Event("draft", "学习", "linux", datetime(2026, 10, 7, 10),
                      datetime(2026, 10, 7, 11), "备注")
        self.run_action(lambda: self.drafts.update(draft=moved))
        self.assertTrue(self.undo())
        self.assertEqual(self.drafts["draft"].start, datetime(2026, 10, 7, 9))

    def test_undo_reverts_a_pending_gap_title(self):
        self.undefined_names["gap"] = "待分类时段"
        self.run_action(lambda: self.undefined_names.clear())
        self.assertTrue(self.undo())
        self.assertEqual(self.undefined_names["gap"], "待分类时段")

    def test_new_change_discards_the_redo_branch(self):
        event = self.event()
        self.run_action(lambda: self.store.save_event(event))
        self.run_action(lambda: self.store.save_event(
            Event(event.id, "第一次修改", "linux", event.start, event.end, "备注")))
        self.undo()
        self.run_action(lambda: self.store.save_event(
            Event(event.id, "第二次修改", "linux", event.start, event.end, "备注")))
        self.assertFalse(self.redo())
        self.assertEqual(self.store.events[event.id].title, "第二次修改")

    def test_undo_after_tag_deletion_restores_the_event_unclassified(self):
        event = self.event(tag="linux")
        self.run_action(lambda: self.store.save_event(event))
        self.run_action(lambda: self.store.delete_events([event.id]))
        self.store.delete_tag("linux")
        self.assertTrue(self.undo())
        self.assertIsNone(self.store.events[event.id].tag_id)
        restored = Store(self.store.directory).events[event.id]
        self.assertEqual((restored.title, restored.tag_id), ("学习", None))

    def test_identical_state_is_not_recorded(self):
        event = self.event()
        self.run_action(lambda: self.store.save_event(event))
        self.run_action(lambda: self.store.save_event(event))
        self.assertTrue(self.undo())
        self.assertFalse(self.store.events)
        self.assertFalse(self.undo())

    def test_unwritten_gap_materialization_is_not_recorded(self):
        event = self.event()
        self.run_action(lambda: self.store.save_event(event))
        # Gap materialization bypasses run_action, as _persist_gaps bypasses _record.
        self.store.save_new_events([self.event("undefined:g", title="未定义", tag=None)])
        self.assertTrue(self.undo())
        self.assertFalse(self.store.events)


if __name__ == "__main__":
    unittest.main()
