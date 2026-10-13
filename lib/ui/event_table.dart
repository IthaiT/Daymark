import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/journal_controller.dart';
import '../domain/event_summary.dart';
import '../domain/model.dart';
import 'theme.dart';

enum EventTableMode { summary, chronological }

typedef _TableEntry = ({Event? event, EventGroup? group, bool nested});

class EventTable extends StatefulWidget {
  const EventTable({
    super.key,
    required this.journal,
    required this.onCell,
    required this.onBlank,
    required this.onAdd,
    required this.onContext,
    required this.beforeScroll,
    required this.mode,
    this.editorId,
    this.editorColumn,
    this.editor,
  });
  final JournalController journal;
  final EventTableMode mode;
  final void Function(String, EventColumn?) onCell;
  final VoidCallback onBlank;
  final VoidCallback onAdd;
  final void Function(Offset, String) onContext;
  final Future<bool> Function() beforeScroll;
  final String? editorId;
  final EventColumn? editorColumn;
  final Widget? editor;
  @override
  State<EventTable> createState() => EventTableState();
}

class EventTableState extends State<EventTable> {
  final vertical = ScrollController();
  final horizontal = ScrollController();
  final _expanded = <EventGroupKey>{};
  EventTableMode get _mode => widget.mode;
  Map<String, Event?> _lastSelection = {};
  late DateTime _day = widget.journal.day;
  static const _rowHeight = 40.0;
  static const _columns = <EventColumn?>[
    EventColumn.title,
    EventColumn.start,
    EventColumn.end,
    EventColumn.tag,
    null,
  ];

  List<EventGroup> get _groups => eventGroups(
    widget.journal.rows,
    widget.journal.day,
    draftIds: widget.journal.drafts.keys.toSet(),
  );
  List<_TableEntry> get _entries {
    if (_mode == EventTableMode.chronological) {
      return [
        for (final event in widget.journal.rows)
          (event: event, group: null, nested: false),
      ];
    }
    return [
      for (final group in _groups)
        if (!group.hasSummary)
          (event: group.events.single, group: null, nested: false)
        else ...[
          (event: null, group: group, nested: false),
          if (_expanded.contains(group.key))
            for (final event in group.events)
              (event: event, group: null, nested: true),
        ],
    ];
  }

  Iterable<String> get selectionOrder =>
      _entries.map((entry) => entry.event?.id).nonNulls;

