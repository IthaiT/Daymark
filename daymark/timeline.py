"""Scrollable daily timeline; event geometry is based on actual timestamps."""

import hashlib
import tkinter as tk
import tkinter.font as tkfont
from dataclasses import replace
from datetime import datetime, time, timedelta
from tkinter import ttk

from .model import duration_text, timeline_segments

PALETTE = ("#dbeafe", "#ede9fe", "#fef3c7", "#fee2e2", "#ffedd5", "#cffafe", "#fce7f3")
DEFAULT_COLORS = {"work": PALETTE[0], "side": PALETTE[1], "explore": PALETTE[2], "life": PALETTE[4]}


def tag_color(store, tag_id, selected=False):
    if tag_id is None:
        color = "#e5e7eb"
    else:
        while store.tags[tag_id].parent_id:
            tag_id = store.tags[tag_id].parent_id
        if tag_id in DEFAULT_COLORS:
            color = DEFAULT_COLORS[tag_id]
        else:
            index = int(hashlib.sha256(tag_id.encode()).hexdigest()[:8], 16)
            color = PALETTE[index % len(PALETTE)]
    if selected:
        color = "#" + "".join(f"{round(int(color[index:index + 2], 16) * 0.78 + 17 * 0.22):02x}"
                               for index in (1, 3, 5))
    return color


