import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../domain/item.dart';
import '../domain/model.dart';
import '../domain/unicode.dart';
import 'dialogs.dart' show errorText;
import 'workspace_style.dart';

Future<void> showEventOrganizer(
  BuildContext context,
  JournalController journal,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => EventOrganizer(journal: journal),
);

String _tagPath(JournalController journal, String id) =>
    journal.store.ancestors(id).map((tag) => tag.name).join(' / ');

/// An occasional maintenance tool, deliberately outside workspace navigation.
class EventOrganizer extends StatefulWidget {
  const EventOrganizer({super.key, required this.journal});
  final JournalController journal;
  @override
  State<EventOrganizer> createState() => _EventOrganizerState();
}

class _EventOrganizerState extends State<EventOrganizer> {
  String? _tagId;
  String _tagQuery = '';
  String _query = '';
  bool _descendants = false;
  DateTimeRange? _range;
  final _selected = <String>{};
  bool _busy = false;
  String? _error;
  final _tagScroll = ScrollController();
  final _eventScroll = ScrollController();
  JournalController get journal => widget.journal;

  @override
  void dispose() {
    _tagScroll.dispose();
    _eventScroll.dispose();
    super.dispose();
  }

  void _filter(VoidCallback change) => setState(() {
    change();
    _selected.clear();
    _error = null;
    if (_eventScroll.hasClients) _eventScroll.jumpTo(0);
  });

  bool _inTag(Event event, String? id) {
    if (id == null) return true;
    if (id.isEmpty) return event.tagIds.isEmpty;
    return event.tagIds.any(
      (tag) =>
          tag == id ||
          (_descendants &&
              journal.store.ancestors(tag).any((node) => node.id == id)),
    );
  }

  List<Event> get _events {
    final needle = caseFold(_query.trim());
    final range = _range;
    final from = range == null ? null : civilTime(range.start);
    final until = range == null
        ? null
        : civilTime(range.end).add(const Duration(days: 1));
    return journal.store.events.values.where((event) {
      if (event.isUndefined || !_inTag(event, _tagId)) return false;
      if (from != null &&
          until != null &&
          (!event.start.isBefore(until) ||
              !(event.end ?? event.start.add(const Duration(microseconds: 1)))
                  .isAfter(from))) {
        return false;
      }
      return needle.isEmpty ||
          caseFold('${event.title}\n${event.notes}').contains(needle);
    }).toList()..sort((a, b) {
      final time = b.start.compareTo(a.start);
      return time != 0 ? time : a.id.compareTo(b.id);
    });
  }

