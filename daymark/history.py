"""Snapshot-based undo/redo history over the persisted event table."""


class History:
    """Reversible snapshots of the whole event table.

    Store mutators report each successful write with the table before and
    after the change. Undo swaps the current table for the previous snapshot
    and keeps the undone change available for redo.
    """

    def __init__(self, limit: int = 100):
        self.limit = limit
        self.suspended = False
        self._undo = []  # (before, after) snapshot pairs, oldest first.
        self._redo = []

    def record(self, before, after):
        """Remember one change; a new edit discards the redo branch."""
        if self.suspended or before == after:
            return
        self._undo.append((before, after))
        if len(self._undo) > self.limit:
            del self._undo[:len(self._undo) - self.limit]
        self._redo.clear()

    def undo(self, restore) -> bool:
        """Apply the previous snapshot through `restore`; False when empty or failed."""
        if not self._undo:
            return False
        before, after = self._undo[-1]
        if not self._apply(restore, before):
            return False
        self._undo.pop()
        self._redo.append((before, after))
        return True

    def redo(self, restore) -> bool:
        """Reapply the change undone last through `restore`."""
        if not self._redo:
            return False
        before, after = self._redo[-1]
        if not self._apply(restore, after):
            return False
        self._redo.pop()
        self._undo.append((before, after))
        return True

    def _apply(self, restore, snapshot) -> bool:
        # Restores must not be recorded as fresh changes.
        self.suspended = True
        try:
            return bool(restore(snapshot))
        finally:
            self.suspended = False

    def can_undo(self) -> bool:
        return bool(self._undo)

    def can_redo(self) -> bool:
        return bool(self._redo)
