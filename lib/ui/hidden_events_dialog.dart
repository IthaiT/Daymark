import 'dart:math' as math;

import 'package:flutter/material.dart' hide Interval;

import '../data/store.dart';
import '../domain/model.dart';

Future<void> showHiddenEventsDialog(
  BuildContext context, {
  required Store store,
  required DateTime day,
  required List<Event> events,
  Interval? within,
}) => showDialog<void>(
  context: context,
  builder: (_) => _HiddenEventsDialog(
    store: store,
    day: day,
    events: events,
    within: within,
  ),
);

class _HiddenEventsDialog extends StatefulWidget {
  const _HiddenEventsDialog({
    required this.store,
    required this.day,
    required this.events,
    this.within,
  });
  final Store store;
  final DateTime day;
  final List<Event> events;
  final Interval? within;

  @override
  State<_HiddenEventsDialog> createState() => _HiddenEventsDialogState();
}

class _HiddenEventsDialogState extends State<_HiddenEventsDialog> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  DataCell _textCell(String value, double width) => DataCell(
    ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Tooltip(
        message: value,
        child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ),
  );

  String _tag(Event event) => event.tagId == null
      ? '未分类'
      : widget.store.ancestors(event.tagId!).map((tag) => tag.name).join(' / ');

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final within = widget.within;
    final notes = widget.events.any((event) => event.notes.isNotEmpty);
    final range = within == null
        ? dateText(widget.day)
        : '${clockText(within.start)} — ${within.end == dayEnd(widget.day) ? '24:00' : clockText(within.end)} · ${durationText(within.duration)}';
    return AlertDialog(
      key: const ValueKey('hidden-events-dialog'),
      title: Text(within == null ? '隐藏的事项' : '折叠时段的事项'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(1040, math.max(280, viewport.width - 128)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$range · ${widget.events.length} 条记录'),
            const SizedBox(height: 12),
            if (widget.events.isEmpty)
              Text(within == null ? '当前没有隐藏的事项。' : '此时段没有隐藏记录。')
            else
              Scrollbar(
                controller: _horizontal,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.min(
                        440,
                        math.max(100, viewport.height - 300),
                      ),
                    ),
                    child: Scrollbar(
                      controller: _vertical,
                      child: SingleChildScrollView(
                        controller: _vertical,
                        child: DataTable(
                          columnSpacing: 20,
                          horizontalMargin: 12,
                          headingRowHeight: 40,
                          dataRowMinHeight: 44,
                          dataRowMaxHeight: 44,
                          columns: [
                            const DataColumn(label: Text('名称')),
                            const DataColumn(label: Text('标签')),
                            const DataColumn(label: Text('开始时间')),
                            const DataColumn(label: Text('结束时间')),
                            const DataColumn(
                              label: Text('本日用时'),
                              numeric: true,
                            ),
                            if (notes) const DataColumn(label: Text('备注')),
                          ],
                          rows: [
                            for (final event in widget.events)
                              DataRow(
                                key: ValueKey('hidden-event-${event.id}'),
                                cells: [
                                  _textCell(
                                    event.title.isEmpty ? '未命名' : event.title,
                                    200,
                                  ),
                                  _textCell(_tag(event), 140),
                                  DataCell(
                                    Text(
                                      timestampText(
                                        event.start,
                                      ).replaceFirst('T', ' '),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      event.end == null
                                          ? '待补全'
                                          : timestampText(
                                              event.end!,
                                            ).replaceFirst('T', ' '),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      event.intervalOn(widget.day) == null
                                          ? '待补全'
                                          : durationText(
                                              event
                                                  .intervalOn(widget.day)!
                                                  .duration,
                                            ),
                                    ),
                                  ),
                                  if (notes) _textCell(event.notes, 200),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
