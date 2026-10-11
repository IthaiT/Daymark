import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'theme.dart';

class TagSidebar extends StatefulWidget {
  const TagSidebar({
    super.key,
    required this.journal,
    required this.beforeAction,
    required this.onError,
  });
  final JournalController journal;
  final Future<bool> Function() beforeAction;
  final ValueChanged<Object> onError;
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
          if (tag.parentId != null)
            const PopupMenuItem(value: 'root', child: Text('移至一级标签')),
          const PopupMenuItem(value: 'delete', child: Text('删除标签')),
        ],
      ],
    );
    if (!mounted) return;
    try {
      switch (choice) {
        case 'add':
          await showTagEditor(context, widget.journal, parentId: tag?.id);
        case 'edit':
          await showTagEditor(context, widget.journal, id: tag!.id);
        case 'root':
          await widget.journal.moveTag(tag!.id, null);
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
    return SizedBox(
      width: 250,
      // Material keeps ListTile ink and tile colors visible above the tint.
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Daymark',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 28),
              Text('我的标签', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) =>
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
                                onSecondaryTapDown: (details) =>
                                    _menu(details.globalPosition, tag),
                                onDoubleTap: () => setState(() {
                                  if (!_collapsed.add(tag.id)) {
                                    _collapsed.remove(tag.id);
                                  }
                                }),
                                child: ListTile(
                                  key: ValueKey('tag-${tag.id}'),
                                  dense: true,
                                  selected: _selected == tag.id,
                                  selectedTileColor: Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  contentPadding: EdgeInsets.only(
                                    left:
                                        4 +
                                        (store.ancestors(tag.id).length - 1) *
                                            20.0,
                                    right: 4,
                                  ),
                                  leading: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: tagDot(store, tag.id),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                  title: Text(
                                    tag.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing:
                                      store.tags.values.any(
                                        (child) => child.parentId == tag.id,
                                      )
                                      ? GestureDetector(
                                          onTap: () => setState(() {
                                            if (!_collapsed.add(tag.id)) {
                                              _collapsed.remove(tag.id);
                                            }
                                          }),
                                          child: Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Icon(
                                              _collapsed.contains(tag.id)
                                                  ? Icons.chevron_right
                                                  : Icons.keyboard_arrow_down,
                                              size: 20,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        )
                                      : null,
                                  onTap: () async {
                                    if (await widget.beforeAction() &&
                                        mounted) {
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
      ),
    );
  }
}
