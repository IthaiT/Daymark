import 'dart:async';

import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../domain/item.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'workspace_style.dart';

/// Project workspace: the tree of projects and planned items, separate from
/// the time records that point at it.
class ProjectScreen extends StatefulWidget {
  const ProjectScreen({super.key, required this.journal, this.focusNode});
  final JournalController journal;
  final FocusNode? focusNode;
  @override
  State<ProjectScreen> createState() => ProjectScreenState();
}

class ProjectScreenState extends State<ProjectScreen> {
  String? _selected;
  bool _saving = false;
  late final _focus = widget.focusNode ?? FocusNode();

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
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

  Future<void> _edit([Item? item, String? parentId]) async {
    final result = await showDialog<Item>(
      context: context,
      builder: (context) => _ItemDialog(
        journal: widget.journal,
        item: item,
        parentId: item?.parentId ?? parentId,
      ),
    );
    if (result == null || !mounted) return;
    await _run(() async {
      final saved = await widget.journal.saveItem(result);
      if (mounted) setState(() => _selected = saved.id);
    });
  }

  Future<void> _createChild(Item parent) => _edit(null, parent.id);

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
    await _run(() async {
      await widget.journal.deleteItem(item.id);
      if (mounted) setState(() => _selected = item.parentId);
    });
  }

  Future<void> _menu(Offset position, Item item) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('修改项目')),
        PopupMenuItem(value: 'child', child: Text('新建子事项')),
        PopupMenuItem(value: 'delete', child: Text('删除项目')),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'edit':
        await _edit(item);
      case 'child':
        await _createChild(item);
      case 'delete':
        await _delete(item);
    }
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    child: AnimatedBuilder(
      animation: widget.journal,
      builder: (context, _) {
        final items = widget.journal.store.items;
        return WorkspaceLayout(
          sidebar: _sidebar(items),
          content: _detail(items),
        );
      },
    ),
  );

  Widget _sidebar(Map<String, Item> items) {
    final ordered = orderedItems(items);
    final durations = itemDurations(items, widget.journal.store.events.values);
    return WorkspacePanel(
      padding: WorkspaceStyle.panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkspaceSectionHeader(
            title: '项目',
            actions: [
              IconButton(
                key: const ValueKey('project-add'),
                tooltip: '新建项目',
                onPressed: _saving ? null : () => unawaited(_edit()),
                icon: const Icon(Icons.add, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ordered.isEmpty
                ? Center(
                    child: Text(
                      '还没有项目',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView(
                    children: [
                      for (final (item, depth) in ordered)
                        _tile(item, depth, durations[item.id] ?? Duration.zero),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Item item, int depth, Duration duration) {
    final selected = item.id == _selected;
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (item.status) {
      ItemStatus.active => Icons.radio_button_unchecked,
      ItemStatus.paused => Icons.pause_circle_outline,
      ItemStatus.done => Icons.check_circle_outline,
      ItemStatus.dropped => Icons.remove_circle_outline,
    };
    return Material(
      color: selected ? scheme.secondaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(WorkspaceStyle.controlRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('project-${item.id}'),
        onTap: () => setState(() => _selected = item.id),
        onSecondaryTapUp: (details) =>
            unawaited(_menu(details.globalPosition, item)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8 + depth * 16, 8, 8, 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: item.status.isOpen ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (duration > Duration.zero)
                Text(
                  durationText(duration),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(Map<String, Item> items) {
    final item = _selected == null ? null : items[_selected];
    if (item == null) {
      return WorkspacePanel(
        padding: WorkspaceStyle.panelPadding,
        child: Center(
          child: Text(
            '选择左侧的项目查看详情',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    final events =
        widget.journal.store.events.values
            .where(
              (event) =>
                  event.itemId != null &&
                  itemOwnedBy(items, event.itemId!, item.id),
            )
            .toList()
          ..sort((a, b) => b.start.compareTo(a.start));
    final durations = itemDurations(items, widget.journal.store.events.values);
    final children = orderedItems(
      items,
    ).where((entry) => entry.$1.parentId == item.id).toList();
    final scheme = Theme.of(context).colorScheme;
    return WorkspacePanel(
      padding: WorkspaceStyle.panelPadding,
      child: ListView(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      durations[item.id] == null ||
                              durations[item.id] == Duration.zero
                          ? '还没有记录时间'
                          : '累计 ${durationText(durations[item.id]!)} · ${events.length} 条记录',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.status.label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: '修改项目',
                onPressed: _saving ? null : () => unawaited(_edit(item)),
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: '删除项目',
                onPressed: _saving ? null : () => unawaited(_delete(item)),
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _text('目标', item.objective, '写下完成时要达到什么'),
          _text('结果', item.outcome, '完成后记录结果，放弃时记录原因'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '子事项',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: _saving ? null : () => unawaited(_createChild(item)),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加'),
              ),
            ],
          ),
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '可以把这件事拆成更小的步骤，拆出来的条目不需要立刻有记录。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final (child, _) in children)
              ListTile(
                key: ValueKey('project-child-${child.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (child.status) {
                  ItemStatus.active => Icons.radio_button_unchecked,
                  ItemStatus.paused => Icons.pause_circle_outline,
                  ItemStatus.done => Icons.check_circle_outline,
                  ItemStatus.dropped => Icons.remove_circle_outline,
                }, size: 16),
                title: Text(child.name),
                trailing: Text(
                  durations[child.id] == null ||
                          durations[child.id] == Duration.zero
                      ? '—'
                      : durationText(durations[child.id]!),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                onTap: () => setState(() => _selected = child.id),
              ),
          const SizedBox(height: 16),
          Text('记录', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (events.isEmpty)
            Text(
              '在时间记录里输入事项名，就会自动归到这里。',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final event in events.take(12))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 132,
                      child: Text(
                        '${dateText(event.start)} ${clockText(event.start)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      event.end == null
                          ? '进行中'
                          : durationText(event.end!.difference(event.start)),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _text(String label, String value, [String? hint]) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(
          value.trim().isEmpty ? (hint ?? '未填写') : value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: value.trim().isEmpty
                ? Theme.of(context).colorScheme.outline
                : null,
          ),
        ),
      ],
    ),
  );
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.journal, this.item, this.parentId});
  final JournalController journal;
  final Item? item;
  final String? parentId;
  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _objective = TextEditingController(
    text: widget.item?.objective ?? '',
  );
  late final _outcome = TextEditingController(text: widget.item?.outcome ?? '');
  late final _started = TextEditingController(
    text: widget.item?.startedOn == null
        ? ''
        : dateText(widget.item!.startedOn!),
  );
  late final _ended = TextEditingController(
    text: widget.item?.endedOn == null ? '' : dateText(widget.item!.endedOn!),
  );
  late ItemStatus _status = widget.item?.status ?? ItemStatus.active;
  late String? _parentId = widget.parentId;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _objective.dispose();
    _outcome.dispose();
    _started.dispose();
    _ended.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final started = _started.text.trim().isEmpty
          ? null
          : parseDate(_started.text);
      final ended = _ended.text.trim().isEmpty ? null : parseDate(_ended.text);
      final item = Item(
        id: widget.item?.id ?? widget.journal.newItemId(),
        name: _name.text.trim(),
        parentId: _parentId,
        status: _status,
        startedOn: started,
        endedOn: ended,
        objective: _objective.text.trim(),
        outcome: _outcome.text.trim(),
      );
      // Validate against the tree the store will see, before closing.
      final items = {...widget.journal.store.items, item.id: item};
      validateItems(items);
      if (!mounted) return;
      Navigator.of(context).pop(item);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.journal.store;
    final excluded = widget.item == null
        ? const <String>{}
        : {
            widget.item!.id,
            for (final entry in orderedItems(store.items))
              if (itemOwnedBy(store.items, entry.$1.id, widget.item!.id))
                entry.$1.id,
          };
    final parents = orderedItems(
      store.items,
    ).where((entry) => !excluded.contains(entry.$1.id)).toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item == null ? '新建项目' : '修改项目',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const ValueKey('project-name'),
                        controller: _name,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: '名称'),
                        onSubmitted: (_) => unawaited(_save()),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        key: const ValueKey('project-parent'),
                        initialValue: _parentId,
                        decoration: const InputDecoration(labelText: '上级'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('顶层'),
                          ),
                          for (final (item, depth) in parents)
                            DropdownMenuItem<String?>(
                              value: item.id,
                              child: Text('${'　' * depth}${item.name}'),
                            ),
                        ],
                        onChanged: (value) => setState(() => _parentId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<ItemStatus>(
                        key: const ValueKey('project-status'),
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: '状态'),
                        items: [
                          for (final status in ItemStatus.values)
                            DropdownMenuItem(
                              value: status,
                              child: Text(status.label),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _status = value ?? _status),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _started,
                              decoration: const InputDecoration(
                                labelText: '开始日期',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _ended,
                              decoration: const InputDecoration(
                                labelText: '结束日期',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _objective,
                        decoration: const InputDecoration(labelText: '目标'),
                        minLines: 1,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _outcome,
                        decoration: const InputDecoration(labelText: '结果 / 原因'),
                        minLines: 1,
                        maxLines: 3,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => unawaited(_save()),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
