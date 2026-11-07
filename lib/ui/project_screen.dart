import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/journal_controller.dart';
import '../data/store.dart';
import '../domain/item.dart';
import '../domain/model.dart';
import '../domain/unicode.dart';
import 'dialogs.dart';
import 'pickers.dart' show PickerPopup;
import 'theme.dart'
    show tagColorOverrides, tagDisplayOverrides, tagEventColorsFor, tagDot;
import 'workspace_style.dart';

/// Project workspace: a tree of projects and planned items, edited in place
/// with three fields — name, description and result.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.journal, this.focusNode});
  final JournalController journal;
  final FocusNode? focusNode;
  @override
  State<ProjectScreen> createState() => ProjectScreenState();
}

class ProjectScreenState extends State<ProjectScreen> {
  static const _saveDelay = Duration(milliseconds: 500);

  String? _selected;
  bool _saving = false;
  late final _focus = widget.focusNode ?? FocusNode();
  final _rootAdd = TextEditingController();
  final _childAdd = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _result = TextEditingController();
  final _tagQuery = TextEditingController();
  final _nameFocus = FocusNode(debugLabel: 'project-name');
  final _childFocus = FocusNode(debugLabel: 'project-child-add');
  final _treeFocus = FocusNode(debugLabel: 'project-tree');
  final _collapsed = <String>{};
  String? _boundId;
  bool _tagOpen = false;
  Timer? _pendingSave;

  Store get _store => widget.journal.store;

  @override
  void dispose() {
    _pendingSave?.cancel();
    if (widget.focusNode == null) _focus.dispose();
    _rootAdd.dispose();
    _childAdd.dispose();
    _name.dispose();
    _description.dispose();
    _result.dispose();
    _tagQuery.dispose();
    _nameFocus.dispose();
    _childFocus.dispose();
    _treeFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            key: const ValueKey('project-error-toast'),
            content: Text(errorText(error)),
            behavior: SnackBarBehavior.floating,
            width: 480,
            showCloseIcon: true,
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Binds the three editors to one node. Switching nodes first writes whatever
  /// was typed, so nothing is lost when clicking around the tree.
  Future<void> _select(String? id) async {
    if (id == _selected) return;
    await _flush();
    if (!mounted) return;
    setState(() => _selected = id);
    _bind(id == null ? null : _store.items[id]);
  }

  void _bind(Item? item) {
    _boundId = item?.id;
    _name.text = item?.name ?? '';
    _description.text = item?.objective ?? '';
    _result.text = item?.outcome ?? '';
  }

  void _scheduleSave() {
    _pendingSave?.cancel();
    _pendingSave = Timer(_saveDelay, () => unawaited(_flush()));
  }

  Future<void> _flush() async {
    _pendingSave?.cancel();
    _pendingSave = null;
    final id = _boundId;
    if (id == null) return;
    final item = _store.items[id];
    if (item == null || item.source != null) return;
    final name = _name.text.trim();
    final next = item.copyWith(
      // An empty name would fail validation; keep the last good one.
      name: name.isEmpty ? item.name : name,
      objective: _description.text,
      outcome: _result.text,
    );
    if (next == item) return;
    await _run(() => widget.journal.saveItem(next));
  }

  /// Accepts several lines at once, so a brainstorm can be pasted in one go.
  Future<void> _addChildren(String? parentId, String text) async {
    final names = [
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (names.isEmpty) return;
    await _flush();
    await _run(() async {
      for (final name in names) {
        await widget.journal.createItem(name, parentId);
      }
    });
  }

  /// Right-click actions for a tree row, so renaming, adding a child and
  /// deleting all work without leaving the panel.
  Future<void> _rowMenu(Offset position, Item item) async {
    if (item.source != null) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('重命名')),
        PopupMenuItem(value: 'child', child: Text('新建子事项')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'rename':
        _treeFocus.requestFocus();
        await _select(item.id);
        if (!mounted) return;
        _nameFocus.requestFocus();
        _name.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _name.text.length,
        );
      case 'child':
        await _select(item.id);
        if (!mounted) return;
        _childFocus.requestFocus();
      case 'delete':
        await _delete(item);
    }
  }

