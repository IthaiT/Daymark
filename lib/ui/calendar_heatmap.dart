import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../domain/calendar_activity.dart';
import '../domain/model.dart';
import 'theme.dart';

typedef ActivityTag = ({String? id, bool unclassified});
const allActivityTags = (id: null, unclassified: false);

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
  final ActivityTag selection;
  final ValueChanged<ActivityTag> onSelectionChanged;
  final ValueChanged<DateTime> onDaySelected;

  @override
  State<CalendarHeatmap> createState() => _CalendarHeatmapState();
}

class _CalendarHeatmapState extends State<CalendarHeatmap> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = widget.journal;
    final store = journal.store;
    final selection = widget.selection;
    final tagId = selection.id;
    final ids = tagId == null ? null : store.descendants(tagId);
    final activity = CalendarActivity.of(
      year: journal.day.year,
      events: store.events.values,
      where: (event) => selection.unclassified
          ? event.tagId == null
          : ids == null || ids.contains(event.tagId),
      splitOverlap: journal.splitOverlap,
    );
    final family = tagId == null
        ? Colors.green
        : tagFamily(context, store, tagId);
    final scheme = Theme.of(context).colorScheme;
    final name = selection.unclassified
        ? '未分类'
        : tagId == null
        ? '全部标签'
        : store.ancestors(tagId).map((tag) => tag.name).join(' / ');

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
            Wrap(
              spacing: 16,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: DropdownButton<ActivityTag>(
                    key: const ValueKey('activity-tag-picker'),
                    value: selection,
                    isExpanded: true,
                    menuMaxHeight: 360,
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem(
                        value: allActivityTags,
                        child: Text('全部标签'),
                      ),
                      const DropdownMenuItem(
                        value: (id: null, unclassified: true),
                        child: Text('未分类'),
                      ),
                      for (final tag in store.orderedTags())
                        DropdownMenuItem(
                          value: (id: tag.id, unclassified: false),
                          child: Text(
                            store
                                .ancestors(tag.id)
                                .map((tag) => tag.name)
                                .join(' / '),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) widget.onSelectionChanged(value);
                    },
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
            const SizedBox(height: 8),
            Text(
              '颜色按当前标签本年峰值动态调整；父标签包含子标签。${journal.splitOverlap ? '重叠时段按设置均分。' : '重叠时段只计一次。'}悬停查看时长，点击查看当天记录。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
