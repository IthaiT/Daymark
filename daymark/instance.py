"""Prevent two app instances from overwriting the same local data files."""

import os
from pathlib import Path


class InstanceLock:
    def __init__(self, directory: Path):
        directory.mkdir(parents=True, exist_ok=True)
        self.stream = (directory / ".daymark.lock").open("a+b")
        if self.stream.tell() == 0:
            self.stream.write(b"0")
            self.stream.flush()
        self.stream.seek(0)
        try:
            if os.name == "nt":
                import msvcrt
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            self.stream.close()
            raise ValueError("这个数据目录已由另一个 Daymark 窗口打开，请切换到已有窗口。") from error

    def close(self):
        if not self.stream.closed:
            self.stream.close()
