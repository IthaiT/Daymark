import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/tag_map_controller.dart';
import '../domain/tag_tree.dart';
import 'dialogs.dart';
import 'tag_map_view.dart';
import 'workspace_style.dart';

/// Minimal tag mind map: the canvas, its essential actions and one save button.
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
  Timer? _autoSave;
  Future<bool>? _saving;
  String? _themeKey;
  static const _allRootValue = '__all__';

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
    final expected = widget.controller.view?.root.id;
    if (expected != null && tree.root.id != expected) return;
    widget.controller.applyViewTree(tree);
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _canUndo = canUndo;
      _canRedo = canRedo;
    });
    _scheduleSave();
  }

  /// Debounces writes so a drag or a burst of edits costs one atomic save.
  void _scheduleSave() {
    _autoSave?.cancel();
    _autoSave = Timer(const Duration(milliseconds: 500), () {
      unawaited(_save());
    });
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
        child: Column(
          children: [
            _header(context),
            const SizedBox(height: 10),
            Expanded(
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
                    onError: _showError,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text('标签导图', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 10),
        Flexible(child: _rootPicker(context)),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            '拖动调整层级 · Tab 新建 · 双击改名 · 右键进入子标签',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _rootPicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = widget.controller.isAllView
        ? tagTreeRootName
        : widget.controller.rootNode?.name ?? '选择根标签';
    return PopupMenuButton<String>(
      key: const ValueKey('tag-map-root'),
      tooltip: '选择根标签',
      onSelected: (value) =>
          unawaited(_setRoot(value == _allRootValue ? null : value)),
      itemBuilder: (context) => [
        const PopupMenuItem(value: _allRootValue, child: Text(tagTreeRootName)),
        const PopupMenuDivider(),
        for (final (node, depth) in widget.controller.rootChoices)
          PopupMenuItem(
            value: node.id,
            child: Padding(
              padding: EdgeInsets.only(left: depth * 14),
              child: Text(node.name, overflow: TextOverflow.ellipsis),
            ),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 200),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_tree_outlined,
                size: 15,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
