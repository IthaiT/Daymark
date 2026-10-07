"""Tree, calendar, and minute-precision time pickers using only Tkinter."""

import calendar
import tkinter as tk
from datetime import date, datetime
from tkinter import ttk

FONT = "Microsoft YaHei UI"


class Popup(tk.Toplevel):
    def __init__(self, owner):
        super().__init__(owner)
        self.withdraw()
        self.owner = owner
        self.previous_grab = owner.grab_current()
        self.previous_focus = owner.focus_get()
        self.overrideredirect(True)
        self.transient(owner.winfo_toplevel())
        self.configure(bg="#d4d4d4", padx=1, pady=1)
        self.body = ttk.Frame(self, padding=10)
        self.body.pack(fill="both", expand=True)
        self.bind("<Escape>", lambda _: self.close())
        self.bind("<Button-1>", self._outside_click)
        self.protocol("WM_DELETE_WINDOW", self.close)

    def show(self, focus):
        self.update_idletasks()
        width, height = self.winfo_reqwidth(), self.winfo_reqheight()
        x = min(self.owner.winfo_rootx(), self.winfo_screenwidth() - width)
        y = self.owner.winfo_rooty() + self.owner.winfo_height() + 2
        if y + height > self.winfo_screenheight():
            y = self.owner.winfo_rooty() - height - 2
        self.geometry(f"+{max(0, x)}+{max(0, y)}")
        self.deiconify()
        self.wait_visibility()
        self.lift()
        self.grab_set()
        # focus_set alone cannot reactivate an override-redirect window on Windows.
        focus.focus_force()

    def _outside_click(self, event):
        if not (self.winfo_rootx() <= event.x_root < self.winfo_rootx() + self.winfo_width()
                and self.winfo_rooty() <= event.y_root < self.winfo_rooty() + self.winfo_height()):
            self.close()
            return "break"

    def close(self):
        if not self.winfo_exists():
            return
        self.grab_release()
        self.destroy()
        if self.previous_grab is not None and self.previous_grab.winfo_exists():
            self.previous_grab.grab_set()
        target = self.previous_focus
        if target is None or not target.winfo_exists() or not target.winfo_viewable():
            target = self.owner.entry
        if target.winfo_exists() and target.winfo_viewable():
            target.focus_force()


class Picker(ttk.Frame):
    def __init__(self, parent, width, editable=True, symbol=None):
        super().__init__(parent)
        self.value = tk.StringVar()
        self.entry = ttk.Entry(self, textvariable=self.value, width=width,
                               state="normal" if editable else "readonly")
        self.entry.pack(side="left", fill="x", expand=True)
        if symbol is not None:
            self.button = ttk.Button(self, text=symbol, width=2, style="Icon.TButton", command=self.open_popup)
            self.button.pack(side="left", padx=(4, 0))
        # Open after mouse release, so the entry's press binding cannot steal
        # focus from the new popup or keep the pointer captured by the entry.
        self.entry.bind("<ButtonRelease-1>", lambda _: self.open_popup())
        self.entry.bind("<Alt-Down>", lambda _: self.open_popup())
        self.popup = None

    def get(self):
        return self.value.get()

    def _popup_open(self):
        return self.popup is not None and self.popup.winfo_exists()

    def open_popup(self):
        raise NotImplementedError


class TagPicker(Picker):
    def __init__(self, parent, store, selected=None, excluded=(), empty_label="未分类", width=44):
        super().__init__(parent, width, editable=False, symbol="▾")
        self.store, self.excluded, self.empty_label = store, set(excluded), empty_label
        self.selected_id = None
        self.set_tag(selected)

    def set_tag(self, tag_id):
        if tag_id is not None and (tag_id not in self.store.tags or tag_id in self.excluded):
            raise ValueError("所选标签不可用。")
        self.selected_id = tag_id
        self.value.set(self.store.tags[tag_id].name if tag_id else self.empty_label)

    def tag_id(self):
        return self.selected_id

    def open_popup(self):
        if self._popup_open():
            return
        self.popup = popup = Popup(self)
        box = ttk.Frame(popup.body)
        box.pack(fill="both", expand=True)
        popup.tree = ttk.Treeview(box, show="tree", selectmode="browse", height=10)
        popup.tree.column("#0", width=max(300, self.winfo_width() - 40), minwidth=160)
        popup.tree.pack(side="left", fill="both", expand=True)
        scroll = ttk.Scrollbar(box, command=popup.tree.yview)
        scroll.pack(side="right", fill="y")
        popup.tree.configure(yscrollcommand=scroll.set)
        popup.tree.insert("", "end", iid="none", text=self.empty_label)
        for tag in self.store.ordered_tags():
            if tag.id not in self.excluded:
                popup.tree.insert(f"tag:{tag.parent_id}" if tag.parent_id else "", "end",
                                  iid=f"tag:{tag.id}", text=tag.name, open=True)
        selected = f"tag:{self.selected_id}" if self.selected_id else "none"
        popup.tree.selection_set(selected)
        popup.tree.see(selected)
        popup.tree.bind("<ButtonRelease-1>", self._choose_clicked)
        popup.tree.bind("<Return>", lambda _: self.choose())
        ttk.Button(popup.body, text="选择", command=self.choose).pack(anchor="e", pady=(10, 0))
        popup.show(popup.tree)

    def _choose_clicked(self, pointer):
        tree = self.popup.tree
        row = tree.identify_row(pointer.y)
        if (row and tree.identify_region(pointer.x, pointer.y) == "tree"
                and "indicator" not in tree.identify_element(pointer.x, pointer.y)):
            tree.selection_set(row)
            self.choose()
            return "break"

    def choose(self):
        selected = self.popup.tree.selection()
        if selected:
            self.set_tag(selected[0][4:] if selected[0].startswith("tag:") else None)
            self.popup.close()


