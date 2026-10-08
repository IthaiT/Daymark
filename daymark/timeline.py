"""Scrollable daily timeline; event geometry is based on actual timestamps."""

import hashlib
import tkinter as tk
import tkinter.font as tkfont
from dataclasses import replace
from datetime import datetime, time, timedelta
from tkinter import ttk

from .model import duration_text, move_event_on_day, timeline_segments
from .widgets import AutoScrollbar

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
    def __init__(self, parent, store, on_select, on_edit, on_change, on_context):
        super().__init__(parent)
        self.store, self.on_select, self.on_edit = store, on_select, on_edit
        self.on_change = on_change
        self.on_context = on_context
        self._pieces = {}
        self._drag = None
        self.canvas = tk.Canvas(self, height=280, bg="white", highlightthickness=1, highlightbackground="#e5e5e5")
        self.tick_font = tkfont.Font(self.canvas, family="Microsoft YaHei UI", size=9)
        self.canvas.grid(row=0, column=0, sticky="nsew")
        horizontal = AutoScrollbar(self, orient="horizontal", command=self.canvas.xview)
        horizontal.grid(row=1, column=0, sticky="ew")
        vertical = AutoScrollbar(self, orient="vertical", command=self.canvas.yview)
        vertical.grid(row=0, column=1, sticky="ns")
        self.canvas.configure(xscrollcommand=horizontal.set, yscrollcommand=vertical.set)
        self.columnconfigure(0, weight=1)
        self.rowconfigure(0, weight=1)
        self.canvas.bind("<Configure>", lambda _: self.draw())
        self.canvas.bind("<Button-1>", self._click)
        self.canvas.bind("<B1-Motion>", self._drag_motion)
        self.canvas.bind("<ButtonRelease-1>", self._drag_release)
        self.canvas.bind("<Escape>", lambda _: self.cancel_drag())
        self.canvas.bind("<Double-1>", self._double_click)
        self.canvas.bind("<Button-3>", self._context_menu)
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
        width = self._day_width()
        events = self.events
        if self._drag is not None:
            preview = self._drag["preview"]
            events = [preview if event.id == preview.id else event for event in events]
        segments = timeline_segments(events, self.day)
        bottom = max(90, canvas.winfo_height() - 26)
        canvas.configure(scrollregion=(0, 0, width + 48, bottom + 24))
        origin = datetime.combine(self.day, time.min)

        def x(moment):
            return 24 + (moment - origin).total_seconds() / 86400 * width

        major, minor = self._tick_intervals(width)
        dragging = self._drag is not None and self._drag["moved"]
        if dragging:
            minor = min(minor, self._snap_interval())
        for minute in range(0, 1441, minor):
            xpos = 24 + minute / 1440 * width
            is_major = minute % major == 0
            canvas.create_line(xpos, 43, xpos, bottom if is_major else 49,
                               fill="#e5e5e5" if is_major else "#bbbbbb", tags=("time-tick", "drag-scale") if dragging else ("time-tick",))
            if dragging and not is_major:
                canvas.create_line(xpos, 50, xpos, bottom, fill="#f0f2f5", tags=("drag-scale",))
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
        self._pieces = pieces
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
                title = event.title or "新事件"
                title = title if len(title) <= limit else title[:max(1, limit - 1)] + "…"
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
                endpoint = pieces[event.id][0 if edge == "start" else -1]
                canvas.create_line(xpos, endpoint[2], xpos, endpoint[3], fill="#111111", width=3,
                                   tags=(f"resize:{edge}:{event.id}",))
        now = datetime.now()
        if self.day == now.date():
            current = x(now)
            canvas.create_line(current, 42, current, bottom, fill="#c46d49", width=2, dash=(3, 3))
            canvas.create_polygon(current - 4, 39, current + 4, 39, current, 45, fill="#c46d49")
        if dragging:
            preview = self._drag["preview"]
            start, end = preview.interval_on(self.day)
            for edge, moment in (("start", start), ("end", end)):
                xpos = x(moment)
                canvas.create_line(xpos, 42, xpos, bottom, fill="#2563eb", dash=(4, 3), width=1,
                                   tags=("drag-guide",))
                label = "24:00" if moment.date() > self.day else moment.strftime("%H:%M")
                label_x = min(canvas.canvasx(0) + canvas.winfo_width() - 28,
                              max(canvas.canvasx(0) + 28, xpos))
                # Put the two times at different heights so short events stay legible.
                item = canvas.create_text(label_x, 34 if edge == "start" else bottom - 12,
                                          text=label, fill="#2563eb", font=("Microsoft YaHei UI", 10, "bold"),
                                          tags=("drag-time",))
                bounds = canvas.bbox(item)
                background = canvas.create_rectangle(bounds[0] - 4, bounds[1] - 2, bounds[2] + 4, bounds[3] + 2,
                                                     fill="white", outline="#bfdbfe", tags=("drag-time",))
                canvas.tag_raise(item, background)
            if (snap := self._drag.get("snap")) is not None:
                canvas.create_line(x(snap), 43, x(snap), bottom, fill="#2563eb", width=2, tags=("snap-guide",))

    def _snap_interval(self):
        return 15 if self.zoom < 2 else 5 if self.zoom < 4 else 1

    def _day_width(self):
        return max(650, self.canvas.winfo_width() - 50) * self.zoom

    def _get_event(self, event_id):
        return next((event for event in self.events if event.id == event_id), None)

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
                    return self._get_event(tag[6:])
        return None

    def _click(self, pointer):
        self._hide_tooltip()
        if handle := self._handle_at(pointer):
            edge, event_id = handle
        elif event := self._event_at(pointer):
            edge, event_id = "move", event.id
        else:
            self.on_select(None)
            return "break"
        if self.on_select(event_id) is False:
            return "break"
        event = self._get_event(event_id)
        if event is None:
            return "break"
        if event.interval_on(self.day) is None:
            return "break"
        width = self._day_width()
        origin = datetime.combine(self.day, time.min)
        moment = event.start if edge == "move" else getattr(event, edge)
        edge_x = 24 + (moment - origin).total_seconds() / 86400 * width
        self._drag = dict(edge=edge, original=event, preview=event, origin_x=pointer.x, moved=False,
                          anchor_x=self.canvas.canvasx(pointer.x), offset=self.canvas.canvasx(pointer.x) - edge_x)
        self.canvas.focus_force()
        self.canvas.grab_set()
        return "break"

    def _double_click(self, pointer):
        if self._handle_at(pointer):
            return self._click(pointer)
        if event := self._event_at(pointer):
            self.cancel_drag()
            self.on_edit(event.id)

    def _handle_at(self, pointer):
        x, y = self.canvas.canvasx(pointer.x), self.canvas.canvasy(pointer.y)
        matches = []
        origin = datetime.combine(self.day, time.min) if self.day is not None else None
        width = self._day_width()
        for event_id, rectangles in reversed(list(self._pieces.items())):
            event = self._get_event(event_id)
            start, end = event.interval_on(self.day)
            for edge, moment, clipped, rectangle in (("start", event.start, start, rectangles[0]),
                                                    ("end", event.end, end, rectangles[-1])):
                xpos = 24 + (moment - origin).total_seconds() / 86400 * width
                if moment == clipped and abs(x - xpos) <= 6 and rectangle[2] - 2 <= y <= rectangle[3] + 2:
                    matches.append((abs(x - xpos), event_id not in self.selected, edge, event_id))
        if matches:
            _, _, edge, event_id = min(matches, key=lambda match: (match[0], match[1]))
            return edge, event_id
        return None

    def _context_menu(self, pointer):
        self._hide_tooltip()
        event = self._event_at(pointer)
        width = self._day_width()
        step = self._snap_interval()
        minute = min(1439, max(0, round((self.canvas.canvasx(pointer.x) - 24) / width * 1440 / step) * step))
        start = datetime.combine(self.day, time.min) + timedelta(minutes=minute)
        return self.on_context(pointer, event.id if event else None, start)

    def _snap_offset(self, moments, event_id, pointer):
        self._drag["snap"] = None
        if pointer.state & (0x20000 | 0x8):  # Alt allows free minute-level adjustment.
            return 0
        origin = datetime.combine(self.day, time.min)
        step = self._snap_interval()
        candidates = []
        for moment in moments:
            minutes = (moment - origin).total_seconds() / 60
            grid = min(1440, max(0, round(minutes / step) * step))
            try:
                targets = [origin + timedelta(minutes=grid)]
            except OverflowError:
                targets = [datetime.max]
            for event in self.events:
                if event.id != event_id and (interval := event.interval_on(self.day)):
                    targets.extend(interval)
            for target in targets:
                difference = (target - moment).total_seconds() / 60
                candidates.append((abs(difference), difference, target))
        distance, difference, target = min(candidates, key=lambda candidate: candidate[0])
        width = self._day_width()
        if distance * width / 1440 <= 6:
            self._drag["snap"] = target
            return round(difference)
        return 0

    def _drag_motion(self, pointer):
        if self._drag is None:
            return
        threshold = 4 if self._drag["edge"] == "move" else 2
        if not self._drag["moved"] and abs(pointer.x - self._drag["origin_x"]) < threshold:
            return
        self._drag["moved"] = True
        if pointer.x < 16:
            self.canvas.xview_scroll(-1, "units")
        elif pointer.x > self.canvas.winfo_width() - 16:
            self.canvas.xview_scroll(1, "units")
        width = self._day_width()
        original, edge = self._drag["original"], self._drag["edge"]
        if edge == "move":
            minutes = round((self.canvas.canvasx(pointer.x) - self._drag["anchor_x"]) / width * 1440)
            preview = move_event_on_day(original, self.day, minutes)
            correction = self._snap_offset(preview.interval_on(self.day), original.id, pointer)
            self._drag["preview"] = move_event_on_day(original, self.day, minutes + correction)
            self.canvas.configure(cursor="fleur")
        else:
            xpos = self.canvas.canvasx(pointer.x) - self._drag["offset"]
            minutes = min(1440, max(0, round((xpos - 24) / width * 1440)))
            try:
                moment = datetime.combine(self.day, time.min) + timedelta(minutes=minutes)
            except OverflowError:
                moment = datetime.max.replace(second=0, microsecond=0)
            correction = self._snap_offset((moment,), original.id, pointer)
            try:
                moment += timedelta(minutes=correction)
            except OverflowError:
                pass
            try:
                if edge == "start" and moment >= original.end:
                    moment = (original.end - timedelta(minutes=1)).replace(second=0, microsecond=0)
                elif edge == "end" and moment <= original.start:
                    moment = original.start.replace(second=0, microsecond=0) + timedelta(minutes=1)
            except OverflowError:
                moment = getattr(original, edge)
            self._drag["preview"] = replace(original, **{edge: moment})
            self.canvas.configure(cursor="sb_h_double_arrow")
        self.draw()
        return "break"

    def _drag_release(self, _):
        if self._drag is None:
            return
        state, self._drag = self._drag, None
        if self.canvas.grab_current() is self.canvas:
            self.canvas.grab_release()
        if state["moved"] and state["preview"] != state["original"]:
            self.on_change(state["preview"])
        self.canvas.configure(cursor="")
        self.on_select(None)
        return "break"

    def cancel_drag(self):
        if self._drag is not None:
            self._drag = None
            if self.canvas.grab_current() is self.canvas:
                self.canvas.grab_release()
            self.canvas.configure(cursor="")
            self.on_select(None)
        return "break"

    def _hover(self, pointer):
        if self._drag is not None:
            return
        if self._handle_at(pointer):
            self.canvas.configure(cursor="sb_h_double_arrow")
            self._hide_tooltip()
            return
        event = self._event_at(pointer)
        self.canvas.configure(cursor=("fleur" if event.id in self.selected else "hand2") if event else "")
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
        if not pointer.delta or self._drag is not None:
            return "break"
        direction = 1 if pointer.delta > 0 else -1
        if pointer.state & 0x4:
            zoom = min(4, max(1, self.zoom + direction * 0.25))
            if zoom != self.zoom:
                width = self._day_width() / self.zoom
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
