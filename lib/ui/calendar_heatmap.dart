import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../domain/calendar_activity.dart';
import '../domain/model.dart';
import 'pickers.dart';
import 'tag_visual.dart';
import 'theme.dart';

const allActivityTags = ActivityTagSelection.all();

/// A GitHub-style year grid. Its scale belongs to the selected tag and year.
class CalendarHeatmap extends StatefulWidget {
  const CalendarHeatmap({
    super.key,
    required this.journal,
    required this.selection,
    required this.onSelectionChanged,
    required this.onDaySelected,
  });

  final JournalController journal;
  final ActivityTagSelection selection;
  final ValueChanged<ActivityTagSelection> onSelectionChanged;
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<CalendarHeatmap> createState() => _CalendarHeatmapState();
}

class _CalendarHeatmapState extends State<CalendarHeatmap> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _tags = ScrollController();

  @override
  void didUpdateWidget(CalendarHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selection.ids.length > oldWidget.selection.ids.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tags.hasClients) {
          _tags.jumpTo(_tags.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = widget.journal;
    final store = journal.store;
    final selection = widget.selection;
    final tagId = selection.ids.length == 1 ? selection.ids.single : null;
    final activity = CalendarActivity.of(
      year: journal.day.year,
      events: store.events.values,
      where: (event) => selection.includes(event, store.tags),
      splitOverlap: journal.splitOverlap,
    );
    final family = tagId == null
        ? Colors.green
        : tagFamily(context, store, tagId);
    final scheme = Theme.of(context).colorScheme;
    String label(String? id) => id == null
        ? '未分类'
        : store.ancestors(id).map((tag) => tag.name).join(' / ');
    final name = selection.isAll ? '全部标签' : selection.ids.map(label).join('、');

    Widget chip(String? id) {
      final (fill, ink) = id == null
          ? (Colors.blueGrey[100]!, Colors.blueGrey[800]!)
          : tagSurfaceColors(
              tagFamily(context, store, id),
              tagDot(context, store, id),
              opacity: .20,
            );
      return InputChip(
        key: ValueKey(('activity-tag-chip', id)),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 100),
          child: Text(store.tagName(id), overflow: TextOverflow.ellipsis),
        ),
        backgroundColor: fill,
        labelStyle: TextStyle(color: ink),
        deleteIconColor: ink,
        side: BorderSide.none,
        tooltip: label(id),
        deleteButtonTooltipMessage: '移除${label(id)}',
        onDeleted: () => widget.onSelectionChanged(selection.remove(id)),
      );
    }

    Color color(int level) =>
        level == 0 ? scheme.surfaceContainerHighest : family[level * 100]!;

    final first = DateTime.utc(activity.year);
    final last = DateTime.utc(activity.year, 12, 31);
    final start = first.subtract(Duration(days: first.weekday - 1));
    final weeks = (last.difference(start).inDays + 1 + 6) ~/ 7;

    return Scrollbar(
      controller: _vertical,
      child: SingleChildScrollView(
        controller: _vertical,
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 16,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: selection.isAll
                        ? 240
                        : math.min(480, constraints.maxWidth),
                    child: Row(
                      children: [
                        SizedBox(
                          width: selection.isAll
                              ? 240
                              : math.min(240, constraints.maxWidth / 2),
                          child: TagSearchField(
                            key: const ValueKey('activity-tag-picker'),
                            store: store,
                            value: null,
                            clearAfterSelection: true,
                            excluded: selection.ids,
                            onChanged: (id) =>
                                widget.onSelectionChanged(selection.add(id)),
                          ),
                        ),
                        if (!selection.isAll)
                          Expanded(
                            child: SingleChildScrollView(
                              controller: _tags,
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.only(left: 8),
                              child: Row(
                                children: [
                                  for (final id in selection.ids)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: chip(id),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('activity-previous-year'),
                        tooltip: '上一年',
                        onPressed: activity.year <= 1
                            ? null
                            : () => widget.onDaySelected(
                                DateTime.utc(activity.year - 1),
                              ),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(
                        '${activity.year} 年',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      IconButton(
                        key: const ValueKey('activity-next-year'),
                        tooltip: '下一年',
                        onPressed: activity.year >= 9999
                            ? null
                            : () => widget.onDaySelected(
                                DateTime.utc(activity.year + 1),
                              ),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  Text(
                    '累计 ${durationText(activity.total)} · ${activity.activeDays} 个活跃日',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final pitch = ((constraints.maxWidth - 30) / weeks).clamp(
                  14.0,
                  22.0,
                );
                final width = math.max(
                  constraints.maxWidth,
                  30 + weeks * pitch,
                );
                return Scrollbar(
                  controller: _horizontal,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: width,
                      child: Column(
                        children: [
                          SizedBox(
                            height: 24,
                            child: Stack(
                              children: [
                                for (var month = 1; month <= 12; month++)
                                  Positioned(
                                    left:
                                        30 +
                                        DateTime.utc(
                                              activity.year,
                                              month,
                                            ).difference(start).inDays ~/
                                            7 *
                                            pitch,
                                    child: Text(
                                      '$month 月',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (var weekday = 0; weekday < 7; weekday++)
                            Row(
                              children: [
                                SizedBox(
                                  width: 30,
                                  height: pitch,
                                  child: Center(
                                    child: Text(
                                      '一二三四五六日'[weekday],
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ),
                                ),
                                for (var week = 0; week < weeks; week++)
                                  _cell(
                                    context,
                                    start.add(
                                      Duration(days: week * 7 + weekday),
                                    ),
                                    activity,
                                    pitch,
                                    color,
                                    name,
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  activity.activeDays == 0
                      ? '本年暂无已完成记录'
                      : '单日峰值 ${durationText(activity.maximum)}',
                  key: const ValueKey('activity-peak'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('少'),
                    const SizedBox(width: 6),
                    for (var level = 0; level <= 9; level++)
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: color(level),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    const Text('多'),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    DateTime day,
    CalendarActivity activity,
    double pitch,
    Color Function(int) color,
    String name,
  ) {
    if (day.year != activity.year) return SizedBox(width: pitch, height: pitch);
    final selected = day == widget.journal.day;
    final message =
        '${dateText(day)} · $name\n${durationText(activity.on(day))}';
    return SizedBox(
      width: pitch,
      height: pitch,
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Tooltip(
          message: message,
          child: Semantics(
            label: message,
            selected: selected,
            button: true,
            onTap: () => widget.onDaySelected(day),
            excludeSemantics: true,
            child: Material(
              key: ValueKey('activity-day-${dateText(day)}'),
              color: color(activity.level(activity.on(day))),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
                side: BorderSide(
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.outlineVariant,
                  width: selected ? 2 : .5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: () => widget.onDaySelected(day)),
            ),
          ),
        ),
      ),
    );
  }
}
