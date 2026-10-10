"""Validated JSON/CSV storage with atomic writes and stable tag identifiers."""

import csv
import json
import os
import tempfile
import time as clock
from dataclasses import asdict, replace
from datetime import date, datetime
from pathlib import Path
from uuid import uuid4

from .model import Event, Tag

CSV_FIELDS = ("id", "title", "tag_id", "start", "end", "notes")
DEFAULT_TAGS = (
    Tag("work", "主业"),
    Tag("embedded", "嵌入式", "work"),
    Tag("linux", "Linux", "embedded"),
    Tag("side", "副业"),
    Tag("agent", "Agent", "side"),
    Tag("learning", "学习", "agent"),
    Tag("course", "某一门课程", "learning"),
    Tag("explore", "探索"),
    Tag("life", "生活"),
    Tag("rest", "休息", "life"),
)


class DataError(ValueError):
    """Invalid persisted data: stop without overwriting the source files."""


class Store:
    def __init__(self, directory: Path):
        self.directory = Path(directory).resolve()
        self.tags_path = self.directory / "tags.json"
        self.events_path = self.directory / "events.csv"
        self.directory.mkdir(parents=True, exist_ok=True)
        self.tags = self._read_tags()
        self.events = self._read_events()
        # Optional observer invoked as (before, after) after each successful write.
        self.on_events_change = None
        # Read and validate all existing files before initializing missing ones.
        if not self.tags_path.exists():
            self._write_tags(self.tags)
        if not self.events_path.exists():
            self._write_events(self.events)

    def _atomic_write(self, path: Path, writer, encoding: str):
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(
                mode="w", encoding=encoding, newline="", dir=self.directory,
                prefix=path.name + ".", suffix=".tmp", delete=False,
            ) as stream:
                temporary = Path(stream.name)
                writer(stream)
                stream.flush()
                os.fsync(stream.fileno())
            # Windows virus scanners can briefly hold a newly written file open.
            for attempt in range(4):
                try:
                    os.replace(temporary, path)
                    break
                except PermissionError:
                    if attempt == 3:
                        raise
                    clock.sleep(0.05 * (attempt + 1))
        finally:
            if temporary is not None and temporary.exists():
                temporary.unlink()

    def _write_tags(self, tags: dict[str, Tag]):
        data = {"version": 1, "tags": [asdict(tag) for tag in tags.values()]}
        self._atomic_write(
            self.tags_path, lambda stream: json.dump(data, stream, ensure_ascii=False, indent=2), "utf-8"
        )

    def _write_events(self, events: dict[str, Event]):
        def write(stream):
            writer = csv.DictWriter(stream, fieldnames=CSV_FIELDS)
            writer.writeheader()
            for event in sorted(events.values(), key=lambda event: (event.start, event.id)):
                writer.writerow({
                    "id": event.id, "title": event.title, "tag_id": event.tag_id or "",
                    "start": event.start.isoformat(timespec="seconds"),
                    "end": event.end.isoformat(timespec="seconds") if event.end else "",
                    "notes": event.notes,
                })
        self._atomic_write(self.events_path, write, "utf-8-sig")

    @staticmethod
    def _validate_tags(tags: dict[str, Tag]):
        siblings = set()
        for tag in tags.values():
            if not isinstance(tag.id, str) or not tag.id:
                raise ValueError("标签 ID 必须是非空字符串。")
            if not isinstance(tag.name, str) or not tag.name.strip():
                raise ValueError("标签名称不能为空。")
            if tag.parent_id is not None and tag.parent_id not in tags:
                raise ValueError(f"标签「{tag.name}」的父标签不存在。")
            key = (tag.parent_id, tag.name.strip().casefold())
            if key in siblings:
                raise ValueError("同一个父标签下不能有重名标签。")
            siblings.add(key)
            visited = {tag.id}
            parent = tag.parent_id
            while parent:
                if parent in visited:
                    raise ValueError("不能把标签移动到自己或自己的子标签中。")
                visited.add(parent)
                parent = tags[parent].parent_id

    def _read_tags(self) -> dict[str, Tag]:
        if not self.tags_path.exists():
            return {tag.id: tag for tag in DEFAULT_TAGS}
        try:
            payload = json.loads(self.tags_path.read_text(encoding="utf-8-sig"))
            if payload["version"] != 1 or not isinstance(payload["tags"], list):
                raise ValueError("不支持的标签文件格式。")
            tags = {}
            for row in payload["tags"]:
                tag = Tag(**row)
                if tag.id in tags:
                    raise ValueError("标签 ID 重复。")
                tags[tag.id] = tag
            self._validate_tags(tags)
            return tags
        except (ValueError, TypeError, KeyError, RecursionError) as error:
            raise DataError(f"无法读取 {self.tags_path}：{error}") from error

    def validate_event(self, event: Event, allow_incomplete: bool = False):
        if not isinstance(event.id, str) or not event.id:
            raise ValueError("事件 ID 不能为空。")
        if not isinstance(event.title, str) or not event.title.strip():
            raise ValueError("请输入事件名称。")
        if event.tag_id is not None and event.tag_id not in self.tags:
            raise ValueError("所选标签不存在。")
        if not isinstance(event.notes, str):
            raise ValueError("备注必须是文本。")
        if event.end is None and not allow_incomplete:
            raise ValueError("请填写事件的结束时间。")
        if event.start.tzinfo is not None or (event.end and event.end.tzinfo is not None):
            raise ValueError("时间应为本机本地时间，不带时区后缀。")
        if event.end is not None and event.end <= event.start:
            raise ValueError("结束时间必须晚于开始时间；跨天事件请修改结束日期。")

    def _read_events(self) -> dict[str, Event]:
        if not self.events_path.exists():
            return {}
        try:
            events = {}
            with self.events_path.open(encoding="utf-8-sig", newline="") as stream:
                reader = csv.DictReader(stream)
                if reader.fieldnames != list(CSV_FIELDS):
                    raise ValueError("CSV 列名不匹配。")
                for line, row in enumerate(reader, start=2):
                    try:
                        if None in row or any(value is None for value in row.values()):
                            raise ValueError("CSV 列数不匹配。")
                        event = Event(
                            row["id"], row["title"], row["tag_id"] or None,
                            datetime.fromisoformat(row["start"]),
                            datetime.fromisoformat(row["end"]) if row["end"] else None,
                            row["notes"],
                        )
                        self.validate_event(event, allow_incomplete=True)
                        if event.id in events:
                            raise ValueError("事件 ID 重复。")
                        events[event.id] = event
                    except (ValueError, TypeError) as error:
                        raise ValueError(f"第 {line} 行：{error}") from error
            return events
        except (ValueError, TypeError, csv.Error) as error:
            raise DataError(f"无法读取 {self.events_path}：{error}") from error

    def tag_ancestors(self, tag_id: str | None) -> list[Tag]:
        ancestors = []
        while tag_id:
            tag = self.tags[tag_id]
            ancestors.append(tag)
            tag_id = tag.parent_id
        return list(reversed(ancestors))

    def tag_name(self, tag_id: str | None) -> str:
        return self.tags[tag_id].name if tag_id else "未分类"

    def tag_outline(self, tag_id: str | None) -> str:
        return "\n".join("  " * depth + tag.name for depth, tag in enumerate(self.tag_ancestors(tag_id))) or "未分类"

    def ordered_tags(self) -> list[Tag]:
        return sorted(self.tags.values(), key=lambda tag: tuple(item.name.casefold() for item in self.tag_ancestors(tag.id)))

    def descendants(self, tag_id: str) -> set[str]:
        result = {tag_id}
        pending = [tag_id]
        while pending:
            parent = pending.pop()
            children = [tag.id for tag in self.tags.values() if tag.parent_id == parent]
            result.update(children)
            pending.extend(children)
        return result

    def save_tag(self, name: str, parent_id: str | None, tag_id: str | None = None) -> Tag:
        if tag_id is not None and tag_id not in self.tags:
            raise ValueError("标签不存在。")
        tag = Tag(tag_id or uuid4().hex, name.strip(), parent_id)
        tags = {**self.tags, tag.id: tag}
        self._validate_tags(tags)
        self._write_tags(tags)
        self.tags = tags
        return tag

    def delete_tag(self, tag_id: str):
        if any(tag.parent_id == tag_id for tag in self.tags.values()):
            raise ValueError("此标签还有子标签，请先移动或删除子标签。")
        if any(event.tag_id == tag_id for event in self.events.values()):
            raise ValueError("此标签还有事件，请先给这些事件更换标签。")
        tags = dict(self.tags)
        del tags[tag_id]
        self._write_tags(tags)
        self.tags = tags

    def _notify_events_change(self, before: dict[str, Event]):
        if self.on_events_change is not None:
            self.on_events_change(before, self.events)

    def save_event(self, event: Event):
        self.validate_event(event)
        before = self.events
        events = {**self.events, event.id: event}
        self._write_events(events)
        self.events = events
        self._notify_events_change(before)

    def save_new_events(self, events: list[Event]):
        """Persist derived undefined gaps so unclassified time survives export."""
        pending = [event for event in events if event.id not in self.events]
        if not pending:
            return
        merged = dict(self.events)
        for event in pending:
            self.validate_event(event)
            merged[event.id] = event
        before = self.events
        self._write_events(merged)
        self.events = merged
        self._notify_events_change(before)

    def delete_events(self, event_ids: list[str]):
        before = self.events
        events = {key: value for key, value in self.events.items() if key not in event_ids}
        self._write_events(events)
        self.events = events
        self._notify_events_change(before)

    def reassign_events(self, event_ids: list[str], tag_id: str | None):
        if tag_id is not None and tag_id not in self.tags:
            raise ValueError("所选标签不存在。")
        before = self.events
        events = dict(self.events)
        for event_id in event_ids:
            events[event_id] = replace(events[event_id], tag_id=tag_id)
        self._write_events(events)
        self.events = events
        self._notify_events_change(before)

    def restore_events(self, events: dict[str, Event]) -> bool:
        """Undo/redo entry point: bulk-replace, unclassifying tags deleted since."""
        events = {event.id: (event if event.tag_id in self.tags else replace(event, tag_id=None))
                  for event in events.values()}
        for event in events.values():
            self.validate_event(event, allow_incomplete=True)
        before = self.events
        self._write_events(events)
        self.events = events
        self._notify_events_change(before)
        return True

    def events_on(self, day: date) -> list[Event]:
        return sorted(
            (event for event in self.events.values() if event.interval_on(day)
             or (event.end is None and event.start.date() == day)),
            key=lambda event: (event.start, event.id),
        )