  Future<void> _pickRange() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
      initialDateRange: _range,
      helpText: '筛选事件日期',
      saveText: '应用',
      confirmText: '应用',
    );
    if (result != null && mounted) _filter(() => _range = result);
  }

  Future<void> _move() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final count = _selected.length;
    final moved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RepaintBoundary(
        key: const ValueKey('organize-move-capture'),
        child: _MoveDialog(journal: journal, ids: {..._selected}),
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (moved == true) _selected.clear();
    });
    if (moved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已移动 $count 条事件', style: const TextStyle(fontSize: 16)),
        ),
      );
    }
  }

  Future<void> _history(bool redo) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (redo) {
        await journal.redo();
      } else {
        await journal.undo();
      }
      if (mounted) setState(_selected.clear);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cleanup() async {
    final ids = journal.unusedTagIds;
    final tags = journal.store
        .orderedTags()
        .where((tag) => ids.contains(tag.id))
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('清理 ${ids.length} 个空标签'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '以下标签及其子标签均未被事件、事项或草稿使用。删除后会清空撤销记录。',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    for (final tag in tags)
                      ListTile(
                        leading: const Icon(Icons.label_outline),
                        title: Text(
                          _tagPath(journal, tag.id),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: '取消',
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
          ),
          IconButton.filled(
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            tooltip: '确认删除空标签',
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await journal.deleteUnusedTags(ids);
      if (mounted) {
        _filter(() {
          if (ids.contains(_tagId)) _tagId = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: journal,
    builder: (context, _) {
      final events = _events;
      final visibleIds = events.map((event) => event.id).toSet();
      _selected.retainAll(visibleIds);
      final size = MediaQuery.sizeOf(context);
      return PopScope(
        canPop: !_busy,
        child: Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: SizedBox(
            width: math.min(1160, size.width - 40),
            height: math.min(780, size.height - 40),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.drive_file_move_outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '历史事件整理',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: '撤销最近修改',
                        onPressed: !_busy && journal.history.canUndo
                            ? () => _history(false)
                            : null,
                        icon: const Icon(Icons.undo),
                      ),
                      IconButton(
                        tooltip: '重做最近修改',
                        onPressed: !_busy && journal.history.canRedo
                            ? () => _history(true)
                            : null,
                        icon: const Icon(Icons.redo),
                      ),
                      IconButton(
                        tooltip: '清理空标签',
                        onPressed: !_busy && journal.unusedTagIds.isNotEmpty
                            ? _cleanup
                            : null,
                        icon: const Icon(Icons.cleaning_services_outlined),
                      ),
                      IconButton(
                        tooltip: '关闭整理',
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: math.max(860, constraints.maxWidth),
                          height: constraints.maxHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 280, child: _sources()),
                              const SizedBox(width: 16),
                              Expanded(child: _records(events)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _sources() {
    final needle = caseFold(_tagQuery.trim());
    final tags = journal.store
        .orderedTags()
        .where((tag) => caseFold(_tagPath(journal, tag.id)).contains(needle))
        .toList();
    final records = journal.store.events.values
        .where((event) => !event.isUndefined)
        .toList();
    final counts = <String, int>{};
    for (final event in records) {
      final scope = event.tagIds.toSet();
      if (_descendants) {
        for (final id in event.tagIds) {
          scope.addAll(journal.store.ancestors(id).map((tag) => tag.id));
        }
      }
      if (scope.isEmpty) scope.add('');
      for (final id in scope) {
        counts.update(id, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    Widget source(String? id, String name) => ListTile(
      key: ValueKey('organize-source-${id ?? 'all'}'),
      selected: _tagId == id,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      leading: Icon(
        id == null
            ? Icons.all_inbox_outlined
            : id.isEmpty
            ? Icons.label_off_outlined
            : Icons.label_outline,
      ),
      title: Text(name, style: const TextStyle(fontSize: 16)),
      trailing: Text(
        '${id == null ? records.length : counts[id] ?? 0}',
        style: const TextStyle(fontSize: 16),
      ),
      onTap: _busy ? null : () => _filter(() => _tagId = id),
    );
    return WorkspacePanel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              key: const ValueKey('organize-tag-search'),
              enabled: !_busy,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                hintText: '查找来源标签',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _tagQuery = value),
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: _tagScroll,
              child: ListView(
                controller: _tagScroll,
                children: [
                  source(null, '全部事件'),
                  source('', '无标签'),
                  for (final tag in tags)
                    source(tag.id, _tagPath(journal, tag.id)),
                  if (tags.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('没有匹配的标签', style: TextStyle(fontSize: 16)),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            key: const ValueKey('organize-descendants'),
            title: const Text('包含子标签', style: TextStyle(fontSize: 16)),
            value: _descendants,
            onChanged: _busy
                ? null
                : (value) => _filter(() => _descendants = value),
          ),
        ],
      ),
    );
  }

  Widget _records(List<Event> events) => WorkspacePanel(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('organize-event-search'),
                enabled: !_busy,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: '搜索事件名称或备注',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => _filter(() => _query = value),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '筛选日期',
              onPressed: _busy ? null : _pickRange,
              icon: const Icon(Icons.date_range_outlined),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Checkbox(
              key: const ValueKey('organize-select-all'),
              semanticLabel: '选择全部筛选结果',
              tristate: true,
              value: _selected.isEmpty
                  ? false
                  : _selected.length == events.length
                  ? true
                  : null,
              onChanged: _busy || events.isEmpty
                  ? null
                  : (_) => setState(() {
                      if (_selected.length == events.length) {
                        _selected.clear();
                      } else {
                        _selected.addAll(events.map((event) => event.id));
                      }
                    }),
            ),
            Expanded(
              child: Text(
                '已选 ${_selected.length} / ${events.length} 条',
                style: const TextStyle(fontSize: 16),
              ),
            ),
            IconButton.filled(
              style: IconButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
              tooltip: '移动所选事件',
              onPressed: !_busy && _selected.isNotEmpty ? _move : null,
              icon: const Icon(Icons.drive_file_move_outline),
            ),
          ],
        ),
        if (_range != null)
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(
              label: Text(
                '${dateText(_range!.start)} — ${dateText(_range!.end)}',
                style: const TextStyle(fontSize: 16),
              ),
              onDeleted: _busy ? null : () => _filter(() => _range = null),
              deleteButtonTooltipMessage: '清除日期筛选',
            ),
          ),
        const Divider(),
        Expanded(
          child: events.isEmpty
              ? const Center(
                  child: Text('没有符合条件的事件', style: TextStyle(fontSize: 16)),
                )
              : Scrollbar(
                  controller: _eventScroll,
                  child: ListView.builder(
                    controller: _eventScroll,
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return CheckboxListTile(
                        key: ValueKey('organize-event-${event.id}'),
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(event.id),
                        title: Text(
                          event.title,
                          style: const TextStyle(fontSize: 16),
                        ),
                        subtitle: Text(
                          [
                            '${timestampText(event.start).replaceFirst('T', ' ')} → ${event.end == null ? '待补全' : timestampText(event.end!).replaceFirst('T', ' ')}',
                            if (event.itemId != null)
                              '事项：${journal.store.itemPath(event.itemId!)}',
                            event.tagIds.isEmpty
                                ? '无标签'
                                : event.tagIds
                                      .map((id) => _tagPath(journal, id))
                                      .join(' · '),
                          ].join('\n'),
                          style: const TextStyle(fontSize: 16),
                        ),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  _selected.add(event.id);
                                } else {
                                  _selected.remove(event.id);
                                }
                              }),
                      );
                    },
                  ),
                ),
        ),
      ],
    ),
  );
}

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.journal, required this.ids});
  final JournalController journal;
  final Set<String> ids;
  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  bool _items = false;
  String _query = '';
  OwnerRef? _target;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.journal.moveEventsTo(widget.ids, _target!);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.journal.store;
    final needle = caseFold(_query.trim());
    final choices = <(OwnerRef, String, IconData)>[
      if (_items)
        for (final (item, _) in orderedItems(store.items))
          (
            (id: item.id, isItem: true),
            store.itemPath(item.id),
            switch (item.status) {
              ItemStatus.active => Icons.radio_button_unchecked,
              ItemStatus.paused => Icons.pause_circle_outline,
              ItemStatus.done => Icons.check_circle_outline,
              ItemStatus.dropped => Icons.cancel_outlined,
            },
          )
      else
        for (final tag in store.orderedTags())
          (
            (id: tag.id, isItem: false),
            _tagPath(widget.journal, tag.id),
            Icons.label_outline,
          ),
    ].where((choice) => caseFold(choice.$2).contains(needle)).toList();
    final target = _target;
    final tags = target == null
        ? <String>[]
        : target.isItem
        ? store.effectiveItemTagIds(target.id)
        : [target.id];
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text('移动 ${widget.ids.length} 条事件'),
        content: SizedBox(
          width: 560,
          height: 540,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('标签', style: TextStyle(fontSize: 16)),
                    icon: Icon(Icons.label_outline),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('事项', style: TextStyle(fontSize: 16)),
                    icon: Icon(Icons.workspaces_outline),
                  ),
                ],
                selected: {_items},
                onSelectionChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _items = value.single;
                        _target = null;
                      }),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('organize-target-search'),
                autofocus: true,
                enabled: !_saving,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  hintText: '搜索目标名称或路径',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: choices.isEmpty
                    ? const Center(
                        child: Text('没有匹配的目标', style: TextStyle(fontSize: 16)),
                      )
                    : ListView.builder(
                        itemCount: choices.length,
                        itemBuilder: (context, index) {
                          final (owner, path, icon) = choices[index];
                          return ListTile(
                            key: ValueKey('organize-target-${owner.id}'),
                            leading: Icon(icon),
                            selected: _target == owner,
                            selectedTileColor: Theme.of(
                              context,
                            ).colorScheme.secondaryContainer,
                            title: Text(
                              path,
                              style: const TextStyle(fontSize: 16),
                            ),
                            trailing: _target == owner
                                ? const Icon(Icons.check)
                                : null,
                            onTap: _saving
                                ? null
                                : () => setState(() => _target = owner),
                          );
                        },
                      ),
              ),
              const Divider(),
              if (target != null) ...[
                Text(
                  '目标：${target.isItem ? store.itemPath(target.id) : _tagPath(widget.journal, target.id)}',
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  target.isItem
                      ? '替换原事项和全部旧标签，继承标签：${tags.isEmpty ? '无标签' : tags.map(store.tagName).join(' · ')}'
                      : '替换全部旧标签，保留现有事项关联。',
                  style: const TextStyle(fontSize: 16),
                ),
              ] else
                Text(
                  _items ? '可选择任意状态的历史事项。' : '选择要移入的标签。',
                  style: const TextStyle(fontSize: 16),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(),
              ),
            ),
          IconButton(
            tooltip: '取消移动',
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            icon: const Icon(Icons.close),
          ),
          IconButton.filled(
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            tooltip: '确认移动',
            onPressed: !_saving && _target != null ? _save : null,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
    );
  }
}
