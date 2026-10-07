"""The Daymark desktop application."""

import tkinter as tk
from datetime import date, datetime, timedelta
from tkinter import messagebox, ttk

from .dialogs import EventDialog, ReassignDialog, TagChoice, TagDialog
from .model import duration_text
from .timeline import Timeline, tag_color

BG, INK, MUTED, GREEN = "#f4f2ed", "#243b33", "#78847c", "#356f64"
FONT = "Microsoft YaHei UI"


class App(tk.Tk):
    def __init__(self, store):
        super().__init__()
        self.store = store
        self.title("Daymark · 日迹")
        self.configure(bg=BG)
        width, height = min(1360, self.winfo_screenwidth() - 80), min(900, self.winfo_screenheight() - 64)
        xpos = max(0, (self.winfo_screenwidth() - width) // 2)
        ypos = max(0, (self.winfo_screenheight() - height - 40) // 2)
        self.geometry(f"{width}x{height}+{xpos}+{ypos}")
        self.minsize(1100, 740)
        self.day = date.today()
        self.filter_tag = None
        self.date_text = tk.StringVar(value=self.day.isoformat())
        self.status = tk.StringVar(value="所有记录都留在这台电脑。")
        self.timer_text = tk.StringVar()
        self.summary_groups = {}
        self._tick_count = 0
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
        self.protocol("WM_DELETE_WINDOW", self.close)
        self._tick_job = self.after(1000, self.tick)

    def _configure_styles(self):
        style = ttk.Style(self)
        style.theme_use("clam")
        style.configure(".", font=(FONT, 10), background=BG, foreground=INK)
        style.configure("TFrame", background=BG)
        style.configure("TLabel", background=BG, foreground=INK)
        style.configure("Muted.TLabel", foreground=MUTED, font=(FONT, 9))
        style.configure("Title.TLabel", font=(FONT, 20, "bold"))
        style.configure("Heading.TLabel", font=(FONT, 12, "bold"))
        style.configure("Sidebar.TFrame", background="#e9e7de")
        style.configure("Sidebar.TLabel", background="#e9e7de")
        style.configure("Logo.TLabel", background="#e9e7de", font=(FONT, 23, "bold"), foreground=GREEN)
        style.configure("SideMuted.TLabel", background="#e9e7de", foreground=MUTED, font=(FONT, 9))
        style.configure("Card.TFrame", background="white")
        style.configure("Card.TLabel", background="white")
        style.configure("CardMuted.TLabel", background="white", foreground=MUTED, font=(FONT, 9))
        style.configure("Metric.TLabel", background="white", font=(FONT, 19, "bold"), foreground=GREEN)
        style.configure("TButton", padding=(12, 7), background="#e8ebe6", borderwidth=0)
        style.map("TButton", background=[("active", "#dce3dc")])
        style.configure("Accent.TButton", background=GREEN, foreground="white")
        style.map("Accent.TButton", background=[("disabled", "#a9bcb5"), ("active", "#28584f")],
                  foreground=[("disabled", "#edf0ee")])
        style.configure("Danger.TButton", background="#f0e2da", foreground="#9d4f3c")
        style.configure("TEntry", padding=7, fieldbackground="white", bordercolor="#d8ddd7")
        style.configure("TCombobox", padding=6, fieldbackground="white", bordercolor="#d8ddd7")
        style.map("TCombobox", fieldbackground=[("readonly", "white")])
        style.configure("Treeview", background="white", fieldbackground="white", foreground=INK,
                        rowheight=28, borderwidth=0)
        style.map("Treeview", background=[("selected", "#dce9e2")], foreground=[("selected", INK)])
        style.configure("Treeview.Heading", background="#edf0eb", font=(FONT, 9), padding=(6, 8))
        style.configure("Tags.Treeview", background="#e9e7de", fieldbackground="#e9e7de", rowheight=34)
        style.configure("Tooltip.TLabel", background="#243b33", foreground="white", font=(FONT, 10))

    def _build_sidebar(self):
        sidebar = ttk.Frame(self, style="Sidebar.TFrame", padding=(20, 28))
        sidebar.grid(row=0, column=0, sticky="nsew")
        sidebar.configure(width=250)
        sidebar.grid_propagate(False)
        sidebar.columnconfigure(0, weight=1)
        sidebar.rowconfigure(4, weight=1)
        ttk.Label(sidebar, text="Daymark", style="Logo.TLabel").grid(row=0, column=0, sticky="w")
        ttk.Label(sidebar, text="日迹 / 时间有迹可循", style="SideMuted.TLabel").grid(row=1, column=0, sticky="w", pady=(4, 32))
        ttk.Label(sidebar, text="我的标签", style="Sidebar.TLabel", font=(FONT, 12, "bold")).grid(row=2, column=0, sticky="w")
        ttk.Button(sidebar, text="显示全部事件", command=self.clear_filter).grid(row=3, column=0, sticky="ew", pady=(12, 10))
        tree_box = ttk.Frame(sidebar, style="Sidebar.TFrame")
        tree_box.grid(row=4, column=0, sticky="nsew")
        tree_box.columnconfigure(0, weight=1)
        tree_box.rowconfigure(0, weight=1)
        self.tags_tree = ttk.Treeview(tree_box, show="tree", selectmode="browse", style="Tags.Treeview")
        self.tags_tree.column("#0", width=180, minwidth=80)
        self.tags_tree.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(tree_box, command=self.tags_tree.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.tags_tree.configure(yscrollcommand=scroll.set)
        self.tags_tree.bind("<<TreeviewSelect>>", self.tag_selected)
        self.tags_tree.bind("<Double-1>", lambda _: self.edit_tag())
        ttk.Label(sidebar, text="选择标签可筛选整个分支的事件。", style="SideMuted.TLabel", wraplength=205).grid(
            row=5, column=0, sticky="w", pady=(12, 14))
        ttk.Button(sidebar, text="＋ 新增标签", command=self.add_tag).grid(row=6, column=0, sticky="ew", pady=(0, 8))
        ttk.Button(sidebar, text="修改 / 移动标签", command=self.edit_tag).grid(row=7, column=0, sticky="ew", pady=(0, 8))
        ttk.Button(sidebar, text="删除标签", command=self.delete_tag).grid(row=8, column=0, sticky="ew")
        ttk.Label(sidebar, text="慢慢记录，慢慢看清。", style="SideMuted.TLabel").grid(row=9, column=0, sticky="w", pady=(28, 0))

    def _build_main(self):
        main = ttk.Frame(self, padding=(24, 16, 24, 10))
        main.grid(row=0, column=1, sticky="nsew")
        main.columnconfigure(0, weight=1)
        main.rowconfigure(5, weight=1)
        header = ttk.Frame(main)
        header.grid(row=0, column=0, sticky="ew", pady=(0, 10))
        ttk.Label(header, text="今天，时间去了哪里？", style="Title.TLabel").pack(side="left")
        ttk.Button(header, text="＋ 补录事件", command=self.add_event, style="Accent.TButton").pack(side="right")
        date_bar = ttk.Frame(main)
        date_bar.grid(row=1, column=0, sticky="ew", pady=(0, 12))
        ttk.Button(date_bar, text="‹", width=3, command=lambda: self.shift_day(-1)).pack(side="left")
        self.date_entry = ttk.Entry(date_bar, textvariable=self.date_text, width=13)
        self.date_entry.pack(side="left", padx=8)
        self.date_entry.bind("<Return>", lambda _: self.set_day())
        ttk.Button(date_bar, text="查看", command=self.set_day).pack(side="left")
        ttk.Button(date_bar, text="›", width=3, command=lambda: self.shift_day(1)).pack(side="left", padx=8)
        ttk.Button(date_bar, text="今天", command=self.go_today).pack(side="left")
        self.weekday_label = ttk.Label(date_bar, style="Muted.TLabel")
        self.weekday_label.pack(side="left", padx=14)
        self.filter_label = ttk.Label(date_bar, style="Muted.TLabel")
        self.filter_label.pack(side="right")
        metrics = ttk.Frame(main)
        metrics.grid(row=2, column=0, sticky="ew", pady=(0, 12))
        self.metric_values = []
        for index, (title, note) in enumerate((
            ("实际覆盖", "重叠时间只计算一次"),
            ("事件累计", "重叠记录分别累加"),
            ("全天未记录", "24 小时减去实际覆盖"),
        )):
            metrics.columnconfigure(index, weight=1, uniform="metric")
            card = ttk.Frame(metrics, style="Card.TFrame", padding=(16, 9))
            card.grid(row=0, column=index, sticky="ew", padx=(0 if index == 0 else 10, 0))
            ttk.Label(card, text=title, style="CardMuted.TLabel").pack(anchor="w")
            value = ttk.Label(card, style="Metric.TLabel")
            value.pack(anchor="w", pady=(4, 2))
            ttk.Label(card, text=note, style="CardMuted.TLabel").pack(anchor="w")
            self.metric_values.append(value)
        quick = ttk.Frame(main, style="Card.TFrame", padding=12)
        quick.grid(row=3, column=0, sticky="ew", pady=(0, 12))
        quick.columnconfigure(0, weight=1)
        quick.columnconfigure(1, weight=1)
        ttk.Label(quick, text="正在做什么？", style="CardMuted.TLabel").grid(row=0, column=0, sticky="w", pady=(0, 6))
        ttk.Label(quick, text="归属标签", style="CardMuted.TLabel").grid(row=0, column=1, sticky="w", padx=10, pady=(0, 6))
        self.quick_title = ttk.Entry(quick, width=25)
        self.quick_title.grid(row=1, column=0, sticky="ew")
        self.quick_tag = TagChoice(quick, self.store, width=32)
        self.quick_tag.grid(row=1, column=1, sticky="ew", padx=10)
        self.start_button = ttk.Button(quick, text="▶ 开始计时", command=self.start_timer, style="Accent.TButton")
        self.start_button.grid(row=1, column=2)
        self.stop_button = ttk.Button(quick, text="■ 结束", command=self.stop_timer)
        self.stop_button.grid(row=1, column=3, padx=(8, 0))
        ttk.Label(quick, textvariable=self.timer_text, style="CardMuted.TLabel").grid(row=2, column=0, columnspan=4, sticky="w", pady=(8, 0))
        self.quick_title.bind("<Return>", lambda _: self.start_timer())
        timeline_box = ttk.Frame(main)
        timeline_box.grid(row=4, column=0, sticky="ew", pady=(0, 12))
        timeline_box.columnconfigure(0, weight=1)
        timeline_heading = ttk.Frame(timeline_box)
        timeline_heading.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        ttk.Label(timeline_heading, text="一天的轨迹", style="Heading.TLabel").pack(side="left")
        ttk.Label(timeline_heading, text="点击选中 · 双击编辑 · 滚轮横移", style="Muted.TLabel").pack(side="left", padx=16)
        self.zoom_choice = ttk.Combobox(timeline_heading, values=("全天", "2× 放大", "4× 放大"), state="readonly", width=10)
        self.zoom_choice.current(0)
        self.zoom_choice.pack(side="right")
        self.zoom_choice.bind("<<ComboboxSelected>>", self.zoom_changed)
        self.timeline = Timeline(timeline_box, self.store, self.select_event, self.edit_event)
        self.timeline.grid(row=1, column=0, sticky="ew")
        bottom = ttk.Frame(main)
        bottom.grid(row=5, column=0, sticky="nsew")
        bottom.columnconfigure(0, weight=1)
        bottom.rowconfigure(1, weight=1)
        toolbar = ttk.Frame(bottom)
        toolbar.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        self.events_heading = ttk.Label(toolbar, text="事件明细", style="Heading.TLabel")
        self.events_heading.pack(side="left")
        ttk.Button(toolbar, text="删除", command=self.delete_events, style="Danger.TButton").pack(side="right")
        ttk.Button(toolbar, text="更换标签", command=self.reassign_events).pack(side="right", padx=8)
        ttk.Button(toolbar, text="编辑", command=self.edit_selected_event).pack(side="right")
        table_box = ttk.Frame(bottom, style="Card.TFrame")
        table_box.grid(row=1, column=0, sticky="nsew")
        table_box.columnconfigure(0, weight=1)
        table_box.rowconfigure(0, weight=1)
        self.events_tree = ttk.Treeview(table_box, columns=("title", "start", "end", "tag", "duration"), show="headings", selectmode="extended", height=5)
        for column, label, width in (("title", "事件", 160), ("start", "开始", 88), ("end", "结束", 88),
                                     ("tag", "标签路径", 230), ("duration", "本日用时", 95)):
            self.events_tree.heading(column, text=label)
            self.events_tree.column(column, width=width, minwidth=width, stretch=column in ("title", "tag"))
        self.events_tree.grid(row=0, column=0, sticky="nsew")
        table_y = ttk.Scrollbar(table_box, command=self.events_tree.yview)
        table_y.grid(row=0, column=1, sticky="ns")
        table_x = ttk.Scrollbar(table_box, orient="horizontal", command=self.events_tree.xview)
        table_x.grid(row=1, column=0, sticky="ew")
        self.events_tree.configure(yscrollcommand=table_y.set, xscrollcommand=table_x.set)
        self.events_tree.bind("<Double-1>", lambda _: self.edit_selected_event())
        self.events_tree.bind("<<TreeviewSelect>>", lambda _: self.draw_timeline())
        distribution = ttk.Frame(bottom, style="Card.TFrame", padding=14, width=230)
        distribution.grid(row=0, column=1, rowspan=2, sticky="nsew", padx=(14, 0))
        distribution.grid_propagate(False)
        distribution.columnconfigure(0, weight=1)
        distribution.rowconfigure(2, weight=1)
        ttk.Label(distribution, text="用时分布", style="Card.TLabel", font=(FONT, 12, "bold")).grid(row=0, column=0, sticky="w")
        ttk.Label(distribution, text="全天 · 按一级标签累计", style="CardMuted.TLabel").grid(row=1, column=0, sticky="w", pady=(4, 12))
        self.summary_canvas = tk.Canvas(distribution, width=185, height=150, bg="white", highlightthickness=0)
        self.summary_canvas.grid(row=2, column=0, sticky="nsew")
        summary_scroll = ttk.Scrollbar(distribution, command=self.summary_canvas.yview)
        summary_scroll.grid(row=2, column=1, sticky="ns")
        self.summary_canvas.configure(yscrollcommand=summary_scroll.set)
        self.summary_canvas.bind("<Configure>", lambda _: self.draw_summary())
        self.summary_canvas.bind("<MouseWheel>", lambda event: self.summary_canvas.yview_scroll(-1 if event.delta > 0 else 1, "units"))
        ttk.Label(main, textvariable=self.status, style="Muted.TLabel").grid(row=6, column=0, sticky="w", pady=(10, 0))

    def visible_events(self, now=None):
        events = self.store.events_on(self.day, now)
        if self.filter_tag:
            branch = self.store.descendants(self.filter_tag)
            events = [event for event in events if event.tag_id in branch]
        return events

    def refresh_tags(self, selected=None):
        selected = selected or self.filter_tag
        initial = not self.tags_tree.get_children()
        expanded = {tag_id for tag_id in self.store.tags if self.tags_tree.exists(tag_id) and self.tags_tree.item(tag_id, "open")}
        self.tags_tree.delete(*self.tags_tree.get_children())
        for tag in self.store.ordered_tags():
            self.tags_tree.insert(tag.parent_id or "", "end", iid=tag.id, text=tag.name,
                                  open=initial or tag.id in expanded)
        if selected in self.store.tags:
            self.tags_tree.selection_set(selected)
            self.tags_tree.see(selected)
        current_tag = self.quick_tag.tag_id()
        self.quick_tag.ids = [None] + [tag.id for tag in self.store.ordered_tags()]
        self.quick_tag.configure(values=["未分类"] + [self.store.tag_path(tag_id) for tag_id in self.quick_tag.ids[1:]])
        self.quick_tag.current(self.quick_tag.ids.index(current_tag) if current_tag in self.quick_tag.ids else 0)

    def refresh(self):
        now = datetime.now()
        selected = self.events_tree.selection()
        events = self.visible_events(now)
        self.events_tree.delete(*self.events_tree.get_children())
        for event in events:
            start, end = event.interval_on(self.day, now)
            def clock(moment):
                return moment.strftime("%H:%M") if moment.date() == self.day else moment.strftime("%m-%d %H:%M")
            self.events_tree.insert("", "end", iid=event.id, values=(
                event.title, clock(event.start), clock(event.end) if event.end else "计时中",
                self.store.tag_path(event.tag_id), duration_text((end - start).total_seconds()),
            ))
        self.events_tree.selection_set([event_id for event_id in selected if self.events_tree.exists(event_id)])
        self.events_heading.configure(text=f"事件明细 · {len(events)}")
        self.date_text.set(self.day.isoformat())
        self.weekday_label.configure(text="星期" + "一二三四五六日"[self.day.weekday()])
        path = self.store.tag_path(self.filter_tag) if self.filter_tag else "全部标签"
        self.filter_label.configure(text=path if len(path) <= 24 else path[:23] + "…")
        total, covered, self.summary_groups = self.store.summary(self.day, now)
        for label, seconds in zip(self.metric_values, (covered, total, 86400 - covered)):
            label.configure(text=duration_text(seconds))
        self.status.set("存在重叠事件，时间轴已分行展示；实际覆盖时间已去重。" if total > covered else "所有记录都留在这台电脑。Ctrl+N 补录事件；Ctrl+←/→ 切换日期。")
        self.draw_timeline(now)
        self.draw_summary()
        self.update_timer_text(now)

    def draw_timeline(self, now=None):
        now = now or datetime.now()
        self.timeline.update_events(self.visible_events(now), self.day, now, self.events_tree.selection())

    def draw_summary(self):
        canvas = self.summary_canvas
        canvas.delete("all")
        width = max(140, canvas.winfo_width() - 4)
        total = sum(self.summary_groups.values())
        if not total:
            canvas.create_text(0, 15, anchor="nw", text="记录后，在这里看见分配。", fill=MUTED, font=(FONT, 9))
        for index, (tag_id, seconds) in enumerate(sorted(self.summary_groups.items(), key=lambda item: -item[1])):
            top = index * 62
            name = self.store.tags[tag_id].name if tag_id else "未分类"
            canvas.create_text(0, top + 3, anchor="nw", text=name[:10], fill=INK, font=(FONT, 10))
            canvas.create_text(width, top + 4, anchor="ne", text=f"{seconds / total:.0%}", fill=MUTED, font=(FONT, 9))
            canvas.create_rectangle(0, top + 26, width, top + 31, fill="#edf0eb", outline="")
            canvas.create_rectangle(0, top + 26, width * seconds / total, top + 31, fill=tag_color(self.store, tag_id), outline="")
            canvas.create_text(0, top + 37, anchor="nw", text=duration_text(seconds), fill=MUTED, font=(FONT, 9))
        canvas.configure(scrollregion=(0, 0, width, max(100, len(self.summary_groups) * 62)))

    def tag_selected(self, _=None):
        selected = self.tags_tree.selection()
        self.filter_tag = selected[0] if selected else None
        if self.filter_tag:
            self.quick_tag.current(self.quick_tag.ids.index(self.filter_tag))
        self.refresh()

    def clear_filter(self):
        self.tags_tree.selection_remove(self.tags_tree.selection())
        self.filter_tag = None
        self.refresh()

    def tag_saved(self, tag_id):
        self.filter_tag = tag_id
        self.refresh_tags(tag_id)
        self.refresh()

    def add_tag(self):
        TagDialog(self, self.store, self.tag_saved, parent_id=self.filter_tag)

    def edit_tag(self):
        if self.filter_tag:
            TagDialog(self, self.store, self.tag_saved, tag_id=self.filter_tag)
        else:
            messagebox.showinfo("修改标签", "请先在左侧选择一个标签。", parent=self)

    def delete_tag(self):
        if not self.filter_tag:
            messagebox.showinfo("删除标签", "请先在左侧选择一个标签。", parent=self)
            return
        tag_id = self.filter_tag
        if messagebox.askyesno("删除标签", f"删除「{self.store.tag_path(tag_id)}」？", parent=self):
            if self.try_action(lambda: self.store.delete_tag(tag_id)):
                self.filter_tag = None
                self.refresh_tags()
                self.refresh()

    def set_day(self):
        try:
            self.day = datetime.strptime(self.date_text.get().strip(), "%Y-%m-%d").date()
        except ValueError:
            messagebox.showerror("日期格式", "请使用 YYYY-MM-DD，例如 2026-10-07。", parent=self)
            self.date_text.set(self.day.isoformat())
            return
        self.refresh()

    def shift_day(self, delta):
        try:
            self.day += timedelta(days=delta)
            self.refresh()
        except OverflowError:
            messagebox.showerror("日期范围", "已经到达日期范围边界。", parent=self)

    def go_today(self):
        self.day = date.today()
        self.refresh()

    def zoom_changed(self, _=None):
        self.timeline.zoom = (1, 2, 4)[self.zoom_choice.current()]
        self.draw_timeline()

    def add_event(self):
        EventDialog(self, self.store, self.refresh, self.day, tag_id=self.filter_tag)

    def select_event(self, event_id):
        if self.events_tree.exists(event_id):
            self.events_tree.selection_set(event_id)
            self.events_tree.see(event_id)

    def edit_event(self, event_id):
        if self.grab_current() is None and event_id in self.store.events:
            EventDialog(self, self.store, self.refresh, self.day, self.store.events[event_id])

    def selected_events(self):
        selected = list(self.events_tree.selection())
        if not selected:
            messagebox.showinfo("选择事件", "请先选择事件；按 Ctrl 或 Shift 可多选。", parent=self)
        return selected

    def edit_selected_event(self):
        if selected := self.selected_events():
            self.edit_event(selected[0])

    def reassign_events(self):
        if selected := self.selected_events():
            ReassignDialog(self, self.store, selected, self.refresh)

    def delete_events(self):
        selected = self.selected_events()
        if selected and messagebox.askyesno("删除事件", f"删除所选的 {len(selected)} 个事件？", parent=self):
            if self.try_action(lambda: self.store.delete_events(selected)):
                self.refresh()

    def try_action(self, action):
        try:
            action()
            return True
        except (ValueError, OSError) as error:
            messagebox.showerror("操作未完成", str(error), parent=self)
            return False

    def start_timer(self):
        if self.try_action(lambda: self.store.start_timer(self.quick_title.get(), self.quick_tag.tag_id())):
            self.quick_title.delete(0, "end")
            self.day = date.today()
            self.clear_filter()

    def stop_timer(self):
        if self.try_action(self.store.stop_timer):
            self.refresh()

    def update_timer_text(self, now):
        running = self.store.running_event
        self.start_button.configure(state="disabled" if running else "normal")
        self.stop_button.configure(state="normal" if running else "disabled")
        if running:
            seconds = max(0, int((now - running.start).total_seconds()))
            hours, remainder = divmod(seconds, 3600)
            minutes, seconds = divmod(remainder, 60)
            title = running.title[:30] + ("…" if len(running.title) > 30 else "")
            self.timer_text.set(f"进行中 · {title} · {hours:02d}:{minutes:02d}:{seconds:02d}   关闭软件后仍会保留开始时间。")
        else:
            self.timer_text.set("为一件事按下开始；完成后结束计时。忘了记录，也可以稍后补录。")

    def tick(self):
        self.update_timer_text(datetime.now())
        self._tick_count += 1
        if self.store.running_event and self._tick_count % 10 == 0 and self.grab_current() is None:
            self.refresh()
        self._tick_job = self.after(1000, self.tick)

    def close(self):
        self.after_cancel(self._tick_job)
        self.timeline._hide_tooltip()
        self.destroy()
