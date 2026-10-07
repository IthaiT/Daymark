"""Run with `python -m daymark` from the project root."""

import argparse
import sys
import tkinter as tk
from pathlib import Path
from tkinter import messagebox

from .app import App
from .instance import InstanceLock
from .storage import Store


def main():
    parser = argparse.ArgumentParser(description="Daymark · 日迹：本地桌面时间记录")
    parser.add_argument("--data-dir", type=Path, default=Path(__file__).resolve().parents[1] / "data",
                        help="自定义数据目录，默认是项目下的 data 文件夹")
    args = parser.parse_args()
    lock = None
    try:
        lock = InstanceLock(args.data_dir.resolve())
        store = Store(args.data_dir)
        app = App(store)
        app.mainloop()
    except (ValueError, OSError) as error:
        print(f"Daymark: {error}", file=sys.stderr)
        root = tk.Tk()
        root.withdraw()
        messagebox.showerror("Daymark 无法启动", f"{error}\n\n原始数据文件已保留。", parent=root)
        root.destroy()
        return 1
    finally:
        if lock is not None:
            lock.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
