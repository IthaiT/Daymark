"""Snapshot-based undo/redo history over the editor state."""


class History:
    """Reversible snapshots of the complete undoable editor state.

    The application captures its state (persisted events, in-progress drafts
    and pending gap titles) before each user action and records the pair
    after the action completes. Undo swaps the current state for the previous
    snapshot and keeps the undone change available for redo.
    """

    def __init__(self, limit: int = 100):
        self.limit = limit
        self._undo = []  # (before, after) snapshot pairs, oldest first.
        self._redo = []

    def record(self, before, after):
        """Remember one change; a new edit discards the redo branch."""
        if before == after:
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
        return bool(restore(snapshot))

    def can_undo(self) -> bool:
        return bool(self._undo)

    def can_redo(self) -> bool:
        return bool(self._redo)
