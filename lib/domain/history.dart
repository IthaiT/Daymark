class History<T> {
  History({this.limit = 100});
  final int limit;
  final _undo = <(T, T)>[];
  final _redo = <(T, T)>[];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void clear() {
    _undo.clear();
    _redo.clear();
  }

  void record(T before, T after) {
    if (before == after) return;
    _undo.add((before, after));
    if (_undo.length > limit) _undo.removeRange(0, _undo.length - limit);
    _redo.clear();
  }

  Future<bool> undo(Future<void> Function(T) restore) async {
    if (_undo.isEmpty) return false;
    final change = _undo.last;
    await restore(change.$1);
    _undo.removeLast();
    _redo.add(change);
    return true;
  }

  Future<bool> redo(Future<void> Function(T) restore) async {
    if (_redo.isEmpty) return false;
    final change = _redo.last;
    await restore(change.$2);
    _redo.removeLast();
    _undo.add(change);
    return true;
  }
}