  /// Keyboard handling for the tree: Del removes the selected node, arrows
  /// walk the visible rows.
  KeyEventResult _treeKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final rows = _visibleRows(_store.items);
    if (rows.isEmpty) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      final item = _selected == null ? null : _store.items[_selected];
      if (item == null) return KeyEventResult.ignored;
      unawaited(_delete(item));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      final current = rows.indexWhere((row) => row.$1.id == _selected);
      final delta = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      final next = current < 0
          ? 0
          : (current + delta).clamp(0, rows.length - 1);
      unawaited(_select(rows[next].$1.id));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _delete(Item item) async {
    if (item.source != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${item.name}」？'),
        content: const Text('它下面的记录会移到上一层，时间不会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _flush();
    await _run(() async {
      await widget.journal.deleteItem(item.id);
      if (!mounted) return;
      _bind(null);
      setState(() => _selected = item.parentId);
      _bind(_selected == null ? null : _store.items[_selected]);
    });
  }

  /// Adds one tag to the selected node, undoing any exclusion of it.
  Future<void> _addTag(Item item, String tagId) async {
    _tagQuery.clear();
    await _flush();
    await _run(
      () => widget.journal.saveItem(
        item.copyWith(
          tagIds: [...item.tagIds, tagId],
          excludedTagIds: [
            for (final id in item.excludedTagIds)
              if (id != tagId) id,
          ],
        ),
      ),
    );
  }

  /// Drops a tag this node set itself.
  Future<void> _removeTag(Item item, String tagId) async {
    await _flush();
    await _run(
      () => widget.journal.saveItem(
        item.copyWith(
          tagIds: [
            for (final id in item.tagIds)
              if (id != tagId) id,
          ],
        ),
      ),
    );
  }

  /// Drops a tag inherited from an ancestor for this branch only.
  Future<void> _excludeTag(Item item, String tagId) async {
    await _flush();
    await _run(
      () => widget.journal.saveItem(
        item.copyWith(
          excludedTagIds: [...item.excludedTagIds, tagId],
          tagIds: [
            for (final id in item.tagIds)
              if (id != tagId) id,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.journal,
      builder: (context, _) {
        final items = _store.items;
        final selected = _selected == null ? null : items[_selected];
        if (selected?.source != null) _bind(selected);
        if (_selected != null && selected == null) {
          _selected = null;
          _bind(null);
        }
        final durations = itemDurations(
          items,
          _store.events.values,
          splitOverlap: widget.journal.settings.splitOverlap,
        );
        return WorkspaceLayout(
          sidebar: _sidebar(items, durations),
          content: _detail(items, selected, durations),
        );
      },
    );
  }

  Widget _sidebar(Map<String, Item> items, Map<String, Duration> durations) {
    final rows = _visibleRows(items);
    return WorkspacePanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const WorkspaceSectionHeader(title: '事项'),
          _addField(
            key: const ValueKey('project-add'),
            controller: _rootAdd,
            hint: '新增事项，回车创建',
            parentId: null,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Focus(
              focusNode: _treeFocus,
              onKeyEvent: _treeKey,
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '还没有事项。在上面输入名字，回车就建好了。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final (item, depth) = rows[index];
                        return _tile(
                          item,
                          depth,
                          durations[item.id] ?? Duration.zero,
                          hasChildren: items.values.any(
                            (child) => child.parentId == item.id,
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rows the tree shows, honouring which branches are folded.
  List<(Item, int)> _visibleRows(Map<String, Item> items) {
    final children = <String?, List<Item>>{};
    for (final item in items.values) {
      (children[item.parentId] ??= []).add(item);
    }
    for (final siblings in children.values) {
      siblings.sort(compareItemOrder);
    }
    final rows = <(Item, int)>[];
    void visit(String? parentId, int depth) {
      for (final item in children[parentId] ?? const <Item>[]) {
        rows.add((item, depth));
        if (!_collapsed.contains(item.id)) visit(item.id, depth + 1);
      }
    }

    visit(null, 0);
    return rows;
  }

  Widget _tile(
    Item item,
    int depth,
    Duration duration, {
    required bool hasChildren,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selected = item.id == _selected;
    return InkWell(
      key: ValueKey('project-${item.id}'),
      borderRadius: BorderRadius.circular(WorkspaceStyle.controlRadius),
      onTap: () {
        _treeFocus.requestFocus();
        unawaited(_select(item.id));
      },
      onSecondaryTapDown: (details) =>
          unawaited(_rowMenu(details.globalPosition, item)),
      child: Container(
        padding: EdgeInsets.only(left: 4 + depth * 14.0, right: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.secondaryContainer : null,
          borderRadius: BorderRadius.circular(WorkspaceStyle.controlRadius),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: hasChildren
                  ? IconButton(
                      key: ValueKey('project-toggle-${item.id}'),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 22,
                        height: 22,
                      ),
                      iconSize: 16,
                      tooltip: _collapsed.contains(item.id) ? '展开' : '收起',
                      onPressed: () => setState(() {
                        if (!_collapsed.remove(item.id)) {
                          _collapsed.add(item.id);
                        }
                      }),
                      icon: Icon(
                        _collapsed.contains(item.id)
                            ? Icons.chevron_right
                            : Icons.expand_more,
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ),
            ),
            if (item.source != null || item.status != ItemStatus.active)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  item.source?.missing == true ? '已移除' : item.status.label,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            if (duration > Duration.zero)
              Text(
                durationText(duration),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detail(
    Map<String, Item> items,
    Item? item,
    Map<String, Duration> durations,
  ) {
    if (item == null) {
      return WorkspacePanel(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            '选择左侧的事项来写描述和结果，\n或者直接在上面输入名字新建一个。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final children = [
      for (final child in items.values)
        if (child.parentId == item.id) child,
    ]..sort(compareItemOrder);
    final total = durations[item.id] ?? Duration.zero;
    return WorkspacePanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('project-name'),
                  controller: _name,
                  readOnly: item.source != null,
                  focusNode: _nameFocus,
                  style: Theme.of(context).textTheme.headlineSmall,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '名字',
                  ),
                  onChanged: (_) => _scheduleSave(),
                  onTapOutside: (_) => unawaited(_flush()),
                ),
              ),
              const SizedBox(width: 12),
              if (item.source == null)
                SizedBox(width: 260, child: _tagSearch(item)),
              IconButton(
                key: const ValueKey('project-delete'),
                tooltip: '删除',
                onPressed: _saving || item.source != null
                    ? null
                    : () => unawaited(_delete(item)),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _selectedTags(item),
          const SizedBox(height: 4),
          Text(
            item.source == null
                ? item.status.label
                : 'Obsidian · ${item.source!.path} · ${item.status.label}${item.source!.missing ? ' · 源中已移除，历史保留' : ''}，请在 Obsidian 中修改',
            key: const ValueKey('item-source-status'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                    key: const ValueKey('project-description'),
                    controller: _description,
                    label: '描述',
                    readOnly: item.source != null,
                    hint: item.source == null ? '这件事是做什么的，为什么做' : '暂无描述',
                    minLines: 3,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    key: const ValueKey('project-result'),
                    controller: _result,
                    label: '结果',
                    readOnly: item.source != null,
                    hint: item.source == null ? '做完之后得到了什么，放弃了也写在这里' : '暂无结果',
                    minLines: 3,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '子事项 ${children.length}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (total > Duration.zero)
                        Text(
                          '累计 ${durationText(total)}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  for (final child in children)
                    _childRow(child, durations[child.id] ?? Duration.zero),
                  _addField(
                    key: const ValueKey('project-add-child'),
                    controller: _childAdd,
                    focusNode: _childFocus,
                    hint: '新增子事项，回车创建；可粘贴多行',
                    parentId: item.id,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One look for every plain field on this panel: same fill, radius and
  /// padding, so the form reads as a single surface instead of mixed boxes.
  InputDecoration _box({String? hint, Widget? prefixIcon}) {
    final scheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(WorkspaceStyle.controlRadius),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      hintText: hint,
      prefixIcon: prefixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(WorkspaceStyle.controlRadius),
        borderSide: BorderSide(color: scheme.primary, width: 1),
      ),
    );
  }

  /// Enter turns the line into a node; pasting a block creates one per line.
  Widget _addField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required String? parentId,
    FocusNode? focusNode,
  }) => TextField(
    key: key,
    controller: controller,
    focusNode: focusNode,
    minLines: 1,
    maxLines: null,
    keyboardType: TextInputType.multiline,
    decoration: _box(hint: hint, prefixIcon: const Icon(Icons.add, size: 18)),
    onChanged: (value) {
      if (!value.contains('\n')) return;
      controller.clear();
      unawaited(_addChildren(parentId, value));
    },
  );

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String hint,
    int minLines = 2,
    bool readOnly = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      TextField(
        key: key,
        controller: controller,
        minLines: minLines,
        readOnly: readOnly,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: _box(hint: hint),
        onChanged: (_) => _scheduleSave(),
        onTapOutside: (_) => unawaited(_flush()),
      ),
    ],
  );

  Widget _childRow(Item child, Duration duration) {
    final scheme = Theme.of(context).colorScheme;
    final description = child.objective.trim();
    final result = child.outcome.trim();
    final details = [
      if (duration > Duration.zero) durationText(duration),
      if (description.isNotEmpty) description,
      if (result.isNotEmpty) '→ $result',
    ].join(' · ');
    return InkWell(
      key: ValueKey('project-child-${child.id}'),
      borderRadius: BorderRadius.circular(WorkspaceStyle.controlRadius),
      onTap: () => unawaited(_select(child.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    child.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// Searchable tag bar: typing filters the tree, picking adds one. The full
  /// list never opens at once, so a large tag tree stays readable.
  Widget _tagSearch(Item item) => PickerPopup(
    open: _tagOpen,
    groupId: item.id,
    onClose: () => setState(() => _tagOpen = false),
    anchor: TextField(
      key: const ValueKey('project-tag-search'),
      controller: _tagQuery,
      decoration: _box(
        hint: '标签，可搜索',
        prefixIcon: const Icon(Icons.label_outline, size: 18),
      ),
      onTap: () => setState(() => _tagOpen = true),
      onChanged: (_) => setState(() => _tagOpen = true),
      onSubmitted: (_) {
        final matches = _tagMatches(item);
        if (matches.isNotEmpty) unawaited(_addTag(item, matches.first.id));
      },
    ),
    builder: (context, close) => _tagOptions(item, close),
  );

  List<Tag> _tagMatches(Item item) {
    final needle = caseFold(_tagQuery.text.trim());
    return [
      for (final tag in _store.orderedTags())
        if (!item.tagIds.contains(tag.id) &&
            (needle.isEmpty ||
                caseFold(
                  _store
                      .ancestors(tag.id)
                      .map((entry) => entry.name)
                      .join(' / '),
                ).contains(needle)))
          tag,
    ];
  }

  Widget _tagOptions(Item item, VoidCallback close) {
    final matches = _tagMatches(item);
    if (matches.isEmpty) {
      return const Padding(padding: EdgeInsets.all(12), child: Text('没有匹配的标签'));
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 280),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final tag in matches)
              ListTile(
                key: ValueKey('project-tag-${tag.id}'),
                dense: true,
                leading: CircleAvatar(
                  radius: 4,
                  backgroundColor: tagDot(context, _store, tag.id),
                ),
                title: Text(
                  tag.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _store
                      .ancestors(tag.id)
                      .map((entry) => entry.name)
                      .join(' / '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  close();
                  unawaited(_addTag(item, tag.id));
                },
              ),
          ],
        ),
      ),
    );
  }

  /// The tags this node adds and the ones it inherits, as removable chips.
  Widget _selectedTags(Item item) {
    final own = item.tagIds;
    final inherited = [
      for (final id in _store.effectiveItemTagIds(item.id))
        if (!own.contains(id)) id,
    ];
    if (own.isEmpty && inherited.isEmpty) {
      return Text(
        item.source == null ? '还没有标签，在右上角搜索添加。' : '没有标签，可在 Obsidian 文件属性中添加。',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final id in own) _chip(item, id, inherited: false),
        for (final id in inherited) _chip(item, id, inherited: true),
      ],
    );
  }

  /// A tag painted in its own colour instead of carrying a suffix. Inherited
  /// tags use the lighter tone, so the two stay distinguishable without words.
  Widget _chip(Item item, String id, {required bool inherited}) {
    final (background, foreground) = tagEventColorsFor(
      _store,
      id,
      tagColorOverrides(context),
      selected: !inherited,
      tagDisplays: tagDisplayOverrides(context),
    );
    return InputChip(
      key: ValueKey(
        inherited ? 'project-chip-inherited-$id' : 'project-chip-$id',
      ),
      label: Text(_store.tagName(id)),
      labelStyle: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      backgroundColor: background,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      deleteIconColor: foreground,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onDeleted: _saving || item.source != null
          ? null
          : () => unawaited(
              inherited ? _excludeTag(item, id) : _removeTag(item, id),
            ),
    );
  }
}
