import 'dart:async';

import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../data/store.dart';
import '../domain/item.dart';
import '../domain/model.dart';
import 'dialogs.dart';
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
  final _collapsed = <String>{};
  String? _boundId;
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
    if (item == null) return;
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

  Future<void> _delete(Item item) async {
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

  /// Applies one tag to the selected node: own tags are removed, inherited ones
  /// are dropped for this branch, everything else is added.
  Future<void> _toggleTag(Item item, String tagId) async {
    await _flush();
    final own = item.tagIds.contains(tagId);
    final inherited =
        !own && _store.effectiveItemTagIds(item.id).contains(tagId);
    final excluded = item.excludedTagIds.contains(tagId);
    final next = own
        ? item.copyWith(
            tagIds: [
              for (final id in item.tagIds)
                if (id != tagId) id,
            ],
          )
        : inherited
        ? item.copyWith(excludedTagIds: [...item.excludedTagIds, tagId])
        : excluded
        ? item.copyWith(
            excludedTagIds: [
              for (final id in item.excludedTagIds)
                if (id != tagId) id,
            ],
            tagIds: [...item.tagIds, tagId],
          )
        : item.copyWith(tagIds: [...item.tagIds, tagId]);
    await _run(() => widget.journal.saveItem(next));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.journal,
      builder: (context, _) {
        final items = _store.items;
        final selected = _selected == null ? null : items[_selected];
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
          WorkspaceSectionHeader(
            title: '项目',
            actions: [
              Text(
                '${items.length}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          _addField(
            key: const ValueKey('project-add'),
            controller: _rootAdd,
            hint: '新增项目，回车创建',
            parentId: null,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '还没有项目。在上面输入名字，回车就建好了。',
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
      onTap: () => unawaited(_select(item.id)),
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
            '选择左侧的项目来写描述和结果，\n或者直接在上面输入名字新建一个。',
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
              Text(
                total == Duration.zero ? '还没有记录' : durationText(total),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              IconButton(
                key: const ValueKey('project-delete'),
                tooltip: '删除',
                onPressed: _saving ? null : () => unawaited(_delete(item)),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                    key: const ValueKey('project-description'),
                    controller: _description,
                    label: '描述',
                    hint: '这件事是做什么的，为什么做',
                    minLines: 3,
                  ),
                  const SizedBox(height: 14),
                  _field(
                    key: const ValueKey('project-result'),
                    controller: _result,
                    label: '结果',
                    hint: '做完之后得到了什么，放弃了也写在这里',
                    minLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Text('标签', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  _tagBar(item),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '子事项 ${children.length}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      Text(
                        '点一行进入它自己的页面',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  /// Enter turns the line into a node; pasting a block creates one per line.
  Widget _addField({
    required Key key,
    required TextEditingController controller,
    required String hint,
    required String? parentId,
  }) => TextField(
    key: key,
    controller: controller,
    minLines: 1,
    maxLines: null,
    keyboardType: TextInputType.multiline,
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      prefixIcon: const Icon(Icons.add, size: 18),
    ),
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
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      TextField(
        key: key,
        controller: controller,
        minLines: minLines,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        decoration: InputDecoration(hintText: hint, isDense: true),
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
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

  Widget _tagBar(Item item) {
    final own = item.tagIds;
    final inherited = [
      for (final id in _store.effectiveItemTagIds(item.id))
        if (!own.contains(id)) id,
    ];
    final tags = _store.orderedTags();
    if (tags.isEmpty) {
      return Text(
        '还没有标签，去标签导图里建一个。',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 132),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in tags)
              FilterChip(
                key: ValueKey('project-tag-${tag.id}'),
                selected: own.contains(tag.id) || inherited.contains(tag.id),
                label: Text(
                  inherited.contains(tag.id) ? '${tag.name}（继承）' : tag.name,
                ),
                onSelected: _saving
                    ? null
                    : (_) => unawaited(_toggleTag(item, tag.id)),
              ),
          ],
        ),
      ),
    );
  }
}
