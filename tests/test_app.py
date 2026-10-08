"""Desktop integration tests. These briefly open real Tk windows."""

import os
import tempfile
import unittest
from datetime import date, datetime, timedelta
from pathlib import Path
from unittest.mock import patch

from daymark.app import App
from daymark.dialogs import EventDialog
from daymark.instance import InstanceLock
from daymark.model import Event
from daymark.storage import Store
from daymark.timeline import tag_color


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
        errors = patch("tkinter.messagebox.showerror", side_effect=AssertionError("Unexpected UI error"))
        errors.start()
        self.addCleanup(errors.stop)

    @staticmethod
    def fill(entry, value):
        if hasattr(entry, "value"):
            entry.value.set(value)
        else:
            entry.delete(0, "end")
            entry.insert(0, value)

    def choose_tag(self, picker, tag_id):
        self.click(picker.button)
        tree = picker.popup.tree
        item = f"tag:{tag_id}" if tag_id else "none"
        tree.see(item)
        self.app.update()
        x, y, width, height = tree.bbox(item)
        self.click(tree, x + 110, y + height // 2)

    def click(self, widget, x=None, y=None):
        """Exercise Tk's mouse bindings rather than invoking widget callbacks."""
        self.app.update()
        x = widget.winfo_width() // 2 if x is None else x
        y = widget.winfo_height() // 2 if y is None else y
        coordinates = {"x": x, "y": y, "rootx": widget.winfo_rootx() + x, "rooty": widget.winfo_rooty() + y}
        widget.event_generate("<Enter>", **coordinates)
        widget.event_generate("<Motion>", **coordinates)
        widget.event_generate("<ButtonPress-1>", **coordinates)
        self.app.update()
        widget.event_generate("<ButtonRelease-1>", **coordinates)
        self.app.update()

    def type_key(self, keysym):
        focused = self.app.focus_get()
        self.assertIsNotNone(focused, "A visible editor must have keyboard focus")
        focused.event_generate("<KeyPress>", keysym=keysym)
        # Escape can destroy the popup on key press; key release goes to the
        # restored input target, as it does in the normal event loop.
        released_to = self.app.focus_get()
        self.assertIsNotNone(released_to)
        released_to.event_generate("<KeyRelease>", keysym=keysym)
        self.app.update()

    def wheel(self, delta, state=0, x=None):
        canvas = self.app.timeline.canvas
        self.app.update()
        canvas.event_generate("<MouseWheel>", delta=delta, state=state,
                              x=canvas.winfo_width() // 2 if x is None else x, y=70)
        self.app.update()

    def begin_resize(self, event_id, edge, moment):
        self.app.select_event(event_id)
        self.app.update()
        canvas = self.app.timeline.canvas
        handle = canvas.find_withtag(f"resize:{edge}:{event_id}")[0]
        left, top, right, bottom = canvas.bbox(handle)
        x, y = round((left + right) / 2 - canvas.canvasx(0)), round((top + bottom) / 2 - canvas.canvasy(0))
        canvas.event_generate("<ButtonPress-1>", x=x, y=y)
        self.app.update()
        ticks = canvas.find_withtag("time-tick")
        left, right = canvas.coords(ticks[0])[0], canvas.coords(ticks[-1])[0]
        original = getattr(self.store.events[event_id], edge)
        x = round(x + (right - left) * (moment - original).total_seconds() / 86400)
        canvas.event_generate("<B1-Motion>", x=x, y=y)
        self.app.update()
        return canvas, x, y

    def cell_event(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9)
        event = Event("cell", "原名称", "linux", start, start + timedelta(hours=1), "保留备注")
        self.store.save_event(event)
        self.app.refresh()
        self.app.update()
        return event

    def click_timeline_event(self, event_id):
        canvas = self.app.timeline.canvas
        self.app.update()
        left, top, right, bottom = canvas.bbox(canvas.find_withtag(f"event:{event_id}")[0])
        x, y = round((left + right) / 2 - canvas.canvasx(0)), round((top + bottom) / 2 - canvas.canvasy(0))
        self.click(canvas, x, y)

    def test_event_selection_matches_both_panels_and_background_click_clears_it(self):
        event = self.cell_event()
        tree, canvas = self.app.events_tree, self.app.timeline.canvas
        x, y, width, height = tree.bbox(event.id)
        self.click(tree, x + 100, y + height // 2)
        selected_color = tag_color(self.store, event.tag_id, selected=True)
        row_tag = tree.item(event.id, "tags")[0]
        self.assertEqual(self.app.timeline.selected, {event.id})
        self.assertEqual(str(tree.tag_configure(row_tag, "background")), selected_color)
        self.assertEqual(canvas.itemcget(canvas.find_withtag(f"event:{event.id}")[0], "fill"), selected_color)
        for edge in ("start", "end"):
            handle = canvas.find_withtag(f"resize:{edge}:{event.id}")[0]
            self.assertEqual(canvas.type(handle), "line")
            self.assertEqual(canvas.itemcget(handle, "fill"), "#111111")
            self.assertEqual(canvas.itemcget(handle, "arrow"), "last")
        for widget, xpos, ypos in ((canvas, 12, 25), (tree, 100, tree.winfo_height() - 10),
                                   (self.app.events_heading, 10, 10)):
            self.app.select_event(event.id)
            self.app.update()
            self.click(widget, xpos, ypos)
            self.assertEqual(tree.selection(), ())
            self.assertFalse(self.app.timeline.selected)
            self.assertFalse(canvas.find_withtag(f"resize:start:{event.id}"))
            self.assertFalse(canvas.find_withtag(f"resize:end:{event.id}"))
            self.assertEqual(str(tree.tag_configure(row_tag, "background")), tag_color(self.store, event.tag_id))
        self.click_timeline_event(event.id)
        self.assertEqual(tree.selection(), (event.id,))
        self.assertEqual(str(tree.tag_configure(row_tag, "background")), selected_color)

    def test_delete_key_works_in_both_panels_and_respects_cancel_and_multiselection(self):
        event = self.cell_event()
        for key, hours in (("second", 2), ("third", 4)):
            self.store.save_event(Event(key, key, "explore", event.start + timedelta(hours=hours), event.end + timedelta(hours=hours)))
        self.app.refresh()
        self.click_timeline_event(event.id)
        original = self.store.events_path.read_bytes()
        with patch("tkinter.messagebox.askyesno", return_value=False) as confirm:
            self.type_key("Delete")
            confirm.assert_called_once()
        self.assertEqual(self.store.events_path.read_bytes(), original)
        with patch("tkinter.messagebox.askyesno", return_value=True):
            self.type_key("Delete")
        self.assertNotIn(event.id, Store(self.store.directory).events)
        self.assertFalse(self.app.timeline.selected)
        self.app.events_tree.selection_set(("second", "third"))
        self.app.events_tree.focus_force()
        self.app.update()
        with patch("tkinter.messagebox.askyesno", return_value=True) as confirm:
            self.type_key("Delete")
            confirm.assert_called_once()
        self.assertFalse(Store(self.store.directory).events)
        self.assertFalse(self.app.events_tree.get_children())
        self.assertIsNone(self.app.grab_current())

    def test_delete_key_in_an_inline_editor_only_deletes_text(self):
        event = self.cell_event()
        editor = self.double_click_cell(event.id, "title")
        self.fill(editor.entry, "abc")
        editor.entry.selection_clear()
        editor.entry.icursor(1)
        with patch("tkinter.messagebox.askyesno") as confirm:
            self.type_key("Delete")
            confirm.assert_not_called()
        self.assertEqual(editor.entry.get(), "ac")
        self.assertEqual(self.store.events[event.id], event)
        self.type_key("Escape")

    def double_click_cell(self, event_id, column):
        tree = self.app.events_tree
        tree.see(event_id)
        self.app.update()
        x, y, width, height = tree.bbox(event_id, column)
        self.click(tree, x + width // 2, y + height // 2)
        self.click(tree, x + width // 2, y + height // 2)
        self.assertIsNotNone(self.app.cell_editor)
        self.assertEqual(self.app.cell_editor.column, column)
        return self.app.cell_editor

    def test_inline_title_saves_on_enter_and_escape_discards_changes(self):
        event = self.cell_event()
        editor = self.double_click_cell(event.id, "title")
        self.assertIsNone(self.app.grab_current())
        self.type_key("x")
        self.type_key("Return")
        self.assertIsNone(self.app.cell_editor)
        self.assertEqual(Store(self.store.directory).events[event.id].title, "x")
        self.assertEqual(self.store.events[event.id].notes, event.notes)
        editor = self.double_click_cell(event.id, "title")
        self.fill(editor.entry, "取消修改")
        self.type_key("Escape")
        self.assertIsNone(self.app.cell_editor)
        self.assertEqual(self.store.events[event.id].title, "x")

    def test_inline_tag_can_select_a_parent_or_unclassified(self):
        event = self.cell_event()
        for tag_id in ("embedded", None):
            editor = self.double_click_cell(event.id, "tag")
            tree = editor.input.popup.tree
            row = f"tag:{tag_id}" if tag_id else "none"
            tree.see(row)
            self.app.update()
            x, y, width, height = tree.bbox(row)
            self.click(tree, x + 110, y + height // 2)
            self.assertIsNone(self.app.cell_editor)
            self.assertEqual(self.store.events[event.id].tag_id, tag_id)
            self.assertIsNone(self.app.grab_current())

    def test_inline_timestamp_uses_nested_pickers_and_recalculates_daily_duration(self):
        self.app.day = date(2026, 10, 7)
        event = self.cell_event()
        editor = self.double_click_cell(event.id, "end")
        popup = editor.input.popup
        self.click(popup.date.entry)
        self.click(popup.date.popup.day_buttons[8])
        self.assertEqual(self.app.grab_current(), popup)
        self.click(popup.time.entry)
        clock = popup.time.popup
        for items, index in ((clock.hours, 0), (clock.minutes, 30)):
            items.see(index)
            self.app.update()
            x, y, width, height = items.bbox(index)
            self.click(items, x + 8, y + height // 2)
        footer = clock.body.grid_slaves(row=1)[0]
        self.click(footer.winfo_children()[-1])
        self.click(popup.confirm)
        self.assertIsNone(self.app.cell_editor)
        self.assertEqual(self.store.events[event.id].end, datetime(2026, 10, 8, 0, 30))
        self.assertEqual(self.app.events_tree.item(event.id, "values")[-1], "15 小时 00 分")
        self.assertIsNone(self.app.grab_current())
        tree = self.app.events_tree
        x, y, width, height = tree.bbox(event.id, "duration")
        self.click(tree, x + width // 2, y + height // 2)
        self.click(tree, x + width // 2, y + height // 2)
        self.assertIsNone(self.app.cell_editor)

    def test_inline_invalid_time_and_failed_writes_keep_data_and_editor(self):
        event = self.cell_event()
        original = self.store.events_path.read_bytes()
        editor = self.double_click_cell(event.id, "end")
        editor.input.popup.close()
        self.fill(editor.input, "08:00")
        with patch("tkinter.messagebox.showerror") as error:
            self.type_key("Return")
            error.assert_called_once()
        self.assertIs(self.app.cell_editor, editor)
        self.assertEqual(self.store.events_path.read_bytes(), original)
        self.type_key("Escape")
        editor = self.double_click_cell(event.id, "title")
        self.fill(editor.entry, "写入失败")
        with patch.object(self.store, "_write_events", side_effect=OSError("无法保存")), patch("tkinter.messagebox.showerror") as error:
            self.type_key("Return")
            error.assert_called_once()
        self.assertIs(self.app.cell_editor, editor)
        self.assertEqual(self.store.events[event.id], event)
        self.assertEqual(self.store.events_path.read_bytes(), original)
        self.type_key("Escape")
        self.assertIsNone(self.app.grab_current())

    def test_unchanged_inline_timestamp_preserves_legacy_seconds(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9, second=32)
        event = Event("seconds", "已有秒数", "linux", start, start + timedelta(hours=1))
        self.store.save_event(event)
        self.app.refresh()
        original = self.store.events_path.read_bytes()
        editor = self.double_click_cell(event.id, "start")
        self.click(editor.input.popup.confirm)
        self.assertEqual(self.store.events[event.id], event)
        self.assertEqual(self.store.events_path.read_bytes(), original)

    def test_cancelling_inline_picker_unlocks_main_calendar(self):
        event = self.cell_event()
        self.double_click_cell(event.id, "tag")
        self.app.cancel_cell()
        self.assertIsNone(self.app.grab_current())
        self.click(self.app.date_picker.entry)
        self.assertTrue(self.app.date_picker.popup.winfo_viewable())
        self.type_key("Escape")
        self.assertIsNone(self.app.grab_current())

    def test_sidebar_double_click_does_not_open_editor_and_rows_match_timeline_colors(self):
        event = self.cell_event()
        tree = self.app.tags_tree
        tree.see("linux")
        self.app.update()
        x, y, width, height = tree.bbox("linux")
        self.click(tree, x + 130, y + height // 2)
        self.click(tree, x + 130, y + height // 2)
        self.assertIsNone(self.app.grab_current())
        self.assertEqual(self.app.add_event_button.master, self.app.events_heading.master)
        self.app.select_event(event.id)
        self.app.update()
        color = tag_color(self.store, event.tag_id, selected=True)
        row_tag = self.app.events_tree.item(event.id, "tags")[0]
        self.assertEqual(str(self.app.events_tree.tag_configure(row_tag, "background")), color)
        body = self.app.timeline.canvas.find_withtag(f"event:{event.id}")[0]
        self.assertEqual(self.app.timeline.canvas.itemcget(body, "fill"), color)
        self.assertEqual(self.app.tk.call("ttk::style", "map", "Treeview", "-background"), "")

    def test_inline_title_blur_commits_before_resizing_the_event(self):
        event = self.cell_event()
        editor = self.double_click_cell(event.id, "title")
        self.fill(editor.entry, "新名称")
        self.app.timeline.zoom = 4
        self.app.timeline.draw()
        self.app.timeline.canvas.xview_moveto(0.25)
        pointer = self.begin_resize(event.id, "end", event.end + timedelta(minutes=30))
        self.finish_resize(pointer)
        self.assertIsNone(self.app.cell_editor)
        self.assertEqual(self.store.events[event.id].title, "新名称")
        self.assertEqual(self.store.events[event.id].end, event.end + timedelta(minutes=30))

    def test_inline_title_commit_preserves_requested_day_navigation(self):
        event = self.cell_event()
        editor = self.double_click_cell(event.id, "title")
        target = self.app.day + timedelta(days=1)
        self.fill(editor.entry, "")
        self.app.date_picker.value.set(target.isoformat())
        with patch("tkinter.messagebox.showerror") as error:
            self.app.set_day()
            error.assert_called_once()
        self.assertEqual(self.app.day, event.start.date())
        self.assertEqual(self.app.date_picker.get(), self.app.day.isoformat())
        self.assertIs(self.app.cell_editor, editor)
        self.fill(editor.entry, "切换日期前保存")
        self.app.date_picker.value.set(target.isoformat())
        self.app.set_day()
        self.app.update()
        self.assertEqual(self.app.day, target)
        self.assertEqual(self.app.date_picker.get(), target.isoformat())
        self.assertEqual(self.store.events[event.id].title, "切换日期前保存")
        self.assertIsNone(self.app.cell_editor)
        self.assertFalse(self.app.events_tree.exists(event.id))

    def finish_resize(self, pointer):
        canvas, x, y = pointer
        canvas.event_generate("<ButtonRelease-1>", x=x, y=y)
        self.app.update()

    def begin_move(self, event_id, minutes, share=0.3):
        self.app.select_event(event_id)
        self.app.update()
        canvas = self.app.timeline.canvas
        left, top, right, bottom = canvas.bbox(canvas.find_withtag(f"event:{event_id}")[0])
        x, y = round((left + right) / 2 - canvas.canvasx(0)), round(top + (bottom - top) * share - canvas.canvasy(0))
        canvas.event_generate("<ButtonPress-1>", x=x, y=y)
        self.app.update()
        self.assertIsNotNone(self.app.timeline._drag)
        ticks = canvas.find_withtag("time-tick")
        span = canvas.coords(ticks[-1])[0] - canvas.coords(ticks[0])[0]
        x = round(x + span * minutes / 1440)
        canvas.event_generate("<B1-Motion>", x=x, y=y)
        self.app.update()
        return canvas, x, y

    def test_body_drag_moves_both_times_preserves_duration_and_updates_table_after_release(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9, second=32)
        event = Event("moved", "平移学习", "linux", start, start + timedelta(hours=1), "保留备注")
        self.store.save_event(event)
        self.app.refresh()
        self.app.timeline.zoom = 4
        self.app.timeline.draw()
        self.app.timeline.canvas.xview_moveto(0.25)
        original = self.store.events_path.read_bytes()
        pointer = self.begin_move(event.id, 90)
        self.assertEqual(self.store.events[event.id], event)
        self.assertEqual(self.store.events_path.read_bytes(), original)
        self.assertEqual(self.app.timeline._drag["preview"].start, start + timedelta(minutes=90))
        self.finish_resize(pointer)
        moved = Store(self.store.directory).events[event.id]
        self.assertEqual(moved.start, start + timedelta(minutes=90))
        self.assertEqual(moved.end, event.end + timedelta(minutes=90))
        self.assertEqual(moved.end - moved.start, event.end - event.start)
        self.assertEqual((moved.title, moved.tag_id, moved.notes), (event.title, event.tag_id, event.notes))
        self.assertEqual(self.app.events_tree.item(event.id, "values")[1:3], ("10:30", "11:30"))
        self.assertEqual(self.app.events_tree.item(event.id, "values")[-1], "1 小时 00 分")
        self.assertEqual(self.app.timeline.selected, {event.id})
        self.assertIsNone(self.app.grab_current())

    def test_body_drag_can_cancel_and_failed_writes_restore_the_original(self):
        event = self.cell_event()
        original = self.store.events_path.read_bytes()
        pointer = self.begin_move(event.id, 60)
        self.type_key("Escape")
        self.finish_resize(pointer)
        self.assertEqual(self.store.events_path.read_bytes(), original)
        pointer = self.begin_move(event.id, -30, share=0.7)
        with patch.object(self.store, "_write_events", side_effect=OSError("无法保存")), patch("tkinter.messagebox.showerror") as error:
            self.finish_resize(pointer)
            error.assert_called_once()
        self.assertEqual(self.store.events[event.id], event)
        self.assertEqual(self.store.events_path.read_bytes(), original)
        self.assertEqual(self.app.events_tree.item(event.id, "values")[1:3], ("09:00", "10:00"))
        self.assertIsNone(self.app.grab_current())

    def test_timeline_double_click_still_opens_editor_without_an_active_drag(self):
        event = self.cell_event()
        self.click_timeline_event(event.id)
        self.click_timeline_event(event.id)
        dialog = self.app.grab_current()
        self.assertIsInstance(dialog, EventDialog)
        self.assertIsNone(self.app.timeline._drag)
        self.assertEqual(dialog.notes.get("1.0", "end-1c"), event.notes)
        self.click(dialog.notes)
        self.type_key("x")
        self.assertIn("x", dialog.notes.get("1.0", "end-1c"))
        dialog.destroy()
        self.assertIsNone(self.app.grab_current())
        self.assertEqual(self.store.events[event.id], event)

    def test_body_drag_keeps_events_within_day_edges_and_moves_cross_day_endpoints_together(self):
        event = self.cell_event()
        origin = datetime.combine(self.app.day, datetime.min.time())
        self.finish_resize(self.begin_move(event.id, -1000))
        self.assertEqual(self.store.events[event.id].start, origin)
        self.assertEqual(self.store.events[event.id].end, origin + timedelta(hours=1))
        self.finish_resize(self.begin_move(event.id, 2000, share=0.7))
        self.assertEqual(self.store.events[event.id].start, origin + timedelta(hours=23))
        self.assertEqual(self.store.events[event.id].end, origin + timedelta(days=1))
        night = Event("night-move", "夜间记录", "life", origin - timedelta(hours=1), origin + timedelta(minutes=30))
        self.store.save_event(night)
        self.app.refresh()
        self.finish_resize(self.begin_move(night.id, 120))
        self.assertEqual(self.store.events[night.id].start, night.start + timedelta(hours=2))
        self.assertEqual(self.store.events[night.id].end, night.end + timedelta(hours=2))
        self.assertEqual(self.app.events_tree.item(night.id, "values")[-1], "1 小时 30 分")
        self.assertIsNone(self.app.grab_current())

    def test_resize_previews_without_writing_then_updates_scrolled_timeline_and_table(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9)
        event = Event("resized", "学习", "linux", start, start + timedelta(hours=1))
        self.store.save_event(event)
        self.app.refresh()
        self.app.timeline.zoom = 4
        self.app.timeline.draw()
        self.app.timeline.canvas.xview_moveto(0.25)
        original = self.store.events_path.read_bytes()
        end = start + timedelta(hours=1, minutes=30)
        pointer = self.begin_resize(event.id, "end", end)
        self.assertEqual(self.store.events[event.id], event)
        self.assertEqual(self.store.events_path.read_bytes(), original)
        self.finish_resize(pointer)
        self.assertEqual(Store(self.store.directory).events[event.id].end, end)
        self.assertEqual(self.app.events_tree.item(event.id, "values")[-1], "1 小时 30 分")
        pointer = self.begin_resize(event.id, "start", start + timedelta(minutes=15))
        self.finish_resize(pointer)
        self.assertEqual(self.store.events[event.id].start, start + timedelta(minutes=15))
        self.assertEqual(self.app.events_tree.item(event.id, "values")[-1], "1 小时 15 分")
        self.assertIsNone(self.app.grab_current())

    def test_escape_cancels_a_resize_without_changing_storage(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9)
        event = Event("cancelled", "学习", "linux", start, start + timedelta(hours=1))
        self.store.save_event(event)
        self.app.refresh()
        original = self.store.events_path.read_bytes()
        pointer = self.begin_resize(event.id, "end", start + timedelta(hours=2))
        self.type_key("Escape")
        self.finish_resize(pointer)
        self.assertEqual(self.store.events[event.id], event)
        self.assertEqual(self.store.events_path.read_bytes(), original)
        self.assertIsNone(self.app.grab_current())

    def test_failed_resize_restores_the_event_and_releases_mouse_capture(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9)
        event = Event("failed", "学习", "linux", start, start + timedelta(hours=1))
        self.store.save_event(event)
        self.app.refresh()
        original = self.store.events_path.read_bytes()
        pointer = self.begin_resize(event.id, "end", start + timedelta(hours=2))
        with patch.object(self.store, "_write_events", side_effect=OSError("无法保存")), patch("tkinter.messagebox.showerror") as error:
            self.finish_resize(pointer)
            error.assert_called_once()
        self.assertEqual(self.store.events[event.id], event)
        self.assertEqual(self.store.events_path.read_bytes(), original)
        self.assertEqual(self.app.events_tree.item(event.id, "values")[-1], "1 小时 00 分")
        self.assertIsNone(self.app.grab_current())

    def test_resize_preserves_a_hidden_cross_day_boundary_and_prevents_reversed_times(self):
        origin = datetime.combine(self.app.day, datetime.min.time())
        event = Event("night", "夜间学习", "linux", origin - timedelta(hours=1), origin + timedelta(minutes=30))
        self.store.save_event(event)
        self.app.refresh()
        self.app.update()
        self.assertFalse(self.app.timeline.canvas.find_withtag(f"resize:start:{event.id}"))
        self.app.timeline.zoom = 4
        self.app.timeline.draw()
        pointer = self.begin_resize(event.id, "end", origin + timedelta(hours=1))
        self.finish_resize(pointer)
        self.assertEqual(self.store.events[event.id].start, event.start)
        self.assertEqual(self.store.events[event.id].end, origin + timedelta(hours=1))
        self.app.timeline.zoom = 1
        start = origin + timedelta(hours=9)
        second = Event("short", "学习", "linux", start, start + timedelta(hours=1))
        self.store.save_event(second)
        self.app.refresh()
        pointer = self.begin_resize(second.id, "start", start + timedelta(hours=2))
        self.finish_resize(pointer)
        self.assertEqual(self.store.events[second.id].end - self.store.events[second.id].start, timedelta(minutes=1))

    def test_short_event_resize_handles_work_at_datetime_limits(self):
        for key, start, end, edge, target in (
            ("minimum", datetime.min, datetime.min + timedelta(seconds=30), "start", datetime.min + timedelta(minutes=2)),
            ("maximum", datetime.max - timedelta(seconds=30), datetime.max, "end", datetime.max - timedelta(minutes=2)),
        ):
            with self.subTest(edge=edge):
                self.app.day = start.date()
                event = Event(key, "边界记录", "linux", start, end)
                self.store.save_event(event)
                self.app.refresh()
                pointer = self.begin_resize(key, edge, target)
                self.finish_resize(pointer)
                self.assertEqual(self.store.events[key], event)
                self.assertIsNone(self.app.grab_current())

    def test_ctrl_wheel_zooms_between_full_day_and_four_times(self):
        timeline = self.app.timeline
        canvas = timeline.canvas
        self.assertEqual(timeline.zoom, 1)
        # The first and last time ticks mark midnight at each end of the day.
        grid = canvas.find_withtag("time-tick")
        original_span = canvas.coords(grid[-1])[0] - canvas.coords(grid[0])[0]
        self.wheel(-120, state=0x4)
        self.assertEqual(timeline.zoom, 1)
        for _ in range(16):
            self.wheel(120, state=0x4)
        self.assertEqual(timeline.zoom, 4)
        grid = canvas.find_withtag("time-tick")
        enlarged_span = canvas.coords(grid[-1])[0] - canvas.coords(grid[0])[0]
        self.assertAlmostEqual(enlarged_span, original_span * 4)
        for _ in range(16):
            self.wheel(-120, state=0x4)
        self.assertEqual(timeline.zoom, 1)
        self.assertAlmostEqual(canvas.xview()[0], 0, places=3)

    def test_zoom_adds_minute_ticks_and_keeps_labels_readable(self):
        timeline = self.app.timeline
        canvas = timeline.canvas
        for geometry in ("1100x740", "1360x900"):
            with self.subTest(geometry=geometry):
                self.app.geometry(geometry)
                timeline.zoom = 1
                timeline.draw()
                self.app.update()
                original_labels = len(canvas.find_withtag("time-label"))
                original_ticks = len(canvas.find_withtag("time-tick"))
                previous_count = original_labels
                for _ in range(12):
                    self.wheel(120, state=0x4)
                    labels = canvas.find_withtag("time-label")
                    self.assertGreaterEqual(len(labels), previous_count)
                    previous_count = len(labels)
                    for left, right in zip(labels, labels[1:]):
                        self.assertLess(canvas.bbox(left)[2], canvas.bbox(right)[0])
                texts = [canvas.itemcget(item, "text") for item in labels]
                self.assertEqual((texts[0], texts[-1]), ("00:00", "24:00"))
                self.assertTrue(any(not text.endswith(":00") for text in texts))
                self.assertGreater(len(labels), original_labels)
                self.assertGreater(len(canvas.find_withtag("time-tick")), original_ticks)

    def test_ctrl_wheel_keeps_pointer_time_and_event_selection(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=12)
        event = Event("zoomed", "午间学习", "linux", start, start + timedelta(hours=1))
        self.store.save_event(event)
        self.app.refresh()
        self.app.update()
        timeline = self.app.timeline
        canvas = timeline.canvas
        rectangle = canvas.find_withtag(f"event:{event.id}")[0]
        left, top, right, bottom = canvas.coords(rectangle)
        pointer_x = int((left + right) / 2)
        self.click(canvas, pointer_x, int((top + bottom) / 2))
        self.assertEqual(self.app.events_tree.selection(), (event.id,))
        fraction = (canvas.canvasx(pointer_x) - left) / (right - left)
        for _ in range(6):
            self.wheel(120, state=0x4, x=pointer_x)
            rectangle = canvas.find_withtag(f"event:{event.id}")[0]
            left, top, right, bottom = canvas.coords(rectangle)
            self.assertAlmostEqual(canvas.canvasx(pointer_x), left + fraction * (right - left), delta=2)
            fraction = (canvas.canvasx(pointer_x) - left) / (right - left)
        self.assertEqual(self.app.events_tree.selection(), (event.id,))
        self.assertEqual(timeline.selected, {event.id})
        # Hit testing still selects the same record after zooming and scrolling.
        self.app.events_tree.selection_remove(event.id)
        self.app.update()
        # Use a different point in the record so Tk does not treat this as a double-click.
        self.click(canvas, pointer_x + 12, int((top + bottom) / 2))
        self.assertEqual(self.app.events_tree.selection(), (event.id,))

    def test_normal_and_shift_wheel_scroll_without_changing_zoom(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9)
        for index in range(12):
            self.store.save_event(Event(str(index), "重叠事件", "linux", start, start + timedelta(hours=1)))
        self.app.refresh()
        self.app.update()
        self.wheel(120, state=0x4)
        timeline = self.app.timeline
        canvas = timeline.canvas
        zoom, horizontal, vertical = timeline.zoom, canvas.xview(), canvas.yview()
        self.wheel(-120)
        self.assertGreater(canvas.xview()[0], horizontal[0])
        self.assertEqual(canvas.yview(), vertical)
        horizontal = canvas.xview()
        self.wheel(-120, state=0x1)
        self.assertEqual(canvas.yview(), vertical)
        self.assertEqual(canvas.xview(), horizontal)
        self.assertEqual(timeline.zoom, zoom)

    def test_new_and_existing_event_fields_accept_mouse_focus_and_typing(self):
        start = datetime(2026, 10, 7, 9)
        existing = Event("old", "原名称", "linux", start, start + timedelta(hours=1))
        self.store.save_event(existing)
        for event in (None, existing):
            with self.subTest(editing=event is not None):
                editor = EventDialog(self.app, self.store, self.app.refresh, start.date(), event)
                self.click(editor.title_entry)
                self.assertEqual(self.app.focus_get(), editor.title_entry)
                original = editor.title_entry.get()
                self.type_key("x")
                self.assertNotEqual(editor.title_entry.get(), original)
                self.click(editor.notes)
                self.assertEqual(self.app.focus_get(), editor.notes)
                self.type_key("n")
                self.assertEqual(editor.notes.get("1.0", "end-1c"), "n")
                editor.destroy()

    def test_timeline_fills_height_and_expands_after_an_overlap_ends(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=13)
        self.store.save_event(Event("cooking", "做饭", "life", start, start + timedelta(hours=2)))
        self.store.save_event(Event("podcast", "听博客", "explore", start, start + timedelta(hours=1)))
        self.app.refresh()
        self.app.update()
        canvas = self.app.timeline.canvas
        for geometry in ("1100x740", "1360x900"):
            self.app.geometry(geometry)
            self.app.update()
            ticks = canvas.find_withtag("time-tick")
            left, right = canvas.coords(ticks[0])[0], canvas.coords(ticks[-1])[0]
            height = canvas.winfo_height() - 24 - 50
            for hour, share, expected in ((13.5, 0.25, "cooking"), (13.5, 0.75, "podcast"),
                                          (14.5, 0.25, "cooking"), (14.5, 0.75, "cooking")):
                x = int(left + (right - left) * hour / 24 - canvas.canvasx(0))
                self.click(canvas, x, int(50 + height * share))
                self.assertEqual(self.app.events_tree.selection(), (expected,))

    def test_single_mouse_click_selects_a_tag_and_returns_to_notes(self):
        editor = EventDialog(self.app, self.store, self.app.refresh, date(2026, 10, 7))
        self.click(editor.tag.entry)
        popup = editor.tag.popup
        tree = popup.tree
        tree.see("tag:linux")
        self.app.update()
        x, y, width, height = tree.bbox("tag:linux")
        self.click(tree, x + 90, y + height // 2)
        self.assertFalse(popup.winfo_exists())
        self.assertEqual(editor.tag.tag_id(), "linux")
        self.assertEqual(self.app.grab_current(), editor)
        self.click(editor.notes)
        self.assertEqual(self.app.focus_get(), editor.notes)
        self.type_key("a")
        self.assertEqual(editor.notes.get("1.0", "end-1c"), "a")
        editor.destroy()

    def test_clicking_main_date_field_opens_calendar_and_changes_day(self):
        self.app.date_picker.value.set("2026-10-07")
        self.click(self.app.date_picker.entry)
        popup = self.app.date_picker.popup
        self.assertTrue(popup.winfo_viewable())
        self.click(popup.day_buttons[8])
        self.assertEqual(self.app.day, date(2026, 10, 8))
        self.assertFalse(popup.winfo_exists())
        self.assertIsNone(self.app.grab_current())
        self.assertIsNotNone(self.app.focus_get())

    def test_mouse_selects_hours_minutes_and_confirms_the_time(self):
        editor = EventDialog(self.app, self.store, self.app.refresh, date(2026, 10, 7))
        self.click(editor.start_time.entry)
        popup = editor.start_time.popup
        for items, index in ((popup.hours, 14), (popup.minutes, 35)):
            items.see(index)
            self.app.update()
            x, y, width, height = items.bbox(index)
            self.click(items, x + 8, y + height // 2)
        footer = popup.body.grid_slaves(row=1)[0]
        self.click(footer.winfo_children()[-1])
        self.assertEqual(editor.start_time.get(), "14:35")
        self.assertEqual(self.app.grab_current(), editor)
        self.assertFalse(popup.winfo_exists())
        editor.destroy()

    def test_dismissing_a_picker_restores_typing_and_can_reopen(self):
        editor = EventDialog(self.app, self.store, self.app.refresh, self.app.day)
        self.click(editor.start_time.entry)
        popup = editor.start_time.popup
        self.type_key("Escape")
        self.assertFalse(popup.winfo_exists())
        self.assertEqual(self.app.grab_current(), editor)
        self.click(editor.notes)
        self.type_key("b")
        self.assertEqual(editor.notes.get("1.0", "end-1c"), "b")
        self.click(editor.start_time.entry)
        self.assertTrue(editor.start_time.popup.winfo_viewable())
        editor.destroy()
        self.assertIsNone(self.app.grab_current())

    def test_closing_editor_with_open_picker_unlocks_event_selection(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9)
        event = Event("selectable", "事件", "linux", start, start + timedelta(hours=1))
        self.store.save_event(event)
        self.app.refresh()
        editor = EventDialog(self.app, self.store, self.app.refresh, self.app.day, event)
        self.click(editor.tag.button)
        editor.destroy()
        self.app.update()
        self.assertIsNone(self.app.grab_current())
        tree = self.app.events_tree
        x, y, width, height = tree.bbox(event.id)
        self.click(tree, x + 100, y + height // 2)
        self.assertEqual(tree.selection(), (event.id,))

    def menu_for(self, tag_id=None):
        tree = self.app.tags_tree
        if tag_id:
            tree.see(tag_id)
            self.app.update()
            y = tree.bbox(tag_id)[1] + 18
        else:
            y = tree.winfo_height() - 30
        # Native Windows menu posting can enter a modal OS loop; invoke the
        # real menu actions after verifying the mouse binding requests posting.
        with patch("tkinter.Menu.tk_popup") as post:
            tree.event_generate("<Button-3>", x=100, y=y)
            self.app.update()
            post.assert_called_once()
        return self.app.tag_menu

    def event_menu_for(self, event_id):
        tree = self.app.events_tree
        tree.see(event_id)
        self.app.update()
        x, y, width, height = tree.bbox(event_id)
        with patch("tkinter.Menu.tk_popup") as post:
            tree.event_generate("<Button-3>", x=x + 100, y=y + height // 2)
            self.app.update()
            post.assert_called_once()
        return self.app.event_menu

    def test_event_context_menu_keeps_multiselection_and_confirms_deletion(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9)
        for key in ("a", "b", "c"):
            self.store.save_event(Event(key, key, "linux", start, start + timedelta(hours=1)))
        self.app.refresh()
        self.app.events_tree.selection_set(("a", "b"))
        menu = self.event_menu_for("b")
        self.assertEqual(set(self.app.events_tree.selection()), {"a", "b"})
        self.assertEqual(menu.entrycget(0, "label"), "删除")
        with patch("tkinter.messagebox.askyesno", return_value=False):
            menu.invoke(0)
        self.assertEqual(set(self.store.events), {"a", "b", "c"})
        with patch("tkinter.messagebox.askyesno", return_value=True):
            menu.invoke(0)
        self.assertEqual(set(Store(self.store.directory).events), {"c"})
        self.assertIsNone(self.app.grab_current())

    def test_event_context_menu_targets_clicked_row_and_ignores_empty_space(self):
        start = datetime.combine(self.app.day, datetime.min.time()).replace(hour=9)
        for key in ("a", "b"):
            self.store.save_event(Event(key, key, "linux", start, start + timedelta(hours=1)))
        self.app.refresh()
        tree = self.app.events_tree
        tree.selection_set("a")
        menu = self.event_menu_for("b")
        self.assertEqual(tree.selection(), ("b",))
        with patch("tkinter.messagebox.askyesno", return_value=True):
            menu.invoke(0)
        self.assertEqual(set(self.store.events), {"a"})
        self.app.update()
        with patch("tkinter.Menu.tk_popup") as post:
            tree.event_generate("<Button-3>", x=100, y=tree.winfo_height() - 10)
            self.app.update()
            post.assert_not_called()
        self.assertEqual(set(self.store.events), {"a"})

    def drag(self, source, target):
        tree = self.app.tags_tree
        tree.see(source)
        if target:
            tree.see(target)
        self.app.update()
        start_y = tree.bbox(source)[1] + 18
        end_y = tree.bbox(target)[1] + 18 if target else tree.winfo_height() - 30
        tree.event_generate("<ButtonPress-1>", x=130, y=start_y)
        tree.event_generate("<B1-Motion>", x=130, y=end_y)
        tree.event_generate("<ButtonRelease-1>", x=130, y=end_y)
        self.app.update()

    def test_add_edit_reassign_and_delete_event(self):
        editor = EventDialog(self.app, self.store, self.app.refresh, date(2026, 10, 7))
        self.fill(editor.title_entry, "驱动开发")
        self.choose_tag(editor.tag, "linux")
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
        self.assertEqual(self.app.events_tree.item(event.id, "values")[-1], "1 小时 30 分")
        self.assertEqual((event.start.second, event.end.second), (0, 0))
        editor = EventDialog(self.app, self.store, self.app.refresh, self.app.day, event)
        self.fill(editor.title_entry, "Linux 驱动开发")
        editor.save()
        self.assertEqual(self.store.events[event.id].title, "Linux 驱动开发")
        editor = EventDialog(self.app, self.store, self.app.refresh, self.app.day, self.store.events[event.id])
        self.choose_tag(editor.tag, "explore")
        editor.save()
        self.app.select_event(event.id)
        self.app.update()
        self.assertEqual(self.store.events[event.id].tag_id, "explore")
        with patch("tkinter.messagebox.askyesno", return_value=True):
            self.app.delete_events()
        self.assertEqual(Store(self.store.directory).events, {})

    def test_sidebar_selection_keeps_all_events_visible(self):
        start = datetime(2026, 10, 7, 23, 30)
        self.store.save_event(Event("late", "夜间学习", "linux", start, start + timedelta(hours=1)))
        self.store.save_event(Event("other", "探索", "explore", start, start + timedelta(hours=1)))
        self.app.day = date(2026, 10, 8)
        self.app.refresh()
        self.app.tags_tree.selection_set("work")
        self.app.update()
        self.assertEqual(set(self.app.events_tree.get_children()), {"late", "other"})
        self.assertTrue(self.app.timeline.canvas.find_withtag("event:other"))
        self.assertEqual(self.app.events_tree.item("late", "values")[-1], "30 分钟")
        self.app.timeline.on_select("late")
        self.app.update()
        self.assertEqual(self.app.events_tree.selection(), ("late",))

    def test_context_menu_add_rename_and_delete(self):
        self.menu_for("work").invoke(0)
        dialog = self.app.grab_current()
        self.fill(dialog.name, "新标签")
        dialog.save()
        self.app.update()
        tag_id = self.app.selected_tag()
        self.assertEqual(self.store.tags[tag_id].parent_id, "work")
        self.menu_for(tag_id).invoke(1)
        dialog = self.app.grab_current()
        self.fill(dialog.name, "改名")
        dialog.save()
        self.app.update()
        self.assertEqual(Store(self.store.directory).tags[tag_id].name, "改名")
        with patch("tkinter.messagebox.askyesno", return_value=True):
            self.menu_for(tag_id).invoke(2)
        self.assertNotIn(tag_id, Store(self.store.directory).tags)
        self.menu_for().invoke(0)
        dialog = self.app.grab_current()
        self.fill(dialog.name, "一级标签")
        dialog.save()
        self.app.update()
        self.assertIsNone(self.store.tags[self.app.selected_tag()].parent_id)

    def test_drag_reparents_branch_and_can_move_back_to_root(self):
        start = datetime(2026, 10, 7, 9)
        self.store.save_event(Event("event", "学习", "linux", start, start + timedelta(hours=1)))
        original_events = self.store.events_path.read_bytes()
        self.drag("embedded", "side")
        self.assertEqual(self.store.tags["embedded"].parent_id, "side")
        self.assertEqual(self.app.tags_tree.parent("linux"), "embedded")
        self.assertEqual(Store(self.store.directory).events["event"].tag_id, "linux")
        self.assertEqual(self.store.events_path.read_bytes(), original_events)
        self.drag("embedded", None)
        self.assertIsNone(Store(self.store.directory).tags["embedded"].parent_id)

    def test_drag_to_descendant_is_rejected(self):
        original = self.store.tags_path.read_bytes()
        self.drag("work", "linux")
        self.assertEqual(self.store.tags_path.read_bytes(), original)
        self.assertIsNone(self.store.tags["work"].parent_id)

    def test_drag_release_outside_the_tree_cancels_the_move(self):
        original = self.store.tags_path.read_bytes()
        tree = self.app.tags_tree
        source_y = tree.bbox("embedded")[1] + 18
        target_y = tree.bbox("side")[1] + 18
        tree.event_generate("<ButtonPress-1>", x=130, y=source_y)
        tree.event_generate("<B1-Motion>", x=130, y=target_y)
        tree.event_generate("<ButtonRelease-1>", x=tree.winfo_width() + 20, y=target_y)
        self.app.update()
        self.assertEqual(self.store.tags_path.read_bytes(), original)

    def test_tree_picker_has_hierarchy_and_restores_modal_grab(self):
        editor = EventDialog(self.app, self.store, self.app.refresh, self.app.day)
        editor.tag.open_popup()
        self.app.update()
        tree = editor.tag.popup.tree
        self.assertEqual(tree.parent("tag:linux"), "tag:embedded")
        self.assertEqual(tree.item("tag:linux", "text"), "Linux")
        x, y, width, height = tree.bbox("tag:embedded")
        self.click(tree, x + 90, y + height // 2)
        self.assertEqual(editor.tag.get(), "嵌入式")
        self.assertEqual(self.app.grab_current(), editor)
        editor.destroy()

    def test_calendar_and_time_can_be_selected_with_mouse_controls(self):
        editor = EventDialog(self.app, self.store, self.app.refresh, date(2026, 10, 7))
        self.click(editor.start_date.entry)
        self.app.update()
        editor.start_date.popup.day_buttons[8].invoke()
        self.assertEqual(editor.start_date.get(), "2026-10-08")
        self.click(editor.start_time.entry)
        self.app.update()
        popup = editor.start_time.popup
        popup.hours.selection_clear(0, "end")
        popup.hours.selection_set(14)
        popup.minutes.selection_clear(0, "end")
        popup.minutes.selection_set(35)
        editor.start_time.choose()
        self.assertEqual(editor.start_time.get(), "14:35")
        self.assertEqual(self.app.grab_current(), editor)
        editor.destroy()
        self.app.date_picker.value.set("2026-10-07")
        self.click(self.app.date_picker.entry)
        self.app.update()
        self.app.date_picker.popup.day_buttons[8].invoke()
        self.assertEqual(self.app.day, date(2026, 10, 8))

    def test_legacy_seconds_are_preserved_when_only_title_changes(self):
        start = datetime(2026, 10, 7, 9, 0, 32)
        event = Event("old", "旧记录", "linux", start, start + timedelta(hours=1))
        self.store.save_event(event)
        editor = EventDialog(self.app, self.store, self.app.refresh, start.date(), event)
        self.assertEqual(editor.start_time.get(), "09:00")
        self.fill(editor.title_entry, "更新名称")
        editor.save()
        restored = Store(self.store.directory).events["old"]
        self.assertEqual((restored.start, restored.end), (event.start, event.end))

    def test_layout_is_white_and_both_record_panels_have_more_height(self):
        self.app.geometry("1100x740")
        self.app.update()
        self.assertEqual(self.app.title(), "Daymark")
        self.assertEqual(self.app.cget("bg"), "white")
        self.assertGreaterEqual(self.app.timeline.canvas.winfo_height(), 200)
        self.assertGreaterEqual(self.app.events_tree.winfo_height(), 200)

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
