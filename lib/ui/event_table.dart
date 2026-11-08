import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/journal_controller.dart';
import '../domain/event_stats.dart';
import '../domain/event_summary.dart';
import '../domain/model.dart';
import 'tag_chips.dart';
import 'obsidian_text.dart';

enum EventTableMode { summary, chronological }

typedef _TableEntry = ({
  Event? event,
  EventGroup? group,
  EventGroupKey? scope,
  bool nested,
});

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
    this.events,
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
  final List<Event>? events;
  @override
  State<EventTable> createState() => EventTableState();
}

class EventTableState extends State<EventTable> {
  final vertical = ScrollController();
  final horizontal = ScrollController();
  final _expanded = <EventGroupKey>{};
  EventTableMode get _mode => widget.mode;
  List<Event> get _rows => widget.events ?? widget.journal.rows;
  EventGroupKey? _editingScope;
  String? _editingEventId;
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

  /// Day-wide concurrency profile, built only when shared accounting is on.
  /// It covers every row of the day, so a tag sees the other tags that run
  /// in parallel with it instead of claiming the whole span.
  Map<String, Event>? _profileEvents;
  ConcurrencyProfile? _cachedProfile;
  ConcurrencyProfile? get _profile {
    if (!widget.journal.splitOverlap) return null;
    final day = widget.journal.day;
    final saved = widget.journal.store.events;
    final window = StatsWindow.days(day, day);
    if (_cachedProfile?.window != window || !mapEquals(_profileEvents, saved)) {
      _profileEvents = saved;
      _cachedProfile = ConcurrencyProfile.of(
        window,
        accountingEvents(saved.values),
      );
    }
    return _cachedProfile;
  }

  List<EventGroup> get _groups => eventGroups(
    _rows,
    widget.journal.day,
    draftIds: widget.journal.drafts.keys.toSet(),
    profile: _profile,
  );

  /// Both table modes use the same saved-event allocation. Draft clock
  /// lengths are previews and never reduce another event's credited time.
  Duration? _sharedDuration(Event event) {
    if (widget.journal.drafts.containsKey(event.id)) return null;
    final profile = _profile;
    if (profile == null) return null;
    if (event.intervalOn(widget.journal.day) == null) return null;
    return profile.durationOf([event]);
  }

  List<_TableEntry> get _entries {
    if (_mode == EventTableMode.chronological) {
      return [
        for (final event in _rows)
          (event: event, group: null, scope: null, nested: false),
      ];
    }
    return [
      for (final group in _groups)
        if (!group.hasSummary)
          (
            event: group.events.single,
            group: null,
            scope: group.key,
            nested: false,
          )
        else ...[
          (event: null, group: group, scope: group.key, nested: false),
          if (_expanded.contains(group.key))
            for (final event in group.events)
              (event: event, group: null, scope: group.key, nested: true),
        ],
    ];
  }

  Iterable<String> get selectionOrder =>
      _entries.map((entry) => entry.event?.id).nonNulls.toSet();

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
  Widget _tagCell(Event event) =>
      RecordTagChips(store: widget.journal.store, event: event);

  Widget _textCell(Event event, String label, int cell, bool selected) {
    final style = TextStyle(
      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
    );
    final source = widget.journal.store.items[event.itemId]?.source;
    final directory =
        source?.directory ?? widget.journal.settings.obsidianDirectory;
    if (_columns[cell] == EventColumn.title &&
        label.contains('[[') &&
        directory.isNotEmpty) {
      return ObsidianText(
        text: label,
        directory: directory,
        sourcePath: source?.path ?? '',
        selectable: false,
        maxLines: 1,
        style: style,
      );
    }
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Widget _eventRow(
    Event event,
    List<double> widths, {
    required bool nested,
    required EventGroupKey? scope,
    required bool primary,
  }) {
    final editorScope =
        (_editingEventId == widget.editorId ? _editingScope : null) ??
        _entries
            .where((entry) => entry.event?.id == widget.editorId)
            .firstOrNull
            ?.scope;
    final suffix = primary ? '' : '-${scope?.tagId ?? scope?.itemId ?? 'gap'}';
    final interval = event.intervalOn(widget.journal.day);
    final shared = _sharedDuration(event);
    final labels = [
      event.title.isEmpty ? '填写事件名称…' : event.title,
      _clock(event.start),
      event.end == null ? '待补全' : _clock(event.end!),
      widget.journal.store.ownerName(event),
      shared != null
          ? durationText(shared)
          : interval == null
          ? '—'
          : durationText(interval.duration),
    ];
    final selected = widget.journal.selected.contains(event.id);
    return GestureDetector(
      key: ValueKey('row-${event.id}$suffix'),
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
                        scope == editorScope &&
                        widget.editorColumn == _columns[cell] &&
                        widget.editor != null
                    ? widget.editor!
                    : GestureDetector(
                        key: ValueKey(
                          'cell-${event.id}-${_columns[cell]?.name ?? 'duration'}$suffix',
                        ),
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          _editingScope = scope;
                          _editingEventId = event.id;
                          widget.onCell(event.id, _columns[cell]);
                        },
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: nested && cell == 0 ? 32 : 8,
                              right: 8,
                            ),
                            child: _columns[cell] == EventColumn.tag
                                ? _tagCell(event)
                                : _textCell(
                                    event,
                                    labels[cell],
                                    cell,
                                    selected,
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
    final owner = group.key.itemId != null
        ? (id: group.key.itemId!, isItem: true)
        : group.key.tagId != null
        ? (id: group.key.tagId!, isItem: false)
        : null;
    final title = group.isUnclassified
        ? '未归类 / 空档'
        : widget.journal.store.ownerLabel(owner);
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
                  message: widget.journal.splitOverlap
                      ? '并行时段按同时进行的事件数平均分摊。'
                      : group.hasOverlap
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
                                    scope: entry.scope,
                                    primary: !entries
                                        .take(index)
                                        .any(
                                          (other) =>
                                              other.event?.id ==
                                              entry.event!.id,
                                        ),
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