class DatePicker(Picker):
    def __init__(self, parent, value: date, on_change=None):
        super().__init__(parent, width=12)
        self.value.set(value.isoformat())
        self.year, self.month = value.year, value.month
        self.on_change = on_change

    def open_popup(self):
        if self._popup_open():
            return
        try:
            selected = datetime.strptime(self.get(), "%Y-%m-%d").date()
        except ValueError:
            selected = date.today()
        self.year, self.month = selected.year, selected.month
        self.popup = popup = Popup(self)
        header = ttk.Frame(popup.body)
        header.pack(fill="x", pady=(0, 8))
        ttk.Button(header, text="‹", width=2, style="Icon.TButton", command=lambda: self.shift_month(-1)).pack(side="left")
        popup.month_label = ttk.Label(header, anchor="center", width=16)
        popup.month_label.pack(side="left", expand=True)
        ttk.Button(header, text="›", width=2, style="Icon.TButton", command=lambda: self.shift_month(1)).pack(side="right")
        popup.days = ttk.Frame(popup.body)
        popup.days.pack(fill="both", expand=True)
        ttk.Button(popup.body, text="今天", command=lambda: self.choose(date.today())).pack(fill="x", pady=(8, 0))
        self.draw_month()
        popup.show(popup.month_label)

    def shift_month(self, amount):
        index = self.year * 12 + self.month - 1 + amount
        year, month = divmod(index, 12)
        if 1 <= year <= 9999:
            self.year, self.month = year, month + 1
            self.draw_month()

    def draw_month(self):
        popup = self.popup
        popup.month_label.configure(text=f"{self.year} 年 {self.month} 月")
        for child in popup.days.winfo_children():
            child.destroy()
        for column, weekday in enumerate("一二三四五六日"):
            ttk.Label(popup.days, text=weekday, anchor="center", width=4).grid(row=0, column=column, pady=(0, 6))
        popup.day_buttons = {}
        for row, week in enumerate(calendar.monthcalendar(self.year, self.month), start=1):
            for column, number in enumerate(week):
                if number:
                    day = date(self.year, self.month, number)
                    button = ttk.Button(popup.days, text=str(number), width=3,
                                        style="Selected.TButton" if day.isoformat() == self.get() else "TButton",
                                        command=lambda day=day: self.choose(day))
                    button.grid(row=row, column=column, padx=1, pady=1)
                    popup.day_buttons[number] = button

    def choose(self, value):
        self.value.set(value.isoformat())
        self.popup.close()
        if self.on_change is not None:
            self.on_change()


class TimePicker(Picker):
    def __init__(self, parent, value: datetime):
        super().__init__(parent, width=7)
        self.value.set(value.strftime("%H:%M"))

    def open_popup(self):
        if self._popup_open():
            return
        try:
            selected = datetime.strptime(self.get(), "%H:%M")
        except ValueError:
            selected = datetime.now()
        self.popup = popup = Popup(self)
        popup.hours = self._list(popup.body, "小时", range(24), selected.hour, 0)
        popup.minutes = self._list(popup.body, "分钟", range(60), selected.minute, 1)
        footer = ttk.Frame(popup.body)
        footer.grid(row=1, column=0, columnspan=2, sticky="ew", pady=(10, 0))
        ttk.Button(footer, text="现在", command=self.choose_now).pack(side="left")
        ttk.Button(footer, text="确定", command=self.choose).pack(side="right", padx=(12, 0))
        popup.bind("<Return>", lambda _: self.choose())
        popup.show(popup.hours)

    @staticmethod
    def _list(parent, title, values, selected, column):
        frame = ttk.Frame(parent)
        frame.grid(row=0, column=column, padx=5)
        ttk.Label(frame, text=title).pack(pady=(0, 6))
        box = ttk.Frame(frame)
        box.pack()
        items = tk.Listbox(box, width=5, height=8, font=(FONT, 11), bg="white", fg="#111111",
                           selectbackground="#e5e7eb", selectforeground="#111111", exportselection=False,
                           relief="flat", highlightthickness=0, activestyle="none")
        items.pack(side="left")
        scrollbar = ttk.Scrollbar(box, command=items.yview)
        scrollbar.pack(side="right", fill="y")
        items.configure(yscrollcommand=scrollbar.set)
        for value in values:
            items.insert("end", f"{value:02d}")
        items.selection_set(selected)
        items.see(selected)
        return items

    def choose(self):
        hours, minutes = self.popup.hours.curselection(), self.popup.minutes.curselection()
        if hours and minutes:
            self.value.set(f"{hours[0]:02d}:{minutes[0]:02d}")
            self.popup.close()

    def choose_now(self):
        self.value.set(datetime.now().strftime("%H:%M"))
        self.popup.close()
