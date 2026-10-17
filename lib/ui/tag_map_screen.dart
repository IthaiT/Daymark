import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tag_map_controller.dart';
import '../domain/tag_tree.dart';
import 'dialogs.dart';
import 'tag_map_view.dart';
import 'workspace_style.dart';

/// Minimal tag mind map: a full-height canvas that saves changes automatically.
class TagMapScreen extends StatefulWidget {
  const TagMapScreen({super.key, required this.controller});
  final TagMapController controller;
  @override
  State<TagMapScreen> createState() => TagMapScreenState();
}

class TagMapScreenState extends State<TagMapScreen> {
  final _focus = FocusNode(debugLabel: 'tag-map');
  final _view = GlobalKey<TagMapViewState>();
  TagMapSelection _selection = const TagMapSelection.none();
  bool _canUndo = false;
  bool _canRedo = false;
  bool _mapReady = false;
  bool _editing = false;
  Timer? _autoSave;
  Future<bool>? _saving;
  String? _themeKey;

  @override
  void dispose() {
    _autoSave?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final key = _colors().values.join('|');
    final previous = _themeKey;
    _themeKey = key;
    if (previous != null && previous != key && _mapReady) {
      final view = _view.currentState;
      if (view != null) unawaited(view.applyColors(_colors()));
    }
  }

  void focus() => _focus.requestFocus();

  /// Re-reads tags edited in the journal sidebar while this page stayed alive.
  void synchronize() {
    if (!widget.controller.syncFromStore()) return;
    _reloadView(fit: true);
  }

  void _reloadView({required bool fit}) {
    final tree = widget.controller.view;
    final view = _view.currentState;
    if (tree == null || view == null) return;
    unawaited(view.load(tree, _colors(), fit: fit));
    if (mounted) {
      setState(() {
        _selection = const TagMapSelection.none();
        _canUndo = false;
        _canRedo = false;
      });
    }
  }

  Future<void> _setRoot(String? id) async {
    await _view.currentState?.endEdit();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    if (!await _save()) return;
    if (!mounted) return;
    widget.controller.setRoot(id);
    _reloadView(fit: true);
  }

  Map<String, Object?> _colors() {
    final scheme = Theme.of(context).colorScheme;
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    String rgba(Color color, double opacity) {
      final value = color.toARGB32();
      return 'rgba(${(value >> 16) & 0xff}, ${(value >> 8) & 0xff}, '
          '${value & 0xff}, $opacity)';
    }

    return {
      'background': hex(scheme.surfaceContainerLowest),
      'surface': hex(scheme.surfaceContainerLowest),
      'accent': hex(scheme.primary),
      'onAccent': hex(scheme.onPrimary),
      'line': hex(scheme.outlineVariant),
      'text': hex(scheme.onSurface),
      'muted': hex(scheme.onSurfaceVariant),
      'border': hex(scheme.outlineVariant),
      'hover': rgba(scheme.primary, .16),
      'fontFamily':
          "'Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI', sans-serif",
    };
  }

  void _viewReady() {
    if (mounted) setState(() => _mapReady = true);
    _reloadView(fit: true);
  }

  void _changed(
    TagTree tree,
    TagMapSelection selection,
    bool canUndo,
    bool canRedo,
  ) {
    try {
      widget.controller.applyViewTree(tree);
    } on FormatException {
      // A change serialized before the root switch arrived late.
      return;
    }
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _canUndo = canUndo;
      _canRedo = canRedo;
    });
    if (widget.controller.dirty) _scheduleSave();
  }

  /// Debounces writes so a drag or a burst of edits costs one atomic save.
  /// An open inline editor is committed when it closes, never mid-typing.
  void _scheduleSave() {
    _autoSave?.cancel();
    if (_editing) return;
    _autoSave = Timer(const Duration(milliseconds: 500), () {
      unawaited(_save());
    });
  }

  void _editingChanged(bool editing) {
    _editing = editing;
    if (editing) {
      _autoSave?.cancel();
    } else {
      _scheduleSave();
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('tag-map-error'),
          content: Text(errorText(error)),
          behavior: SnackBarBehavior.floating,
          width: 480,
          showCloseIcon: true,
        ),
      );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          width: 480,
        ),
      );
  }

  /// Commits an inline rename before an explicit save or navigation.
  Future<bool> _saveNow() async {
    await _view.currentState?.endEdit();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return false;
    return _save();
  }

  Future<bool> _save() {
    _autoSave?.cancel();
    final pending = _saving;
    if (pending != null) return pending;
    final future = _write();
    _saving = future;
    return future
        .then((saved) {
          if (saved && widget.controller.dirty) _scheduleSave();
          return saved;
        })
        .whenComplete(() {
          if (identical(_saving, future)) _saving = null;
        });
  }

  Future<bool> _write() async {
    final controller = widget.controller;
    if (!_mapReady) return false;
    if (!controller.dirty) return true;
    try {
      await controller.save();
      await _view.currentState?.applyAssignedIds(controller.assignedIds);
      return true;
    } catch (error) {
      _showError(error);
      return false;
    }
  }

  Future<void> _beginEdit(String id) async {
    if (!_mapReady || id.isEmpty || id == tagTreeRootId) return;
    final view = _view.currentState;
    if (view != null) await view.beginEdit(id);
  }

  Future<void> _renameSelected() => _beginEdit(_selection.id);

  Future<void> _deleteSelected() async {
    if (!_mapReady || _selection.id.isEmpty || _selection.id == tagTreeRootId) {
      return;
    }
    await _view.currentState?.endEdit();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final blocker = widget.controller.deleteBlocker(_selection.id);
    if (blocker != null) {
      _showMessage(blocker);
      return;
    }
    final removedId = _selection.id;
    final view = _view.currentState;
    if (view != null) await view.remove(removedId);
    if (mounted && _selection.id == removedId) {
      setState(() => _selection = const TagMapSelection.none());
    }
  }

  Future<void> _undo() async {
    if (!_canUndo) return;
    await _view.currentState?.endEdit();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _view.currentState?.undo();
  }

  Future<void> _redo() async {
    if (!_canRedo) return;
    await _view.currentState?.endEdit();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await _view.currentState?.redo();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          unawaited(_undo()),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
          unawaited(_redo()),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): () =>
          unawaited(_redo()),
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          unawaited(_saveNow()),
      const SingleActivator(LogicalKeyboardKey.f2): () =>
          unawaited(_renameSelected()),
      const SingleActivator(LogicalKeyboardKey.delete): () =>
          unawaited(_deleteSelected()),
    },
    child: Focus(
      focusNode: _focus,
      autofocus: true,
      child: Padding(
        padding: WorkspaceStyle.padding,
        child: WorkspacePanel(
          child: Listener(
            onPointerDown: (_) => _focus.requestFocus(),
            child: TagMapView(
              key: _view,
              onReady: _viewReady,
              onChange: _changed,
              onSave: () => unawaited(_saveNow()),
              onDelete: () => unawaited(_deleteSelected()),
              onEnter: (id) => unawaited(_setRoot(id)),
              onEditing: _editingChanged,
              onError: _showError,
            ),
          ),
        ),
      ),
    ),
  );
}