  @override
  void didUpdateWidget(EventTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final modeChanged = oldWidget.mode != widget.mode;
    if (_day != widget.journal.day) {
      _day = widget.journal.day;
      _expanded.clear();
      _lastSelection = {};
    }
    final selected = widget.journal.selected;
    final newlySelected = selected
        .where((id) => _lastSelection[id] != widget.journal.event(id))
        .toSet();
    _lastSelection = {for (final id in selected) id: widget.journal.event(id)};
    for (final group in _groups) {
      if (group.events.any(
        (event) =>
            newlySelected.contains(event.id) ||
            event.id == widget.editorId ||
            modeChanged && selected.contains(event.id),
      )) {
        _expanded.add(group.key);
      }
    }
    final revealId =
        newlySelected.firstOrNull ??
        (modeChanged ? selected.firstOrNull : null);
    if (modeChanged || revealId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (modeChanged && vertical.hasClients) {
          vertical.jumpTo(0);
        }
        if (revealId != null) {
          reveal(revealId);
        }
      });
    }
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (
      signal,
    ) async {
      if (!await widget.beforeScroll() || !mounted) return;
      final pointer = signal as PointerScrollEvent;
      final scroll =
          HardwareKeyboard.instance.isShiftPressed ||
              pointer.scrollDelta.dy == 0
          ? horizontal
          : vertical;
      if (scroll.hasClients) {
        final delta = pointer.scrollDelta.dy != 0
            ? pointer.scrollDelta.dy
            : pointer.scrollDelta.dx;
        scroll.jumpTo(
          (scroll.offset + delta).clamp(0.0, scroll.position.maxScrollExtent),
        );
      }
    });
  }

  @override
  void dispose() {
    vertical.dispose();
    horizontal.dispose();
    super.dispose();
  }

  void reveal(String id) {
    if (_mode == EventTableMode.summary) {
      final group = _groups
          .where((group) => group.events.any((event) => event.id == id))
          .firstOrNull;
      if (group != null && group.hasSummary && !_expanded.contains(group.key)) {
        setState(() => _expanded.add(group.key));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) reveal(id);
        });
        return;
      }
    }
    final index = _entries.indexWhere((entry) => entry.event?.id == id);
    if (index < 0 || !vertical.hasClients) return;
    final top = index * _rowHeight;
    final bottom = top + _rowHeight;
    if (top < vertical.offset) {
      vertical.jumpTo(top.clamp(0.0, vertical.position.maxScrollExtent));
    } else if (bottom > vertical.offset + vertical.position.viewportDimension) {
      vertical.jumpTo(
        (bottom - vertical.position.viewportDimension).clamp(
          0.0,
          vertical.position.maxScrollExtent,
        ),
      );
    }
  }

  Future<void> _toggle(EventGroup group) async {
    if (!await widget.beforeScroll() || !mounted) return;
    setState(() {
      if (!_expanded.add(group.key)) _expanded.remove(group.key);
    });
  }

  String _clock(DateTime value) => dayStart(value) == widget.journal.day
      ? clockText(value)
      : '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')} ${clockText(value)}';
  Widget _tagCell(Event event) {
    final (background, foreground) = eventColors(widget.journal.store, event);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        widget.journal.store.tagName(event.tagId),
        maxLines: 1,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _eventRow(Event event, List<double> widths, {required bool nested}) {
    final interval = event.intervalOn(widget.journal.day);
    final labels = [
      event.title.isEmpty ? '填写事件名称…' : event.title,
      _clock(event.start),
      event.end == null ? '待补全' : _clock(event.end!),
      widget.journal.store.tagName(event.tagId),
      interval == null ? '—' : durationText(interval.duration),
    ];
    final selected = widget.journal.selected.contains(event.id);
    return GestureDetector(
      key: ValueKey('row-${event.id}'),
      onSecondaryTapDown: (details) =>
          widget.onContext(details.globalPosition, event.id),
      child: ColoredBox(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        child: Row(
          children: [
            for (var cell = 0; cell < labels.length; cell++)
              SizedBox(
                width: widths[cell],
                height: _rowHeight,
                child:
                    widget.editorId == event.id &&
                        widget.editorColumn == _columns[cell] &&
                        widget.editor != null
                    ? widget.editor!
                    : GestureDetector(
                        key: ValueKey(
                          'cell-${event.id}-${_columns[cell]?.name ?? 'duration'}',
                        ),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onCell(event.id, _columns[cell]),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: nested && cell == 0 ? 32 : 8,
                              right: 8,
                            ),
                            child: _columns[cell] == EventColumn.tag
                                ? _tagCell(event)
                                : Text(
                                    labels[cell],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: selected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                          ),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(EventGroup group, List<double> widths) {
    final title = group.isUnclassified
        ? '未分类 / 未定义'
        : widget.journal.store.tagName(group.key.tagId);
    final expanded = _expanded.contains(group.key);
    final selected = group.events
        .where((event) => widget.journal.selected.contains(event.id))
        .length;
    final scheme = Theme.of(context).colorScheme;
    final duration = group.incompleteCount == group.events.length
        ? '—'
        : durationText(group.duration);
    return Material(
      key: group.isUnclassified
          ? const ValueKey('group-unclassified')
          : ValueKey(('event-group', group.key)),
      color: selected > 0
          ? scheme.secondaryContainer
          : scheme.surfaceContainerLow,
      child: InkWell(
        onTap: () => unawaited(_toggle(group)),
        child: SizedBox(
          height: _rowHeight,
          child: Row(
            children: [
              SizedBox(
                width: widths[0],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Icon(
                        expanded ? Icons.expand_more : Icons.chevron_right,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${group.events.length} 条',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: widths[1],
                child: Text(
                  expanded ? '分段明细' : '展开查看',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(
                width: widths[2],
                child: Text(
                  selected > 0
                      ? '已选 $selected 条'
                      : group.incompleteCount > 0
                      ? '${group.incompleteCount} 条待补全'
                      : '',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(
                width: widths[3],
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _tagCell(group.events.first),
                  ),
                ),
              ),
              SizedBox(
                width: widths[4],
                child: Tooltip(
                  message: group.hasOverlap
                      ? '仅累计当天用时，重叠时段只计一次。'
                      : '累计每段在当天的用时。',
                  child: Text(
                    duration,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.max(770.0, constraints.maxWidth);
      final extra = (width - 770) / 2;
      final widths = [240 + extra, 110.0, 110.0, 180 + extra, 130.0];
      final entries = _entries;
      return Listener(
        onPointerSignal: _wheel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onBlank,
          child: Scrollbar(
            controller: horizontal,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: horizontal,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: SizedBox(
                width: width,
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: vertical,
                        child: ListView.builder(
                          controller: vertical,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: entries.length + 1,
                          itemBuilder: (context, index) {
                            if (index == entries.length) {
                              return GestureDetector(
                                key: const ValueKey('table-blank'),
                                behavior: HitTestBehavior.opaque,
                                onTap: widget.onBlank,
                                onDoubleTap: widget.onAdd,
                                child: SizedBox(
                                  height: math.max(
                                    _rowHeight,
                                    constraints.maxHeight -
                                        entries.length * _rowHeight,
                                  ),
                                ),
                              );
                            }
                            final entry = entries[index];
                            return entry.group != null
                                ? _summaryRow(entry.group!, widths)
                                : _eventRow(
                                    entry.event!,
                                    widths,
                                    nested: entry.nested,
                                  );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
