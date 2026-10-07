"""Desktop integration tests. These briefly open real Tk windows."""

import os
import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from daymark.app import App
from daymark.dialogs import EventDialog, ReassignDialog, TagDialog
from daymark.instance import InstanceLock
from daymark.model import Event
from daymark.storage import Store


@unittest.skipUnless(os.environ.get("DAYMARK_UI_TESTS") == "1", "Set DAYMARK_UI_TESTS=1 to open test windows")
class AppTests(unittest.TestCase):
    def setUp(self):
        artifacts = Path(__file__).resolve().parents[1] / ".test-artifacts"
        artifacts.mkdir(exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(dir=artifacts)
        self.addCleanup(self.directory.cleanup)
        self.store = Store(Path(self.directory.name))
        self.app = App(self.store)
        self.addCleanup(self.app.close)
        self.app.update()
        self.errors = patch("tkinter.messagebox.showerror", side_effect=AssertionError("Unexpected UI error"))
        self.errors.start()
        self.addCleanup(self.errors.stop)

    @staticmethod
    def fill(entry, value):
        entry.delete(0, "end")
        entry.insert(0, value)

    def test_add_event_edit_reassign_move_tag_and_delete(self):
        editor = EventDialog(self.app, self.store, self.app.refresh, date(2026, 10, 7), tag_id="linux")
        self.fill(editor.title_entry, "驱动开发")
        self.fill(editor.start_date, "2026-10-07")
        self.fill(editor.start_time, "09:00")
        self.fill(editor.end_date, "2026-10-07")
        self.fill(editor.end_time, "10:30")
        editor.save()
        self.app.day = date(2026, 10, 7)
        self.app.refresh()
        self.app.update()
        event = next(iter(self.store.events.values()))
        self.assertEqual(self.app.events_tree.get_children(), (event.id,))
        self.assertTrue(self.app.timeline.canvas.find_withtag(f"event:{event.id}"))
        self.assertEqual(self.app.metric_values[0].cget("text"), "1 小时 30 分")

        editor = EventDialog(self.app, self.store, self.app.refresh, self.app.day, event)
        self.fill(editor.title_entry, "Linux 驱动开发")
        editor.save()
        self.assertEqual(self.store.events[event.id].title, "Linux 驱动开发")

        mover = TagDialog(self.app, self.store, self.app.tag_saved, "embedded")
        mover.parent_choice.current(mover.parent_choice.ids.index("side"))
        self.fill(mover.name, "技术")
        mover.save()
        self.app.update()
        self.assertEqual(self.store.tag_path("linux"), "副业 → 技术 → Linux")
        self.assertIn("副业 → 技术 → Linux", self.app.events_tree.item(event.id, "values"))

        reassign = ReassignDialog(self.app, self.store, [event.id], self.app.refresh)
        reassign.tag.current(reassign.tag.ids.index("explore"))
        reassign.save()
        self.app.clear_filter()
        self.app.select_event(event.id)
        self.app.update()
        self.assertEqual(self.store.events[event.id].tag_id, "explore")
        with patch("tkinter.messagebox.askyesno", return_value=True):
            self.app.delete_events()
        self.assertEqual(Store(self.store.directory).events, {})

    def test_timer_restore_display_and_stop(self):
        timer = self.store.start_timer("Agent 学习", "learning", now=datetime.now() - timedelta(minutes=20))
        self.app.store = Store(self.store.directory)
        self.app.timeline.store = self.app.store
        self.app.refresh()
        self.assertIn("Agent 学习", self.app.timer_text.get())
        self.assertEqual(str(self.app.start_button.cget("state")), "disabled")
        self.app.stop_timer()
        self.assertIsNotNone(Store(self.store.directory).events[timer.id].end)
        self.assertEqual(str(self.app.stop_button.cget("state")), "disabled")

    def test_filter_cross_day_timeline_selection_and_zoom(self):
        start = datetime(2026, 10, 7, 23, 30)
        self.store.save_event(Event("late", "夜间学习", "linux", start, start + timedelta(hours=1)))
        self.store.save_event(Event("other", "探索", "explore", start, start + timedelta(minutes=15)))
        self.app.day = date(2026, 10, 8)
        self.app.tags_tree.selection_set("work")
        self.app.update()
        self.app.refresh()
        self.assertEqual(self.app.events_tree.get_children(), ("late",))
        self.assertEqual(self.app.events_tree.item("late", "values")[-1], "30 分钟")
        self.app.timeline.on_select("late")
        self.app.update()
        self.assertEqual(self.app.events_tree.selection(), ("late",))
        self.app.zoom_choice.current(2)
        self.app.zoom_changed()
        self.assertEqual(self.app.timeline.zoom, 4)
        self.app.clear_filter()
        self.app.shift_day(-1)
        self.assertEqual(len(self.app.events_tree.get_children()), 2)

    def test_single_instance_lock_released_after_close(self):
        lock = InstanceLock(self.store.directory)
        try:
            with self.assertRaises(ValueError):
                InstanceLock(self.store.directory)
        finally:
            lock.close()
        lock = InstanceLock(self.store.directory)
        lock.close()


if __name__ == "__main__":
    unittest.main()
