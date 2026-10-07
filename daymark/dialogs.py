"""Focused modal editors for labels, events, and bulk reassignment."""

import tkinter as tk
from datetime import datetime, timedelta
from tkinter import messagebox, ttk
from uuid import uuid4

from .model import Event
from .widgets import DatePicker, TagPicker, TimePicker


class Dialog(tk.Toplevel):
    def __init__(self, parent, title):
        super().__init__(parent)
        self.title(title)
        self.configure(bg="white")
        self.transient(parent)
        self.resizable(False, False)
        self.body = ttk.Frame(self, padding=24)
        self.body.pack(fill="both", expand=True)
        self.body.columnconfigure(1, weight=1)
        self.bind("<Escape>", lambda _: self.destroy())
        self.protocol("WM_DELETE_WINDOW", self.destroy)

    def show(self, focus):
        self.update_idletasks()
        x = self.master.winfo_rootx() + (self.master.winfo_width() - self.winfo_reqwidth()) // 2
        y = self.master.winfo_rooty() + (self.master.winfo_height() - self.winfo_reqheight()) // 2
        self.geometry(f"+{max(0, x)}+{max(0, y)}")
        self.grab_set()
        focus.focus_set()

    def buttons(self, row, callback, label="保存"):
        bar = ttk.Frame(self.body)
        bar.grid(row=row, column=0, columnspan=2, sticky="e", pady=(20, 0))
        ttk.Button(bar, text="取消", command=self.destroy).pack(side="left", padx=(0, 8))
        ttk.Button(bar, text=label, command=callback, style="Accent.TButton").pack(side="left")

    def try_save(self, callback):
        try:
            callback()
        except (ValueError, OSError) as error:
            messagebox.showerror("未能保存", str(error), parent=self)
            return False
        self.destroy()
        return True


class TagDialog(Dialog):
    def __init__(self, parent, store, on_saved, tag_id=None, parent_id=None):
        super().__init__(parent, "修改 / 移动标签" if tag_id else "新增标签")
        self.store, self.on_saved, self.tag_id = store, on_saved, tag_id
        tag = store.tags.get(tag_id)
        ttk.Label(self.body, text="标签名称").grid(row=0, column=0, sticky="w", padx=(0, 14))
        self.name = ttk.Entry(self.body, width=44)
        self.name.grid(row=0, column=1, sticky="ew", pady=(0, 16))
        if tag:
            self.name.insert(0, tag.name)
        ttk.Label(self.body, text="父标签").grid(row=1, column=0, sticky="w", padx=(0, 14))
        self.parent_choice = TagPicker(self.body, store, tag.parent_id if tag else parent_id,
                                      excluded=store.descendants(tag_id) if tag else (),
                                      empty_label="（一级标签）", width=44)
        self.parent_choice.grid(row=1, column=1, sticky="ew")
        self.buttons(2, self.save)
        self.bind("<Return>", lambda _: self.save())
        self.show(self.name)

    def save(self):
        saved = []
        if self.try_save(lambda: saved.append(self.store.save_tag(self.name.get(), self.parent_choice.tag_id(), self.tag_id))):
            self.on_saved(saved[0].id)


class EventDialog(Dialog):
    def __init__(self, parent, store, on_saved, day, event=None, tag_id=None):
        super().__init__(parent, "编辑事件" if event else "补录事件")
        self.store, self.on_saved, self.event = store, on_saved, event
        now = datetime.now().replace(second=0, microsecond=0)
        end = event.end if event else (now if day == now.date() else datetime.combine(day, datetime.min.time()).replace(hour=10))
        start = event.start if event else end - timedelta(hours=1)
        ttk.Label(self.body, text="事件名称").grid(row=0, column=0, sticky="w", padx=(0, 16))
        self.title_entry = ttk.Entry(self.body, width=52)
        self.title_entry.grid(row=0, column=1, sticky="ew", pady=(0, 16))
        if event:
            self.title_entry.insert(0, event.title)
        ttk.Label(self.body, text="标签").grid(row=1, column=0, sticky="w")
        self.tag = TagPicker(self.body, store, event.tag_id if event else tag_id, width=46)
        self.tag.grid(row=1, column=1, sticky="ew", pady=(0, 16))
        self.start_date, self.start_time = self.time_fields(2, "开始", start)
        self.end_date, self.end_time = self.time_fields(3, "结束", end or now)
        ttk.Label(self.body, text="备注").grid(row=4, column=0, sticky="nw")
        self.notes = tk.Text(self.body, width=52, height=5, font=("Microsoft YaHei UI", 10), bg="white", fg="#111111",
                             relief="solid", borderwidth=1, padx=8, pady=8, wrap="word")
        self.notes.grid(row=4, column=1, sticky="ew")
        if event:
            self.notes.insert("1.0", event.notes)
        self.buttons(5, self.save)
        self.show(self.title_entry)

    def time_fields(self, row, label, value):
        ttk.Label(self.body, text=label).grid(row=row, column=0, sticky="w")
        bar = ttk.Frame(self.body)
        bar.grid(row=row, column=1, sticky="w", pady=(0, 16))
        day_entry = DatePicker(bar, value.date())
        day_entry.pack(side="left", padx=(0, 12))
        clock_entry = TimePicker(bar, value)
        clock_entry.pack(side="left")
        return day_entry, clock_entry

    @staticmethod
    def parse_time(day_entry, clock_entry):
        try:
            day, clock = day_entry.get().strip(), clock_entry.get().strip()
            return datetime.strptime(f"{day} {clock}", "%Y-%m-%d %H:%M")
        except (ValueError, TypeError):
            pass
        raise ValueError("日期或时间格式不正确，请使用 YYYY-MM-DD 和 HH:MM。")

    def save(self):
        def write():
            start = self.parse_time(self.start_date, self.start_time)
            end = self.parse_time(self.end_date, self.end_time)
            # Editing text or classification must not silently round legacy timestamps.
            if self.event:
                if start == self.event.start.replace(second=0, microsecond=0):
                    start = self.event.start
                if self.event.end and end == self.event.end.replace(second=0, microsecond=0):
                    end = self.event.end
            event = Event(self.event.id if self.event else uuid4().hex, self.title_entry.get().strip(),
                          self.tag.tag_id(), start,
                          end,
                          self.notes.get("1.0", "end-1c"))
            self.store.save_event(event)
        if self.try_save(write):
            self.on_saved()


class ReassignDialog(Dialog):
    def __init__(self, parent, store, event_ids, on_saved):
        super().__init__(parent, "更换事件标签")
        self.store, self.event_ids, self.on_saved = store, event_ids, on_saved
        ttk.Label(self.body, text=f"将 {len(event_ids)} 个事件转移到：").grid(row=0, column=0, sticky="w", pady=(0, 16))
        self.tag = TagPicker(self.body, store, store.events[event_ids[0]].tag_id, width=46)
        self.tag.grid(row=1, column=0, columnspan=2, sticky="ew")
        self.buttons(2, self.save, "更换标签")
        self.show(self.tag)

    def save(self):
        if self.try_save(lambda: self.store.reassign_events(self.event_ids, self.tag.tag_id())):
            self.on_saved()
