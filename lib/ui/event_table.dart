import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/journal_controller.dart';
import '../domain/model.dart';
import 'theme.dart';

class EventTable extends StatefulWidget {
  const EventTable({
    super.key,
    required this.journal,
    required this.onCell,
    required this.onBlank,
    required this.onAdd,
    required this.onContext,
    required this.beforeScroll,
    this.editorId,
    this.editorColumn,
    this.editor,
  });
  final JournalController journal;
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
    final index = widget.journal.rows.indexWhere((row) => row.id == id);
    if (index < 0 || !vertical.hasClients) return;
    final top = index * 40.0;
    final bottom = top + 40;
    if (top < vertical.offset) {
      vertical.jumpTo(top);
    } else if (bottom > vertical.offset + vertical.position.viewportDimension) {
      vertical.jumpTo(
        (bottom - vertical.position.viewportDimension).clamp(
          0.0,
          vertical.position.maxScrollExtent,
        ),
      );
    }
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.max(770.0, constraints.maxWidth);
      final extra = (width - 770) / 2;
      final widths = [240 + extra, 110.0, 110.0, 180 + extra, 130.0];
      final rows = widget.journal.rows;
      final columns = <EventColumn?>[
        EventColumn.title,
        EventColumn.start,
        EventColumn.end,
        EventColumn.tag,
        null,
      ];
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
                    SizedBox(
                      height: 40,
                      child: Row(
                        children: [
                          for (final (index, label) in [
                            '事件',
                            '开始',
                            '结束',
                            '标签',
                            '本日用时',
                          ].indexed)
                            SizedBox(
                              width: widths[index],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(label),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Scrollbar(
                        controller: vertical,
                        child: ListView.builder(
                          controller: vertical,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rows.length + 1,
                          itemBuilder: (context, index) {
                            if (index == rows.length) {
                              return GestureDetector(
                                key: const ValueKey('table-blank'),
                                behavior: HitTestBehavior.opaque,
                                onTap: widget.onBlank,
                                onDoubleTap: widget.onAdd,
                                child: SizedBox(
                                  height: math.max(
                                    40.0,
                                    constraints.maxHeight -
                                        41 -
                                        rows.length * 40,
                                  ),
                                ),
                              );
                            }
                            final event = rows[index];
                            final interval = event.intervalOn(
                              widget.journal.day,
                            );
                            final labels = [
                              event.title.isEmpty ? '填写事件名称…' : event.title,
                              _clock(event.start),
                              event.end == null ? '待补全' : _clock(event.end!),
                              widget.journal.store.tagName(event.tagId),
                              interval == null
                                  ? '—'
                                  : durationText(interval.duration),
                            ];
                            final selected = widget.journal.selected.contains(
                              event.id,
                            );
                            return GestureDetector(
                              key: ValueKey('row-${event.id}'),
                              onSecondaryTapDown: (details) => widget.onContext(
                                details.globalPosition,
                                event.id,
                              ),
                              child: ColoredBox(
                                color: selected
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer
                                    : Colors.transparent,
                                child: Row(
                                  children: [
                                    for (
                                      var cell = 0;
                                      cell < labels.length;
                                      cell++
                                    )
                                      SizedBox(
                                        width: widths[cell],
                                        height: 40,
                                        child:
                                            widget.editorId == event.id &&
                                                widget.editorColumn ==
                                                    columns[cell] &&
                                                widget.editor != null
                                            ? widget.editor!
                                            : GestureDetector(
                                                key: ValueKey(
                                                  'cell-${event.id}-${columns[cell]?.name ?? 'duration'}',
                                                ),
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap: () => widget.onCell(
                                                  event.id,
                                                  columns[cell],
                                                ),
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                        ),
                                                    child:
                                                        columns[cell] ==
                                                            EventColumn.tag
                                                        ? _tagCell(event)
                                                        : Text(
                                                            labels[cell],
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  selected
                                                                  ? FontWeight
                                                                        .bold
                                                                  : FontWeight
                                                                        .normal,
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
