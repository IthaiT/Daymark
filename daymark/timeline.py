"""Scrollable daily timeline; event geometry is based on actual timestamps."""

import hashlib
import tkinter as tk
from datetime import datetime, time
from tkinter import ttk

from .model import duration_text, timeline_lanes

PALETTE = ("#356f64", "#5c6eb1", "#b57c3a", "#9a6389", "#638653", "#467e9e", "#b26656")
DEFAULT_COLORS = {"work": PALETTE[0], "side": PALETTE[1], "explore": PALETTE[2], "life": PALETTE[4]}


def tag_color(store, tag_id):
    if tag_id is None:
        return "#78828a"
    while store.tags[tag_id].parent_id:
        tag_id = store.tags[tag_id].parent_id
    if tag_id in DEFAULT_COLORS:
        return DEFAULT_COLORS[tag_id]
    index = int(hashlib.sha256(tag_id.encode()).hexdigest()[:8], 16)
    return PALETTE[index % len(PALETTE)]


class Timeline(ttk.Frame):
    def __init__(self, parent, store, on_select, on_edit):
        super().__init__(parent, style="Card.TFrame")
        self.store, self.on_select, self.on_edit = store, on_select, on_edit
        self.canvas = tk.Canvas(self, height=132, bg="#ffffff", highlightthickness=0)
        self.canvas.grid(row=0, column=0, sticky="nsew")
        horizontal = ttk.Scrollbar(self, orient="horizontal", command=self.canvas.xview)
        horizontal.grid(row=1, column=0, sticky="ew")
        vertical = ttk.Scrollbar(self, orient="vertical", command=self.canvas.yview)
        vertical.grid(row=0, column=1, sticky="ns")
        self.canvas.configure(xscrollcommand=horizontal.set, yscrollcommand=vertical.set)
        self.columnconfigure(0, weight=1)
        self.rowconfigure(0, weight=1)
        self.canvas.bind("<Configure>", lambda _: self.draw())
        self.canvas.bind("<Button-1>", self._click)
        self.canvas.bind("<Double-1>", self._double_click)
        self.canvas.bind("<Motion>", self._hover)
        self.canvas.bind("<Leave>", lambda _: self._hide_tooltip())
        self.canvas.bind("<MouseWheel>", self._wheel)
        self.events, self.day, self.now = [], None, None
        self.zoom = 1
        self.selected = set()
        self.tooltip = None
        self.hovered_id = None

    def update_events(self, events, day, now, selected=()):
        self.events, self.day, self.now = events, day, now
        self.selected = set(selected)
        self.draw()

    def draw(self):
        if self.day is None:
            return
        self._hide_tooltip()
        canvas = self.canvas
        canvas.delete("all")
        width = max(650, canvas.winfo_width() - 48) * self.zoom
        lanes = timeline_lanes(self.events, self.day, self.now)
        bottom = max(128, 50 + len(lanes) * 44)
        canvas.configure(scrollregion=(0, 0, width + 48, bottom + 24))
        origin = datetime.combine(self.day, time.min)

        def x(moment):
            return 24 + (moment - origin).total_seconds() / 86400 * width

        for hour in range(25):
            xpos = 24 + hour / 24 * width
            canvas.create_line(xpos, 43, xpos, bottom, fill="#ecefea")
            if self.zoom > 1 or hour % 2 == 0:
                canvas.create_text(xpos, 24, text=f"{hour:02d}:00", fill="#7b8581", font=("Microsoft YaHei UI", 9))
        for lane_index, lane in enumerate(lanes):
            top = 50 + lane_index * 44
            for event, start, end in lane:
                left, right = x(start), x(end)
                # The narrowest records keep a visible hit target; duration stays exact in the tooltip.
                right = max(left + 3, right)
                tags = (f"event:{event.id}",)
                color = tag_color(self.store, event.tag_id)
                canvas.create_rectangle(
                    left, top, right, top + 30, fill=color,
                    outline="#162e28" if event.id in self.selected else color,
                    width=3 if event.id in self.selected else 1,
                    dash=(4, 2) if event.end is None else (), tags=tags,
                )
                available = right - left - 12
                if available >= 20:
                    limit = max(1, int(available / 13))
                    title = event.title if len(event.title) <= limit else event.title[:max(1, limit - 1)] + "…"
                    canvas.create_text(left + 7, top + 15, text=title, fill="white",
                                       anchor="w", font=("Microsoft YaHei UI", 10), tags=tags)
        if not lanes:
            canvas.create_text(width / 2 + 24, 96, text="这一天还没有记录。开始计时，或补录一段时间。",
                               fill="#8b948e", font=("Microsoft YaHei UI", 11))
        if self.day == self.now.date():
            current = x(self.now)
            canvas.create_line(current, 42, current, bottom, fill="#c46d49", width=2, dash=(3, 3))
            canvas.create_polygon(current - 4, 39, current + 4, 39, current, 45, fill="#c46d49")

    def _event_at(self, pointer):
        xpos, ypos = self.canvas.canvasx(pointer.x), self.canvas.canvasy(pointer.y)
        for item in reversed(self.canvas.find_overlapping(xpos - 2, ypos - 2, xpos + 2, ypos + 2)):
            for tag in self.canvas.gettags(item):
                if tag.startswith("event:"):
                    return self.store.events.get(tag[6:])
        return None

    def _click(self, pointer):
        if event := self._event_at(pointer):
            self.on_select(event.id)

    def _double_click(self, pointer):
        if event := self._event_at(pointer):
            self.on_edit(event.id)

    def _hover(self, pointer):
        event = self._event_at(pointer)
        self.canvas.configure(cursor="hand2" if event else "")
        if event is None:
            self._hide_tooltip()
            return
        if event.id == self.hovered_id:
            return
        self._hide_tooltip()
        self.hovered_id = event.id
        start, end = event.interval_on(self.day, self.now)
        description = (f"{event.title}\n{self.store.tag_path(event.tag_id)}\n"
                       f"{start:%H:%M:%S} — {end:%H:%M:%S} · {duration_text((end-start).total_seconds())}"
                       + (" · 计时中" if event.end is None else ""))
        self.tooltip = tk.Toplevel(self)
        self.tooltip.overrideredirect(True)
        self.tooltip.attributes("-topmost", True)
        ttk.Label(self.tooltip, text=description, style="Tooltip.TLabel", padding=12, wraplength=360).pack()
        self.tooltip.geometry(f"+{min(pointer.x_root + 16, self.winfo_screenwidth() - 390)}+{min(pointer.y_root + 18, self.winfo_screenheight() - 130)}")

    def _hide_tooltip(self):
        if self.tooltip is not None:
            self.tooltip.destroy()
        self.tooltip, self.hovered_id = None, None

    def _wheel(self, pointer):
        if pointer.state & 1:
            self.canvas.yview_scroll(-1 if pointer.delta > 0 else 1, "units")
        else:
            self.canvas.xview_scroll(-1 if pointer.delta > 0 else 1, "units")
