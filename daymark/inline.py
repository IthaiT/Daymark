"""Editors placed over individual event-table cells."""

from datetime import datetime, timedelta
from tkinter import messagebox, ttk

from .widgets import DateTimePicker, TagPicker


class CellEditor(ttk.Frame):
    def __init__(self, parent, store, event, column, on_save, on_cancel):
        super().__init__(parent)
        self.event_id, self.column = event.id, column
        self.on_save, self.on_cancel = on_save, on_cancel
        self._closed = self._saving = False
        self._focus_job = self._open_job = None
        if column == "tag":
            self.input = TagPicker(self, store, event.tag_id, on_change=self.commit)
            self.entry = self.input.entry
        elif column in ("start", "end"):
            value = getattr(event, column)
            if value is None:
                try:
                    value = event.start + timedelta(hours=1)
                except OverflowError:
                    value = datetime.max
            self.input = DateTimePicker(self, value, on_change=self.commit)
            self.entry = self.input.entry
        else:
            self.input = self.entry = ttk.Entry(self)
            self.entry.insert(0, event.title)
        self.input.pack(fill="both", expand=True)
        self.entry.bind("<Return>", lambda _: self._commit_key())
        self.entry.bind("<Escape>", lambda _: self._cancel_key())
        self.entry.bind("<FocusOut>", self._focus_out)

    def show(self, bounds):
        x, y, width, height = bounds
        self.place(x=x, y=y, width=width, height=height)
        self.entry.focus_force()
        self.entry.selection_range(0, "end")
        if self.column != "title":
            self._open_job = self.after_idle(self._open_picker)

    def _open_picker(self):
        self._open_job = None
        if not self._closed:
            self.input.open_popup()

    def _focus_out(self, _):
        if not self._closed and not self._saving and self._focus_job is None:
            self._focus_job = self.after_idle(self._check_focus)

    def _check_focus(self):
        self._focus_job = None
        if self._closed or self._saving:
            return
        focused = self.focus_get()
        if focused is not None and not str(focused).startswith(str(self) + "."):
            self.commit()

    def commit(self):
        if self._closed:
            return True
        if self._saving:
            return False
        self._saving = True
        saved = False
        try:
            if self.column == "tag":
                value = self.input.tag_id()
            elif self.column in ("start", "end"):
                value = self.input.get_datetime()
            else:
                value = self.entry.get().strip()
            saved = self.on_save(self, value)
        except ValueError as error:
            messagebox.showerror("输入未保存", str(error), parent=self.winfo_toplevel())
        finally:
            self._saving = False
        if not saved and not self._closed:
            self.entry.focus_force()
        return saved

    def _commit_key(self):
        self.commit()
        return "break"

    def _cancel_key(self):
        self.on_cancel()
        return "break"

    def destroy(self):
        if self._closed:
            return
        self._closed = True
        for job in (self._focus_job, self._open_job):
            if job is not None:
                self.after_cancel(job)
        grabbed = self.grab_current()
        if grabbed is not None and str(grabbed).startswith(str(self) + "."):
            grabbed.grab_release()
        super().destroy()
