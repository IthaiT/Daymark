import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../data/store.dart';
import '../domain/appearance.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'tag_tree_tile.dart';
import 'workspace_style.dart';
import 'theme.dart';

class TagSidebar extends StatefulWidget {
  const TagSidebar({
    super.key,
    required this.journal,
    required this.beforeAction,
    required this.onError,
    this.tagColors = const {},
    this.onTagColorChanged,
    this.onTagStyleChanged,
    this.activityTagIds = const {},
    this.onActivityTagSelected,
  });
  final JournalController journal;
  final Future<bool> Function() beforeAction;
  final ValueChanged<Object> onError;
  final Map<String, TagColor> tagColors;
  final Future<void> Function(String id, TagColor? color)? onTagColorChanged;
  final TagStyleChanged? onTagStyleChanged;
  final Set<String> activityTagIds;
  final ValueChanged<String>? onActivityTagSelected;
  @override
  State<TagSidebar> createState() => _TagSidebarState();
}

class _TagSidebarState extends State<TagSidebar> {
  final _collapsed = <String>{};
  final _scroll = ScrollController();
  String? _selected;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _menu(Offset position, Tag? tag) async {
    if (!await widget.beforeAction() || !mounted) return;
    setState(() => _selected = tag?.id);
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'add',
          child: Text(tag == null ? '新增一级标签' : '新增子标签'),
        ),
        if (tag != null) ...[
          const PopupMenuItem(value: 'edit', child: Text('修改标签')),
          const PopupMenuItem(value: 'delete', child: Text('删除标签')),
        ],
      ],
    );
    if (!mounted) return;
    try {
      switch (choice) {
        case 'add':
          await showTagEditor(
            context,
            widget.journal,
            parentId: tag?.id,
            onColorChanged: widget.onTagColorChanged,
            onStyleChanged: widget.onTagStyleChanged,
          );
        case 'edit':
          await showTagEditor(
            context,
            widget.journal,
            id: tag!.id,
            color: widget.tagColors[tag.id],
            display: tagDisplayOverrides(context)[tag.id],
            onColorChanged: widget.onTagColorChanged,
            onStyleChanged: widget.onTagStyleChanged,
          );
        case 'delete':
          await widget.journal.deleteTag(tag!.id);
      }
    } catch (error) {
      widget.onError(error);
    }
  }

  bool _validDrop(String source, String? target) =>
      source != target &&
      (target == null ||
          !widget.journal.store.descendants(source).contains(target));

  bool _hasChildren(Store store, Tag tag) =>
      store.tags.values.any((child) => child.parentId == tag.id);

  void _toggle(String id) {
    if (!_collapsed.add(id)) _collapsed.remove(id);
  }

  Future<void> _move(String source, String? target) async {
    if (!await widget.beforeAction()) return;
    try {
      await widget.journal.moveTag(source, target);
    } catch (error) {
      widget.onError(error);
    }
  }

  Widget _target(Tag? tag, Widget child) => DragTarget<String>(
    onWillAcceptWithDetails: (details) => _validDrop(details.data, tag?.id),
    onAcceptWithDetails: (details) => _move(details.data, tag?.id),
    builder: (context, candidates, rejected) => ColoredBox(
      color: candidates.isEmpty
          ? Colors.transparent
          : Theme.of(context).colorScheme.secondaryContainer,
      child: child,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final store = widget.journal.store;
    final tags = store
        .orderedTags()
        .where(
          (tag) => !store
              .ancestors(tag.id)
              .take(store.ancestors(tag.id).length - 1)
              .any((parent) => _collapsed.contains(parent.id)),
        )
        .toList();
    return WorkspacePanel(
      child: Padding(
        padding: WorkspaceStyle.panelPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WorkspaceSectionHeader(title: '时间记录'),
            const SizedBox(height: 12),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapUp: (details) =>
                    _menu(details.globalPosition, null),
                child: Scrollbar(
                  controller: _scroll,
                  child: ListView(
                    controller: _scroll,
                    children: [
                      for (final tag in tags)
                        _target(
                          tag,
                          Draggable<String>(
                            data: tag.id,
                            dragAnchorStrategy: pointerDragAnchorStrategy,
                            feedback: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(tag.name),
                              ),
                            ),
                            child: GestureDetector(
                              onSecondaryTapUp: (details) =>
                                  _menu(details.globalPosition, tag),
                              child: TagTreeTile(
                                key: ValueKey('tag-${tag.id}'),
                                store: store,
                                tagId: tag.id,
                                label: tag.name,
                                depth: store.ancestors(tag.id).length - 1,
                                selected: widget.onActivityTagSelected == null
                                    ? _selected == tag.id
                                    : widget.activityTagIds.contains(tag.id),
                                collapsed: _collapsed.contains(tag.id),
                                onToggle: _hasChildren(store, tag)
                                    ? () => setState(() => _toggle(tag.id))
                                    : null,
                                // Tapping a parent row folds or unfolds its
                                // subtree; leaf rows keep the selection.
                                onTap: () async {
                                  if (widget.onActivityTagSelected != null) {
                                    if (await widget.beforeAction() &&
                                        mounted) {
                                      widget.onActivityTagSelected!(tag.id);
                                    }
                                    return;
                                  }
                                  if (_hasChildren(store, tag)) {
                                    setState(() => _toggle(tag.id));
                                    return;
                                  }
                                  if (await widget.beforeAction() && mounted) {
                                    setState(() => _selected = tag.id);
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      _target(
                        null,
                        const SizedBox(height: 180, width: double.infinity),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
