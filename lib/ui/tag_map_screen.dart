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
  String? _themeKey;
  static const _allRootValue = '__all__';

  @override
  void dispose() {
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

  void _setRoot(String? id) {
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

  Future<void> _save() async {
    if (!_mapReady || widget.controller.saving) return;
    try {
      await widget.controller.save();
      _reloadView(fit: false);
      _showMessage('标签已保存');
    } catch (error) {
      _showError(error);
    }
  }

  Future<String?> _askName({
    required String title,
    String initial = '',
    String? detail,
    String? Function(String)? validate,
  }) => showDialog<String>(
    context: context,
    builder: (_) => _TagNameDialog(
      title: title,
      initial: initial,
      detail: detail,
      validate: validate,
    ),
  );

  Future<void> _add() async {
    if (!_mapReady) return;
    final selected = widget.controller.node(_selection.id);
    final parentId = selected?.id ?? widget.controller.rootId ?? tagTreeRootId;
    final parentName = selected?.name ?? widget.controller.rootNode?.name;
    final topLevel = parentId == tagTreeRootId;
    final name = await _askName(
      title: topLevel ? '新增一级标签' : '新增子标签',
      initial: '新标签',
      detail: parentName == null ? null : '添加到「$parentName」',
      validate: (value) =>
          widget.controller.validateName(topLevel ? null : parentId, value),
    );
    if (name == null) return;
    final view = _view.currentState;
    if (view != null) {
      await view.addChild(parentId, name);
    }
  }

  Future<void> _rename(String id, String name) async {
    if (!_mapReady) return;
    final node = widget.controller.node(id);
    if (node == null || id == tagTreeRootId) return;
    final updated = await _askName(
      title: '重命名标签',
      initial: name,
      validate: (value) => widget.controller.validateName(
        widget.controller.parentIdOf(id),
        value,
        ignoreId: id,
      ),
    );
    if (updated == null || updated == name) return;
    final view = _view.currentState;
    if (view != null) await view.rename(id, updated);
  }

  Future<void> _renameSelected() => _rename(_selection.id, _selection.name);

  Future<void> _deleteSelected() async {
    if (!_mapReady || _selection.id.isEmpty || _selection.id == tagTreeRootId) {
      return;
    }
    final blocker = widget.controller.deleteBlocker(_selection.id);
    if (blocker != null) {
      _showMessage(blocker);
      return;
    }
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除标签'),
            content: Text('将在保存后删除标签「${_selection.name}」。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('tag-map-delete-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    final removedId = _selection.id;
    final view = _view.currentState;
    if (view != null) await view.remove(removedId);
    if (mounted && _selection.id == removedId) {
      setState(() => _selection = const TagMapSelection.none());
    }
  }

  Future<void> _undo() async {
    if (!_canUndo) return;
    await _view.currentState?.undo();
  }

  Future<void> _redo() async {
    if (!_canRedo) return;
    await _view.currentState?.redo();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final dirty = widget.controller.dirty;
      return CallbackShortcuts(
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
              unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.f2): () =>
              unawaited(_renameSelected()),
          const SingleActivator(LogicalKeyboardKey.delete): () =>
              unawaited(_deleteSelected()),
          // Tab must not create a node or land on "add" by accident.
          const SingleActivator(LogicalKeyboardKey.tab): () =>
              _focus.requestFocus(),
          const SingleActivator(LogicalKeyboardKey.tab, shift: true): () =>
              _focus.requestFocus(),
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Padding(
            padding: WorkspaceStyle.padding,
            child: Column(
              children: [
                _header(context, dirty),
                const SizedBox(height: 14),
                Expanded(
                  child: WorkspacePanel(
                    child: Listener(
                      onPointerDown: (_) => _focus.requestFocus(),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: TagMapView(
                              key: _view,
                              onReady: _viewReady,
                              onChange: _changed,
                              onRename: (id, name) =>
                                  unawaited(_rename(id, name)),
                              onError: _showError,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 16,
                            child: Center(child: _toolbar(context)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _header(BuildContext context, bool dirty) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text('标签导图', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 10),
                  Flexible(child: _rootPicker(context)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '拖动节点调整层级 · 双击节点重命名',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dirty ? scheme.tertiary : scheme.outline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              dirty ? '未保存的修改' : '已保存',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(width: 10),
        IconButton(
          key: const ValueKey('tag-map-undo'),
          tooltip: '撤销 (Ctrl+Z)',
          onPressed: _canUndo ? () => unawaited(_undo()) : null,
          icon: const Icon(Icons.undo, size: 20),
        ),
        IconButton(
          key: const ValueKey('tag-map-redo'),
          tooltip: '恢复 (Ctrl+Y)',
          onPressed: _canRedo ? () => unawaited(_redo()) : null,
          icon: const Icon(Icons.redo, size: 20),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('tag-map-save'),
          onPressed: _mapReady && dirty && !widget.controller.saving
              ? () => unawaited(_save())
              : null,
          icon: widget.controller.saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(widget.controller.saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }

  Widget _rootPicker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = widget.controller.isAllView
        ? '全部标签'
        : widget.controller.rootNode?.name ?? '选择根标签';
    return PopupMenuButton<String>(
      key: const ValueKey('tag-map-root'),
      tooltip: '选择根标签',
      onSelected: (value) => _setRoot(value == _allRootValue ? null : value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: _allRootValue, child: Text('全部标签')),
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

  Widget _toolbar(BuildContext context) => Material(
    elevation: 2,
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    surfaceTintColor: Colors.transparent,
    borderRadius: BorderRadius.circular(24),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tool(Icons.add, '新增子标签', _mapReady ? _add : null),
          _tool(
            Icons.edit_outlined,
            '重命名',
            !_mapReady ||
                    _selection.id.isEmpty ||
                    _selection.id == tagTreeRootId
                ? null
                : _renameSelected,
          ),
          _tool(
            Icons.delete_outline,
            '删除',
            !_mapReady ||
                    _selection.id.isEmpty ||
                    _selection.id == tagTreeRootId ||
                    _selection.id == widget.controller.rootId
                ? null
                : _deleteSelected,
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          _tool(
            Icons.zoom_out,
            '缩小',
            _mapReady
                ? () async {
                    await _view.currentState?.zoomOut();
                  }
                : null,
          ),
          _tool(
            Icons.fit_screen_outlined,
            '适应画布',
            _mapReady
                ? () async {
                    await _view.currentState?.fit();
                  }
                : null,
          ),
          _tool(
            Icons.zoom_in,
            '放大',
            _mapReady
                ? () async {
                    await _view.currentState?.zoomIn();
                  }
                : null,
          ),
        ],
      ),
    ),
  );

  Widget _tool(
    IconData icon,
    String tooltip,
    Future<void> Function()? action,
  ) => IconButton(
    tooltip: tooltip,
    onPressed: action == null ? null : () => unawaited(action()),
    icon: Icon(icon, size: 19),
    style: IconButton.styleFrom(fixedSize: const Size(36, 36)),
  );
}

class _TagNameDialog extends StatefulWidget {
  const _TagNameDialog({
    required this.title,
    required this.initial,
    required this.validate,
    this.detail,
  });
  final String title;
  final String initial;
  final String? detail;
  final String? Function(String)? validate;
  @override
  State<_TagNameDialog> createState() => _TagNameDialogState();
}

class _TagNameDialogState extends State<_TagNameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initial.length,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _name.text.trim();
    final error = widget.validate?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.detail != null) ...[
            Text(
              widget.detail!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('tag-name-input'),
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(labelText: '标签名称'),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        key: const ValueKey('tag-name-confirm'),
        onPressed: _submit,
        child: const Text('确定'),
      ),
    ],
  );
}
