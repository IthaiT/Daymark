"""The Daymark desktop journal and direct tag-tree interactions."""

import tkinter as tk
from dataclasses import replace
from datetime import date, datetime, timedelta
from tkinter import messagebox, ttk
from uuid import uuid4

from .dialogs import EventDialog, TagDialog
from .history import History
from .inline import CellEditor
from .model import Event, default_event_interval, duration_text, undefined_events
from .timeline import Timeline, tag_color
from .widgets import AutoScrollbar, DatePicker

FONT = "Microsoft YaHei UI"


class App(tk.Tk):
    def __init__(self, store):
        super().__init__()
        self.store = store
        self.history = History()
        self.store.on_events_change = self.history.record
        self.title("Daymark")
        self.configure(bg="white")
        width, height = min(1360, self.winfo_screenwidth() - 80), min(900, self.winfo_screenheight() - 64)
        xpos = max(0, (self.winfo_screenwidth() - width) // 2)
        ypos = max(0, (self.winfo_screenheight() - height - 40) // 2)
        self.geometry(f"{width}x{height}+{xpos}+{ypos}")
        self.minsize(1100, 740)
        self.day = date.today()
        self.cell_editor = None
        self.drafts = {}
        self.undefined = {}
        self.undefined_names = {}
        self._pressed_cell = None
        self._drag_source = None
        self._drag_active = False
        self._drop_target = None
        self._drop_valid = False
        self._drag_preview = None
        self._expand_job = None
        self._configure_styles()
        self.columnconfigure(1, weight=1)
        self.rowconfigure(0, weight=1)
        self._build_sidebar()
        self._build_main()
        self.refresh_tags()
        self.refresh()
        self.bind("<Control-n>", lambda _: self.add_event() if self.grab_current() is None else None)
        self.bind("<Control-Left>", lambda _: self.shift_day(-1) if self.grab_current() is None else None)
        self.bind("<Control-Right>", lambda _: self.shift_day(1) if self.grab_current() is None else None)
        self.bind("<Control-z>", lambda _: self.undo() if self.grab_current() is None else None)
        self.bind("<Control-Z>", lambda _: self.redo() if self.grab_current() is None else None)
        self.bind("<Control-y>", lambda _: self.redo() if self.grab_current() is None else None)
        self.bind("<Control-Y>", lambda _: self.redo() if self.grab_current() is None else None)
        self.bind("<Button-1>", self.background_click)
        self.bind("<<PickerDismissed>>", self.picker_dismissed)
        self.bind("<Delete>", self.delete_key)
        self.protocol("WM_DELETE_WINDOW", self.close)

    def _configure_styles(self):
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure(".", font=(FONT, 10), background="white", foreground="#111111")
        style.configure("TFrame", background="white")
        style.configure("TLabel", background="white", foreground="#111111")
        style.configure("Heading.TLabel", font=(FONT, 12, "bold"))
        style.configure("Logo.TLabel", font=(FONT, 23, "bold"))
        style.configure("TButton", padding=(12, 8), background="white", bordercolor="#d4d4d4", borderwidth=1)
        style.map("TButton", background=[("active", "#f3f4f6")], foreground=[("disabled", "#999999")])
        style.configure("Accent.TButton", font=(FONT, 10, "bold"))
        style.configure("Icon.TButton", font=(FONT, 16), padding=(8, 4))
        style.configure("Selected.TButton", background="#e5e7eb")
        style.configure("TEntry", padding=7, fieldbackground="white", bordercolor="#d4d4d4")
        style.map("TEntry", fieldbackground=[("readonly", "white")], foreground=[("readonly", "#111111")])
        style.configure("Treeview", background="white", fieldbackground="white", foreground="#111111",
                        rowheight=36, borderwidth=0, indicatorsize=16)
        style.map("Treeview", background=[], foreground=[("selected", "#111111")])
        style.map("Tags.Treeview", background=[("selected", "#e5e7eb")], foreground=[("selected", "#111111")])
        style.configure("Treeview.Heading", background="white", font=(FONT, 10), padding=(6, 9))
        style.configure("Tooltip.TLabel", background="white", foreground="#111111", relief="solid", borderwidth=1)
        for direction, sticky in (("Horizontal", "ew"), ("Vertical", "ns")):
            name = f"{direction}.TScrollbar"
            style.layout(name, [(f"{direction}.Scrollbar.trough", {"sticky": "nsew", "children": [
                (f"{direction}.Scrollbar.thumb", {"sticky": sticky, "expand": True}),
            ]})])
            style.configure(name, background="#cbd0d6", troughcolor="#f5f6f7", borderwidth=0,
                            bordercolor="#f5f6f7", lightcolor="#cbd0d6", darkcolor="#cbd0d6",
                            arrowsize=9, width=9)
            style.map(name, background=[("active", "#aeb5be"), ("pressed", "#929ba7")])

    def _build_sidebar(self):
        sidebar = ttk.Frame(self, padding=(20, 24))
        sidebar.grid(row=0, column=0, sticky="nsew")
        sidebar.configure(width=250)
        sidebar.grid_propagate(False)
        sidebar.columnconfigure(0, weight=1)
        sidebar.rowconfigure(2, weight=1)
        ttk.Label(sidebar, text="Daymark", style="Logo.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 28))
        ttk.Label(sidebar, text="我的标签", style="Heading.TLabel").grid(row=1, column=0, sticky="w", pady=(0, 12))
        tree_box = ttk.Frame(sidebar)
        tree_box.grid(row=2, column=0, sticky="nsew")
        tree_box.columnconfigure(0, weight=1)
        tree_box.rowconfigure(0, weight=1)
        self.tags_tree = ttk.Treeview(tree_box, show="tree", selectmode="browse", style="Tags.Treeview")
        self.tags_tree.column("#0", width=180, minwidth=80)
        self.tags_tree.grid(row=0, column=0, sticky="nsew")
        scroll = AutoScrollbar(tree_box, command=self.tags_tree.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.tags_tree.configure(yscrollcommand=scroll.set)
        self.tags_tree.tag_configure("drop", background="#f0f0f0")
        self.tags_tree.bind("<Button-3>", self.tag_context_menu)
        self.tags_tree.bind("<ButtonPress-1>", self.drag_start)
        self.tags_tree.bind("<B1-Motion>", self.drag_motion)
        self.tags_tree.bind("<ButtonRelease-1>", self.drag_release)
        self.tags_tree.bind("<Escape>", lambda _: self.cancel_drag())
        ttk.Separator(self, orient="vertical").grid(row=0, column=0, sticky="nse")

    def _build_main(self):
        main = ttk.Frame(self, padding=(24, 24))
        main.grid(row=0, column=1, sticky="nsew")
        main.columnconfigure(0, weight=1)
        main.rowconfigure(1, weight=1, minsize=280)
        main.rowconfigure(2, weight=1, minsize=250)
        date_bar = ttk.Frame(main)
        date_bar.grid(row=0, column=0, sticky="ew", pady=(0, 24))
        ttk.Button(date_bar, text="‹", width=2, style="Icon.TButton", command=lambda: self.shift_day(-1)).pack(side="left")
        self.date_picker = DatePicker(date_bar, self.day, on_change=self.set_day)
        self.date_picker.pack(side="left", padx=8)
        self.date_picker.entry.bind("<Return>", lambda _: self.set_day())
        ttk.Button(date_bar, text="›", width=2, style="Icon.TButton", command=lambda: self.shift_day(1)).pack(side="left", padx=8)
        ttk.Button(date_bar, text="今天", command=self.go_today).pack(side="left")
        self.weekday_label = ttk.Label(date_bar)
        self.weekday_label.pack(side="left", padx=14)
        timeline_box = ttk.Frame(main)
        timeline_box.grid(row=1, column=0, sticky="nsew", pady=(0, 24))
        timeline_box.columnconfigure(0, weight=1)
        timeline_box.rowconfigure(1, weight=1)
        ttk.Label(timeline_box, text="一天的轨迹", style="Heading.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 12))
        self.timeline = Timeline(timeline_box, self.store, self.select_event, self.rename_event, self.update_event_time,
                                 self.timeline_context_menu, self.position_cell)
        self.timeline.grid(row=1, column=0, sticky="nsew")
        bottom = ttk.Frame(main)
        bottom.grid(row=2, column=0, sticky="nsew")
        bottom.columnconfigure(0, weight=1)
        bottom.rowconfigure(1, weight=1)
        toolbar = ttk.Frame(bottom)
        toolbar.grid(row=0, column=0, sticky="ew", pady=(0, 12))
        self.events_heading = ttk.Label(toolbar, text="事件明细", style="Heading.TLabel")
        self.events_heading.pack(side="left")
        self.add_event_button = ttk.Button(toolbar, text="＋ 新增事件", command=self.add_event, style="Accent.TButton")
        self.add_event_button.pack(side="right")
        table_box = ttk.Frame(bottom)
        table_box.grid(row=1, column=0, sticky="nsew")
        table_box.columnconfigure(0, weight=1)
        table_box.rowconfigure(0, weight=1)
        self.events_tree = ttk.Treeview(table_box, columns=("title", "start", "end", "tag", "duration"),
                                       show="headings", selectmode="extended", height=8)
        for column, label, width in (("title", "事件", 240), ("start", "开始", 110), ("end", "结束", 110),
                                     ("tag", "标签", 180), ("duration", "本日用时", 130)):
            self.events_tree.heading(column, text=label)
            self.events_tree.column(column, width=width, minwidth=width, stretch=column in ("title", "tag"))
        self.events_tree.grid(row=0, column=0, sticky="nsew")
        table_y = AutoScrollbar(table_box, command=lambda *args: self.scroll_events("y", *args))
        table_y.grid(row=0, column=1, sticky="ns")
        table_x = AutoScrollbar(table_box, orient="horizontal", command=lambda *args: self.scroll_events("x", *args))
        table_x.grid(row=1, column=0, sticky="ew")
        self.events_tree.configure(yscrollcommand=table_y.set, xscrollcommand=table_x.set)
        self.events_tree.bind("<Double-1>", self.event_double_click)
        self.events_tree.bind("<Button-1>", self.event_press)
        self.events_tree.bind("<ButtonRelease-1>", self.event_release)
        self.events_tree.bind("<Button-3>", self.event_context_menu)
        self.events_tree.bind("<<TreeviewSelect>>", lambda _: self.draw_timeline())
        self.events_tree.bind("<Configure>", lambda _: self.position_cell())
        self.events_tree.bind("<MouseWheel>", lambda _: None if self.commit_cell() else "break")

    def refresh_tags(self, selected=None):
        selected = selected or self.selected_tag()
        initial = not self.tags_tree.get_children()
        expanded = {tag_id for tag_id in self.store.tags if self.tags_tree.exists(tag_id) and self.tags_tree.item(tag_id, "open")}
        self.tags_tree.delete(*self.tags_tree.get_children())
        for tag in self.store.ordered_tags():
            self.tags_tree.insert(tag.parent_id or "", "end", iid=tag.id, text=tag.name, open=initial or tag.id in expanded)
        if selected in self.store.tags:
            self.tags_tree.selection_set(selected)
            self.tags_tree.see(selected)

    def refresh(self):
        self.cancel_cell()
        self.drafts = {event_id: replace(event, tag_id=None) if event.tag_id is not None and event.tag_id not in self.store.tags else event
                       for event_id, event in self.drafts.items()}
        selected = self.events_tree.selection()
        events = self.visible_events()
        gaps = undefined_events(events, self.day)
        self.undefined = {event.id: replace(event, title=self.undefined_names.get(event.id, event.title))
                          for event in gaps}
        self.undefined_names = {event_id: title for event_id, title in self.undefined_names.items()
                                if event_id in self.undefined}
        events = sorted([*events, *self.undefined.values()], key=lambda event: (event.start, event.id))
        self.events_tree.delete(*self.events_tree.get_children())
        for event in events:
            interval = event.interval_on(self.day)
            def clock(moment):
                return moment.strftime("%H:%M") if moment.date() == self.day else moment.strftime("%m-%d %H:%M")
            color_tag = f"event-color:{event.id}"
            self.events_tree.tag_configure(color_tag, background=self.event_color(event))
            self.events_tree.insert("", "end", iid=event.id, tags=(color_tag,), values=(
                event.title or "填写事件名称…", clock(event.start), clock(event.end) if event.end else "待补全",
                self.store.tag_name(event.tag_id), duration_text((interval[1] - interval[0]).total_seconds()) if interval else "—",
            ))
        self.events_tree.selection_set([event_id for event_id in selected if self.events_tree.exists(event_id)])
        self.events_heading.configure(text=f"事件明细 · {len(events)}")
        self.date_picker.value.set(self.day.isoformat())
        self.weekday_label.configure(text="星期" + "一二三四五六日"[self.day.weekday()])
        self.draw_timeline()

    def visible_events(self):
        events = self.store.events_on(self.day)
        events.extend(event for event in self.drafts.values() if event.interval_on(self.day))
        return sorted(events, key=lambda event: (event.start, event.id))

    def get_event(self, event_id):
        return self.drafts.get(event_id) or self.store.events.get(event_id) or self.undefined.get(event_id)

    def event_color(self, event, selected=False):
        if event.tag_id is None and not selected:
            return "#f5f6f7"
        return tag_color(self.store, event.tag_id, selected)

    def draw_timeline(self):
        selected = set(self.events_tree.selection())
        for event_id in self.events_tree.get_children():
            event = self.get_event(event_id)
            self.events_tree.tag_configure(f"event-color:{event_id}",
                                           background=self.event_color(event, event_id in selected),
                                           font=(FONT, 10, "bold" if event_id in selected else "normal"))
        self.timeline.update_events(self.visible_events(), self.day, selected, self.undefined_names)

    def clear_event_selection(self):
        if not self.commit_cell():
            return False
        self.events_tree.selection_remove(*self.events_tree.selection())
        self.events_tree.focus("")
        self.draw_timeline()
        return True

    def background_click(self, pointer):
        if self.grab_current() is not None or pointer.widget in (self.timeline.canvas, self.events_tree):
            return
        if isinstance(pointer.widget, ttk.Scrollbar):
            return
        if self.cell_editor is not None and str(pointer.widget).startswith(str(self.cell_editor) + "."):
            return
        self.clear_event_selection()

    def picker_dismissed(self, pointer):
        if self.cell_editor is None or self.grab_current() is not None:
            return
        target = self.winfo_containing(pointer.x_root, pointer.y_root)
        if target is None or target.winfo_toplevel() is not self:
            self.clear_event_selection()
            return
        # The popup consumed the press. Deliver it to the clicked widget;
        # the normal mouse release will complete selection or cell editing.
        target.event_generate("<ButtonPress-1>", x=pointer.x_root - target.winfo_rootx(),
                              y=pointer.y_root - target.winfo_rooty(),
                              rootx=pointer.x_root, rooty=pointer.y_root,
                              state=pointer.state, time=pointer.time)

    def event_press(self, pointer):
        self._pressed_cell = None
        event_id = self.events_tree.identify_row(pointer.y)
        column_id = self.events_tree.identify_column(pointer.x)
        selected = self.events_tree.selection() == (event_id,)
        if not self.commit_cell():
            return "break"
        if not event_id:
            self.clear_event_selection()
            return "break"
        if not pointer.state & (0x1 | 0x4) and self.events_tree.identify_region(pointer.x, pointer.y) == "cell":
            if selected:
                self._pressed_cell = (event_id, column_id, pointer.x, pointer.y)
            self.events_tree.selection_set(event_id)
            self.events_tree.focus(event_id)
            self.events_tree.focus_set()
            self.draw_timeline()
            return "break"

    def event_release(self, pointer):
        pressed, self._pressed_cell = self._pressed_cell, None
        if pressed is None or pointer.state & (0x1 | 0x4):
            return
        event_id, column_id, x, y = pressed
        if abs(pointer.x - x) + abs(pointer.y - y) < 6 and column_id in ("#1", "#2", "#3", "#4"):
            column = self.events_tree["columns"][int(column_id[1:]) - 1]
            self.edit_cell(event_id, column)
            return "break"

    def delete_key(self, pointer):
        if self.cell_editor is None and self.grab_current() is None and pointer.widget in (self.events_tree, self.timeline.canvas):
            self.delete_events()
            return "break"

    def selected_tag(self):
        selected = self.tags_tree.selection()
        return selected[0] if selected else None

    def tag_saved(self, tag_id):
        self.refresh_tags(tag_id)
        self.refresh()

    def add_tag(self, parent_id=None):
        TagDialog(self, self.store, self.tag_saved, parent_id=parent_id)

    def edit_tag(self):
        if tag_id := self.selected_tag():
            TagDialog(self, self.store, self.tag_saved, tag_id=tag_id)

    def delete_tag(self):
        if tag_id := self.selected_tag():
            if messagebox.askyesno("删除标签", f"删除「{self.store.tag_name(tag_id)}」？", parent=self):
                if self.try_action(lambda: self.store.delete_tag(tag_id)):
                    self.refresh_tags()
                    self.refresh()

    def tag_context_menu(self, pointer):
        if not self.commit_cell():
            return
        self.cancel_drag()
        tag_id = self.tags_tree.identify_row(pointer.y)
        if tag_id:
            self.tags_tree.selection_set(tag_id)
        else:
            self.tags_tree.selection_remove(self.tags_tree.selection())
        if hasattr(self, "tag_menu"):
            self.tag_menu.destroy()
        self.tag_menu = menu = tk.Menu(self, tearoff=False, bg="white", fg="#111111",
                                       activebackground="#e5e7eb", activeforeground="#111111")
        menu.add_command(label="新增子标签" if tag_id else "新增一级标签", command=lambda: self.add_tag(tag_id or None))
        if tag_id:
            menu.add_command(label="修改标签", command=self.edit_tag)
            menu.add_command(label="删除标签", command=self.delete_tag)
            if self.store.tags[tag_id].parent_id:
                menu.add_separator()
                menu.add_command(label="移至一级标签", command=lambda: self.move_tag(tag_id, None))
        try:
            menu.tk_popup(pointer.x_root, pointer.y_root)
        finally:
            menu.grab_release()

    def drag_start(self, pointer):
        self.cancel_drag()
        row = self.tags_tree.identify_row(pointer.y)
        element = self.tags_tree.identify_element(pointer.x, pointer.y)
        if row and "indicator" not in element:
            self._drag_source = row
            self._drag_origin = (pointer.x, pointer.y)

    def drag_motion(self, pointer):
        if not self._drag_source:
            return
        if not self._drag_active and abs(pointer.x - self._drag_origin[0]) + abs(pointer.y - self._drag_origin[1]) < 6:
            return
        self._drag_active = True
        target = self.tags_tree.identify_row(pointer.y) or None
        inside = 0 <= pointer.x < self.tags_tree.winfo_width() and 0 <= pointer.y < self.tags_tree.winfo_height()
        self._drop_valid = inside and target not in self.store.descendants(self._drag_source)
        if target != self._drop_target:
            self._clear_drop_highlight()
            self._drop_target = target
            if target and self._drop_valid:
                self.tags_tree.item(target, tags=("drop",))
                self._expand_job = self.after(450, lambda target=target: self.tags_tree.item(target, open=True))
        self.tags_tree.configure(cursor="fleur" if self._drop_valid else "X_cursor")
        if pointer.y < 24:
            self.tags_tree.yview_scroll(-1, "units")
        elif pointer.y > self.tags_tree.winfo_height() - 24:
            self.tags_tree.yview_scroll(1, "units")
        if self._drag_preview is None:
            self._drag_preview = tk.Toplevel(self)
            self._drag_preview.overrideredirect(True)
            ttk.Label(self._drag_preview, text=self.store.tag_name(self._drag_source), padding=8,
                      relief="solid", borderwidth=1).pack()
        self._drag_preview.geometry(f"+{pointer.x_root + 16}+{pointer.y_root + 12}")

    def drag_release(self, pointer):
        source = self._drag_source
        target = self.tags_tree.identify_row(pointer.y) or None
        inside = 0 <= pointer.x < self.tags_tree.winfo_width() and 0 <= pointer.y < self.tags_tree.winfo_height()
        valid = (self._drag_active and source is not None and inside
                 and target not in self.store.descendants(source))
        self.cancel_drag()
        if source and valid:
            self.move_tag(source, target)

    def move_tag(self, source, target):
        tag = self.store.tags[source]
        if target != tag.parent_id and self.try_action(lambda: self.store.save_tag(tag.name, target, source)):
            self.tag_saved(source)

    def _clear_drop_highlight(self):
        if self._expand_job is not None:
            self.after_cancel(self._expand_job)
            self._expand_job = None
        if self._drop_target and self.tags_tree.exists(self._drop_target):
            self.tags_tree.item(self._drop_target, tags=())

    def cancel_drag(self):
        self._clear_drop_highlight()
        if self._drag_preview is not None:
            self._drag_preview.destroy()
        self._drag_source, self._drag_preview, self._drop_target = None, None, None
        self._drag_active, self._drop_valid = False, False
        self.tags_tree.configure(cursor="")

    def set_day(self):
        requested = self.date_picker.get().strip()
        if not self.commit_cell():
            self.date_picker.value.set(self.day.isoformat())
            return
        try:
            self.day = datetime.strptime(requested, "%Y-%m-%d").date()
        except ValueError:
            messagebox.showerror("日期格式", "请使用 YYYY-MM-DD，例如 2026-10-07。", parent=self)
            self.date_picker.value.set(self.day.isoformat())
            return
        self.drafts.clear()
        self.undefined_names.clear()
        self.refresh()

    def shift_day(self, delta):
        if not self.commit_cell():
            return
        try:
            self.day += timedelta(days=delta)
            self.drafts.clear()
            self.undefined_names.clear()
            self.refresh()
        except OverflowError:
            messagebox.showerror("日期范围", "已经到达日期范围边界。", parent=self)

    def go_today(self):
        if not self.commit_cell():
            return
        self.day = date.today()
        self.drafts.clear()
        self.undefined_names.clear()
        self.refresh()

    def add_event(self, start=None):
        if not self.commit_cell():
            return "break"
        left, right = default_event_interval(self.day, start)
        event = Event(uuid4().hex, "", None, left, right)
        self.drafts[event.id] = event
        event_id = event.id
        self.refresh()
        self.select_event(event_id)
        self.update_idletasks()
        self.edit_cell(event_id, "title")
        return "break"

    def discard_draft(self, event_id):
        self.cancel_cell()
        self.drafts.pop(event_id, None)
        self.refresh()

    def select_event(self, event_id):
        if event_id is None:
            return self.clear_event_selection()
        if not self.commit_cell():
            return False
        if self.events_tree.exists(event_id):
            self.events_tree.selection_set(event_id)
            self.events_tree.focus(event_id)
            self.events_tree.see(event_id)
            self.draw_timeline()
            return True
        return False

    def edit_event(self, event_id):
        if self.commit_cell() and self.grab_current() is None and event_id in self.store.events:
            EventDialog(self, self.store, self.refresh, self.day, self.store.events[event_id])

    def rename_event(self, event_id):
        if self.select_event(event_id):
            self.update_idletasks()
            self.edit_cell(event_id, "title", self.timeline.canvas)

    def update_event_time(self, event):
        if event.id in self.drafts:
            self.drafts[event.id] = event
            saved = True
        else:
            saved = self.try_action(lambda: self.store.save_event(event))
        self.refresh()
        return saved

    def event_double_click(self, pointer):
        event_id = self.events_tree.identify_row(pointer.y)
        if event_id:
            return self.event_press(pointer)
        if self.events_tree.identify_region(pointer.x, pointer.y) == "nothing":
            self.add_event()
        return "break"

    def edit_cell(self, event_id, column, parent=None):
        if not self.commit_cell():
            return
        if column not in ("title", "start", "end", "tag") or (event := self.get_event(event_id)) is None:
            return
        if event_id in self.undefined and column not in ("title", "tag"):
            return
        parent = self.events_tree if parent is None else parent
        bounds = self.timeline.title_bounds(event_id) if parent is self.timeline.canvas else self.events_tree.bbox(event_id, column)
        if not bounds:
            return
        on_cancel = self.cancel_cell
        if event_id in self.drafts and column == "title":
            on_cancel = lambda: self.discard_draft(event_id)
        self.cell_editor = CellEditor(parent, self.store, event, column, self.save_cell, on_cancel,
                                      self.next_cell)
        self.cell_editor.show(bounds)

    def save_cell(self, editor, value):
        current = self.get_event(editor.event_id)
        field = "tag_id" if editor.column == "tag" else editor.column
        if field in ("start", "end") and (original := getattr(current, field)) is not None:
            if value == original.replace(second=0, microsecond=0):
                value = original
        event = replace(current, **{field: value})
        if event.id in self.undefined:
            if event.tag_id is not None:
                event = replace(event, id=uuid4().hex, title=event.title or "未定义")
                if not self.try_action(lambda: self.store.save_event(event)):
                    return False
                self.undefined_names.pop(current.id, None)
            elif field == "title":
                self.undefined_names[event.id] = value or "未定义"
        elif event.id in self.drafts:
            if not event.title:
                if not self.try_action(lambda: self.store.validate_event(replace(event, title="新事件"))):
                    return False
                self.drafts[event.id] = event
            else:
                if not self.try_action(lambda: self.store.save_event(event)):
                    return False
                del self.drafts[event.id]
        elif event != current and not self.try_action(lambda: self.store.save_event(event)):
            return False
        self.cancel_cell()
        self.refresh()
        self.select_event(event.id)
        return True

    def next_cell(self, editor, backwards=False):
        event_id, column = editor.event_id, editor.column
        columns = ("title", "start", "end", "tag")
        if editor.commit():
            index = columns.index(column) + (-1 if backwards else 1)
            if 0 <= index < len(columns):
                self.edit_cell(event_id, columns[index])
        return "break"

    def commit_cell(self):
        return self.cell_editor is None or self.cell_editor.commit()

    def cancel_cell(self):
        editor, self.cell_editor = self.cell_editor, None
        if editor is not None:
            parent = editor.master
            editor.destroy()
            parent.focus_set()

    def position_cell(self):
        if self.cell_editor is not None:
            if self.cell_editor.master is self.timeline.canvas:
                bounds = self.timeline.title_bounds(self.cell_editor.event_id)
            else:
                bounds = self.events_tree.bbox(self.cell_editor.event_id, self.cell_editor.column)
            if bounds:
                x, y, width, height = bounds
                self.cell_editor.place_configure(x=x, y=y, width=width, height=height)

    def scroll_events(self, axis, *args):
        if self.commit_cell():
            getattr(self.events_tree, axis + "view")(*args)

    def event_context_menu(self, pointer):
        event_id = self.events_tree.identify_row(pointer.y)
        if not self.commit_cell():
            return
        if not event_id or not self.events_tree.exists(event_id):
            return
        if event_id not in self.events_tree.selection():
            self.events_tree.selection_set(event_id)
        self.events_tree.focus(event_id)
        if hasattr(self, "event_menu"):
            self.event_menu.destroy()
        self.event_menu = menu = tk.Menu(self, tearoff=False, bg="white", fg="#111111",
                                         activebackground="#e5e7eb", activeforeground="#111111")
        if event_id in self.undefined:
            menu.add_command(label="设置标签", command=lambda: self.edit_cell(event_id, "tag"))
        else:
            menu.add_command(label="删除", command=self.delete_events)
            if event_id in self.store.events:
                menu.add_command(label="编辑详情", command=lambda: self.edit_event(event_id))
        try:
            menu.tk_popup(pointer.x_root, pointer.y_root)
        finally:
            menu.grab_release()

    def timeline_context_menu(self, pointer, event_id, start):
        if not self.commit_cell():
            return "break"
        self.timeline.cancel_drag()
        if event_id and self.events_tree.exists(event_id):
            if event_id not in self.events_tree.selection():
                self.select_event(event_id)
            self.events_tree.focus(event_id)
        if hasattr(self, "timeline_menu"):
            self.timeline_menu.destroy()
        self.timeline_menu = menu = tk.Menu(self, tearoff=False, bg="white", fg="#111111",
                                            activebackground="#e5e7eb", activeforeground="#111111")
        menu.add_command(label="在此新增事件", command=lambda: self.add_event(start))
        if event_id in self.undefined:
            menu.add_command(label="设置标签", command=lambda: self.edit_cell(event_id, "tag"))
        elif event_id:
            menu.add_separator()
            menu.add_command(label="删除", command=self.delete_events)
            if event_id in self.store.events:
                menu.add_command(label="编辑详情", command=lambda: self.edit_event(event_id))
        try:
            menu.tk_popup(pointer.x_root, pointer.y_root)
        finally:
            menu.grab_release()
        return "break"

    def delete_events(self):
        selected = list(self.events_tree.selection())
        self.cancel_cell()
        saved = [event_id for event_id in selected if event_id in self.store.events]
        if saved and not self.try_action(lambda: self.store.delete_events(saved)):
            return
        for event_id in selected:
            self.drafts.pop(event_id, None)
        self.refresh()

    def undo(self):
        """Ctrl+Z: revert the last persisted event change in both panels."""
        if not self.commit_cell():
            return
        self.history.undo(self.restore_history)

    def redo(self):
        """Ctrl+Y / Ctrl+Shift+Z: reapply the change undone last."""
        if not self.commit_cell():
            return
        self.history.redo(self.restore_history)

    def restore_history(self, events):
        if self.try_action(lambda: self.store.restore_events(events)):
            self.refresh()
            return True
        return False

    def try_action(self, action):
        try:
            action()
            return True
        except (ValueError, OSError) as error:
            messagebox.showerror("操作未完成", str(error), parent=self)
            return False

    def close(self):
        self.cancel_cell()
        self.cancel_drag()
        self.timeline.cancel_drag()
        self.timeline._hide_tooltip()
        self.destroy()