class Timeline(ttk.Frame):
    def __init__(self, parent, store, on_select, on_edit, on_resize):
        super().__init__(parent)
        self.store, self.on_select, self.on_edit = store, on_select, on_edit
        self.on_resize = on_resize
        self._resize = None
        self.canvas = tk.Canvas(self, height=280, bg="white", highlightthickness=1, highlightbackground="#e5e5e5")
        self.tick_font = tkfont.Font(self.canvas, family="Microsoft YaHei UI", size=9)
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
        self.canvas.bind("<B1-Motion>", self._resize_motion)
        self.canvas.bind("<ButtonRelease-1>", self._resize_release)
        self.canvas.bind("<Escape>", lambda _: self.cancel_resize())
        self.canvas.bind("<Double-1>", self._double_click)
        self.canvas.bind("<Motion>", self._hover)
        self.canvas.bind("<Leave>", lambda _: self._hide_tooltip())
        self.canvas.bind("<MouseWheel>", self._wheel)
        self.events, self.day = [], None
        self.zoom = 1
        self.selected = set()
        self.tooltip = None
        self.hovered_id = None

    def update_events(self, events, day, selected=()):
        self.events, self.day = events, day
        self.selected = set(selected)
        self.draw()

    def draw(self):
        if self.day is None:
            return
        self._hide_tooltip()
        canvas = self.canvas
        canvas.delete("all")
        width = max(650, canvas.winfo_width() - 48) * self.zoom
        events = self.events
        if self._resize is not None:
            preview = self._resize["preview"]
            events = [preview if event.id == preview.id else event for event in events]
        segments = timeline_segments(events, self.day)
        bottom = max(90, canvas.winfo_height() - 26)
        canvas.configure(scrollregion=(0, 0, width + 48, bottom + 24))
        origin = datetime.combine(self.day, time.min)

        def x(moment):
            return 24 + (moment - origin).total_seconds() / 86400 * width

        major, minor = self._tick_intervals(width)
        for minute in range(0, 1441, minor):
            xpos = 24 + minute / 1440 * width
            is_major = minute % major == 0
            canvas.create_line(xpos, 43, xpos, bottom if is_major else 49,
                               fill="#e5e5e5" if is_major else "#bbbbbb", tags=("time-tick",))
            if is_major:
                canvas.create_text(xpos, 24, text=f"{minute // 60:02d}:{minute % 60:02d}",
                                   fill="#111111", font=self.tick_font, tags=("time-label",))
        pieces = {}
        for segment in segments:
            top = 50 + (bottom - 50) * segment.slot / segment.total
            low = 50 + (bottom - 50) * (segment.slot + 1) / segment.total
            left, right = x(segment.start), x(segment.end)
            pieces.setdefault(segment.event.id, []).append((left, max(left + 3, right), top, low))
        visible_events = {segment.event.id: segment.event for segment in segments}
        for event_id, rectangles in pieces.items():
            event = visible_events[event_id]
            tags = (f"event:{event_id}", "event-body")
            options = dict(fill=tag_color(self.store, event.tag_id, event_id in self.selected),
                           outline="#111111" if event_id in self.selected else "#cccccc",
                           width=3 if event_id in self.selected else 1, tags=tags)
            if all((top, low) == rectangles[0][2:] for _, _, top, low in rectangles):
                canvas.create_rectangle(
                    rectangles[0][0], rectangles[0][2], rectangles[-1][1], rectangles[-1][3], **options
                )
            else:
                outline = [(value, top) for left, right, top, low in rectangles for value in (left, right)]
                outline += [(value, low) for left, right, top, low in reversed(rectangles) for value in (right, left)]
                canvas.create_polygon(*[coordinate for point in outline for coordinate in point], **options)
            left, right, top, low = max(rectangles, key=lambda item: (item[1] - item[0]) * (item[3] - item[2]))
            available = right - left - 12
            if available >= 20 and low - top >= 18:
                limit = max(1, int(available / 13))
                title = event.title if len(event.title) <= limit else event.title[:max(1, limit - 1)] + "…"
                canvas.create_text(left + 7, (top + low) / 2, text=title, fill="#111111",
                                   anchor="w", font=("Microsoft YaHei UI", 10), tags=(f"event:{event_id}",))
        if not segments:
            canvas.create_text(width / 2 + 24, bottom / 2, text="这一天还没有记录。", fill="#111111", font=("Microsoft YaHei UI", 11))
        if len(self.selected) == 1 and (event := visible_events.get(next(iter(self.selected)))):
            start, end = event.interval_on(self.day)
            for edge, moment, clipped in (("start", event.start, start), ("end", event.end, end)):
                if moment != clipped:
                    continue
                xpos = x(moment)
                canvas.create_line(xpos, 50, xpos, bottom, fill="#111111", dash=(3, 3), tags=("resize-guide",))
                outside = xpos - 12 if edge == "start" else xpos + 12
                canvas.create_line(xpos, bottom + 12, outside, bottom + 12, fill="#111111", width=2,
                                   arrow=tk.LAST, arrowshape=(5, 6, 3), tags=(f"resize:{edge}:{event.id}",))
        now = datetime.now()
        if self.day == now.date():
            current = x(now)
            canvas.create_line(current, 42, current, bottom, fill="#c46d49", width=2, dash=(3, 3))
            canvas.create_polygon(current - 4, 39, current + 4, 39, current, 45, fill="#c46d49")

    def _tick_intervals(self, width):
        major = 120 if self.zoom == 1 else 60 if self.zoom < 2 else 30 if self.zoom < 3 else 15
        # Narrow windows use a larger label interval to keep the times readable.
        while width * major / 1440 < self.tick_font.measure("00:00") + 14:
            major *= 2
        minor = 60 if major >= 120 else 15 if major == 60 else 10 if major == 30 else 5
        return major, minor

    def _event_at(self, pointer):
        xpos, ypos = self.canvas.canvasx(pointer.x), self.canvas.canvasy(pointer.y)
        for item in reversed(self.canvas.find_overlapping(xpos - 2, ypos - 2, xpos + 2, ypos + 2)):
            for tag in self.canvas.gettags(item):
                if tag.startswith("event:"):
                    return self.store.events.get(tag[6:])
        return None

    def _click(self, pointer):
        self._hide_tooltip()
        if handle := self._handle_at(pointer):
            edge, event_id = handle
            if self.on_select(event_id) is False:
                return "break"
            event = self.store.events[event_id]
            width = max(650, self.canvas.winfo_width() - 48) * self.zoom
            origin = datetime.combine(self.day, time.min)
            edge_x = 24 + (getattr(event, edge) - origin).total_seconds() / 86400 * width
            self._resize = dict(edge=edge, original=event, preview=event, origin_x=pointer.x, moved=False,
                                offset=self.canvas.canvasx(pointer.x) - edge_x)
            self.canvas.focus_force()
            self.canvas.grab_set()
            return "break"
        if event := self._event_at(pointer):
            self.on_select(event.id)
            self.canvas.focus_force()
        else:
            self.on_select(None)

    def _double_click(self, pointer):
        if self._handle_at(pointer):
            return self._click(pointer)
        if event := self._event_at(pointer):
            self.on_edit(event.id)

    def _handle_at(self, pointer):
        x, y = self.canvas.canvasx(pointer.x), self.canvas.canvasy(pointer.y)
        for item in reversed(self.canvas.find_overlapping(x - 3, y - 3, x + 3, y + 3)):
            for tag in self.canvas.gettags(item):
                if tag.startswith("resize:"):
                    _, edge, event_id = tag.split(":", 2)
                    return edge, event_id
        return None

    def _resize_motion(self, pointer):
        if self._resize is None:
            return
        if not self._resize["moved"] and abs(pointer.x - self._resize["origin_x"]) < 2:
            return
        self._resize["moved"] = True
        if pointer.x < 16:
            self.canvas.xview_scroll(-1, "units")
        elif pointer.x > self.canvas.winfo_width() - 16:
            self.canvas.xview_scroll(1, "units")
        width = max(650, self.canvas.winfo_width() - 48) * self.zoom
        xpos = self.canvas.canvasx(pointer.x) - self._resize["offset"]
        minutes = min(1440, max(0, round((xpos - 24) / width * 1440)))
        try:
            moment = datetime.combine(self.day, time.min) + timedelta(minutes=minutes)
        except OverflowError:
            moment = datetime.max.replace(second=0, microsecond=0)
        original = self._resize["original"]
        edge = self._resize["edge"]
        try:
            if edge == "start" and moment >= original.end:
                moment = (original.end - timedelta(minutes=1)).replace(second=0, microsecond=0)
            elif edge == "end" and moment <= original.start:
                moment = original.start.replace(second=0, microsecond=0) + timedelta(minutes=1)
        except OverflowError:
            moment = getattr(original, edge)
        self._resize["preview"] = replace(original, **{edge: moment})
        self.canvas.configure(cursor="sb_h_double_arrow")
        self.draw()
        return "break"

    def _resize_release(self, _):
        if self._resize is None:
            return
        state, self._resize = self._resize, None
        if self.canvas.grab_current() is self.canvas:
            self.canvas.grab_release()
        if state["moved"] and state["preview"] != state["original"]:
            self.on_resize(state["preview"])
        self.canvas.configure(cursor="")
        self.draw()
        return "break"

    def cancel_resize(self):
        if self._resize is not None:
            self._resize = None
            if self.canvas.grab_current() is self.canvas:
                self.canvas.grab_release()
            self.canvas.configure(cursor="")
            self.draw()
        return "break"

    def _hover(self, pointer):
        if self._resize is not None:
            return
        if self._handle_at(pointer):
            self.canvas.configure(cursor="sb_h_double_arrow")
            self._hide_tooltip()
            return
        event = self._event_at(pointer)
        self.canvas.configure(cursor="hand2" if event else "")
        if event is None:
            self._hide_tooltip()
            return
        if event.id == self.hovered_id:
            return
        self._hide_tooltip()
        self.hovered_id = event.id
        start, end = event.interval_on(self.day)
        end_text = "24:00" if end.date() > self.day else end.strftime("%H:%M")
        description = (f"{event.title}\n{self.store.tag_outline(event.tag_id)}\n"
                       f"{start:%H:%M} — {end_text} · {duration_text((end-start).total_seconds())}")
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
        if not pointer.delta or self._resize is not None:
            return "break"
        direction = 1 if pointer.delta > 0 else -1
        if pointer.state & 0x4:
            zoom = min(4, max(1, self.zoom + direction * 0.25))
            if zoom != self.zoom:
                width = max(650, self.canvas.winfo_width() - 48)
                # Keep the time under the pointer in place while changing scale.
                fraction = (self.canvas.canvasx(pointer.x) - 24) / (width * self.zoom)
                self.zoom = zoom
                self.draw()
                left = 24 + fraction * width * zoom - pointer.x
                self.canvas.xview_moveto(left / (width * zoom + 48))
        elif pointer.state & 0x1:
            self.canvas.yview_scroll(-direction, "units")
        else:
            self.canvas.xview_scroll(-direction, "units")
        return "break"
