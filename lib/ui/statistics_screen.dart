import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../data/store.dart';
import '../domain/event_stats.dart';
import '../domain/model.dart';
import 'dialogs.dart' show errorText;
import 'pickers.dart' show TagField;
import 'theme.dart' show tagDot;
import 'workspace_style.dart';

/// A read-only reporting workspace. It reads the journal and never changes the
/// selected day, the timeline or the event table of the recording page.
class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key, required this.journal});
  final JournalController journal;
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

enum _StatsPeriod { week, month, custom }

const _unclassifiedId = '__stats_unclassified__';
const _undefinedId = '__stats_undefined__';
const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

class _StatisticsScreenState extends State<StatisticsScreen> {
  late DateTime _from;
  late DateTime _to;
  _StatsPeriod _period = _StatsPeriod.week;
  String? _selectedId;
  final _expanded = <String>{};
  final _hidden = <String>{};
  final _selectedEvents = <String>{};
  final _tableScroll = ScrollController();
  final _eventScroll = ScrollController();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _setWeek();
  }

  @override
  void dispose() {
    _tableScroll.dispose();
    _eventScroll.dispose();
    super.dispose();
  }

  DateTime get _today => dayStart(civilTime(widget.journal.clock()));
  DateTime get _currentWeekStart =>
      _today.subtract(Duration(days: _today.weekday - 1));
  DateTime get _currentMonthStart => DateTime.utc(_today.year, _today.month);

  void _setWeek() {
    _from = _currentWeekStart;
    _to = _from.add(const Duration(days: 6));
  }

  void _setMonth() {
    _from = _currentMonthStart;
    _to = _today;
  }

  bool get _canNext => switch (_period) {
    _StatsPeriod.week => _from.isBefore(_currentWeekStart),
    _StatsPeriod.month => _from.isBefore(_currentMonthStart),
    _StatsPeriod.custom => _to.isBefore(_today),
  };

  String get _periodWord => switch (_period) {
    _StatsPeriod.week => '本周',
    _StatsPeriod.month => '本月',
    _StatsPeriod.custom => '区间',
  };

  String get _compositionTitle => switch (_period) {
    _StatsPeriod.week => '本周构成',
    _StatsPeriod.month => '本月构成',
    _StatsPeriod.custom => '区间构成',
  };

  String get _deltaLabel => switch (_period) {
    _StatsPeriod.week => '较上周',
    _StatsPeriod.month => '较上月',
    _StatsPeriod.custom => '较上期',
  };

  int get _days => _to.difference(_from).inDays + 1;

  String get _rangeText {
    final start = '${_from.month}月${_from.day}日';
    final end = '${_to.month}月${_to.day}日';
    return _from.year == _to.year
        ? '$start – $end'
        : '${_from.year}年$start – ${_to.year}年$end';
  }

  void _changePeriod(_StatsPeriod next) {
    if (next == _period) return;
    if (next == _StatsPeriod.custom) {
      _pickRange();
      return;
    }
    setState(() {
      _period = next;
      _editing = false;
      _selectedEvents.clear();
      if (next == _StatsPeriod.week) {
        _setWeek();
      } else {
        _setMonth();
      }
    });
  }

  void _shift(int direction) {
    if (direction > 0 && !_canNext) return;
    final today = _today;
    setState(() {
      _editing = false;
      _selectedEvents.clear();
      switch (_period) {
        case _StatsPeriod.week:
          _from = _from.add(Duration(days: direction * 7));
          _to = _to.add(Duration(days: direction * 7));
        case _StatsPeriod.month:
          if (direction < 0) {
            final previous = DateTime.utc(_from.year, _from.month - 1);
            _from = previous;
            _to = DateTime.utc(previous.year, previous.month + 1, 0);
          } else {
            final next = DateTime.utc(_from.year, _from.month + 1);
            if (next.isAfter(_currentMonthStart)) return;
            _from = next;
            _to = next.year == today.year && next.month == today.month
                ? today
                : DateTime.utc(next.year, next.month + 1, 0);
          }
        case _StatsPeriod.custom:
          final length = _to.difference(_from).inDays + 1;
          _from = _from.add(Duration(days: direction * length));
          _to = _to.add(Duration(days: direction * length));
      }
    });
  }

  DateTime _localDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  Future<void> _pickRange() async {
    final today = _today;
    final end = _to.isAfter(today) ? today : _to;
    final start = _from.isAfter(end) ? end : _from;
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: _localDate(today),
      initialDateRange: DateTimeRange(
        start: _localDate(start),
        end: _localDate(end),
      ),
      helpText: '选择统计区间',
      saveText: '应用',
    );
    if (result == null || !mounted) return;
    setState(() {
      _from = dayStart(civilTime(result.start));
      _to = dayStart(civilTime(result.end));
      _period = _StatsPeriod.custom;
      _editing = false;
      _selectedEvents.clear();
    });
  }

  void _applyWeek(DateTime monday) {
    setState(() {
      _from = monday;
      _to = monday.add(const Duration(days: 6));
      _period = _StatsPeriod.custom;
      _editing = false;
      _selectedEvents.clear();
    });
  }

  String _rootIdOf(_StatsModel model, _StatsNode node) {
    var current = node;
    while (current.parentId != null) {
      final parent = model.nodes[current.parentId];
      if (parent == null) break;
      current = parent;
    }
    return current.id;
  }

  _StatsNode? _resolveSelected(_StatsModel model) {
    final stored = _selectedId == null ? null : model.nodes[_selectedId];
    if (stored != null && !_hidden.contains(_rootIdOf(model, stored))) {
      return stored;
    }
    final visible = model.roots
        .where((root) => !_hidden.contains(root.id))
        .toList();
    if (visible.isEmpty) return null;
    for (final root in visible) {
      if (!root.isGap && !root.isUnclassified) return root;
    }
    return visible.first;
  }

  void _select(_StatsModel model, _StatsNode node) {
    setState(() {
      _selectedId = node.id;
      _editing = false;
      _selectedEvents.clear();
      var parent = node.parentId;
      while (parent != null) {
        _expanded.add(parent);
        parent = widget.journal.store.tags[parent]?.parentId;
      }
      if (node.children.any((child) => child.duration > Duration.zero)) {
        _expanded.add(node.id);
      }
    });
  }

  void _toggleExpanded(String id) {
    setState(() {
      if (!_expanded.add(id)) _expanded.remove(id);
    });
  }

  void _toggleHidden(String id) {
    setState(() {
      if (!_hidden.add(id)) {
        _hidden.remove(id);
      }
      _editing = false;
      _selectedEvents.clear();
    });
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(errorText(error)),
          behavior: SnackBarBehavior.floating,
          width: 480,
          showCloseIcon: true,
        ),
      );
  }

  Future<void> _moveSelected(_StatsNode node) async {
    if (_selectedEvents.isEmpty) return;
    final store = widget.journal.store;
    final ids = {..._selectedEvents};
    final initial = node.isGap || node.isUnclassified ? null : node.id;
    final result = await showDialog<(bool, String?)>(
      context: context,
      builder: (_) => _MoveTargetDialog(
        store: store,
        count: ids.length,
        initialTarget: initial,
      ),
    );
    if (result == null || !result.$1 || !mounted) return;
    try {
      await widget.journal.setEventTag(ids, result.$2);
      if (!mounted) return;
      setState(() {
        _editing = false;
        _selectedEvents.clear();
      });
      final name = result.$2 == null ? '未分类' : store.tagName(result.$2);
      ScaffoldMessenger.of(context)
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已移动 ${ids.length} 条事件到「$name」'),
            behavior: SnackBarBehavior.floating,
            width: 480,
          ),
        );
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.journal,
    builder: (context, _) {
      final model = _buildModel(context);
      final selected = _resolveSelected(model);
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(constraints.maxWidth, 1080.0);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Padding(
                padding: WorkspaceStyle.padding,
                child: Column(
                  children: [
                    _header(context),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _composition(context, model),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _tagTable(context, model, selected),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 372,
                            child: _detail(context, model, selected),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Text('统计', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 16),
          AppSegmentedButton<_StatsPeriod>(
            segments: const [
              ButtonSegment(value: _StatsPeriod.week, label: Text('周')),
              ButtonSegment(value: _StatsPeriod.month, label: Text('月')),
              ButtonSegment(value: _StatsPeriod.custom, label: Text('自定义')),
            ],
            selected: {_period},
            onSelectionChanged: (values) => _changePeriod(values.single),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: '上一段',
            onPressed: () => _shift(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          TextButton(
            key: const ValueKey('stats-range'),
            onPressed: _pickRange,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_rangeText),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _period == _StatsPeriod.custom ? '$_days 天' : _periodWord,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '下一段',
            onPressed: _canNext ? () => _shift(1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _composition(BuildContext context, _StatsModel model) {
    final scheme = Theme.of(context).colorScheme;
    final visible = model.roots
        .where((root) => !_hidden.contains(root.id))
        .toList();
    final total = visible.fold(
      Duration.zero,
      (sum, node) => sum + node.duration,
    );
    return WorkspacePanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _compositionTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 9),
          if (visible.isEmpty)
            Container(
              height: 38,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(4),
              ),
            )
          else
            SizedBox(
              height: 38,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < visible.length; index++) ...[
                    if (index > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: math.max(1, visible[index].duration.inMinutes),
                      child: InkWell(
                        onTap: () => _toggleHidden(visible[index].id),
                        borderRadius: BorderRadius.circular(4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: visible[index].color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          _legend(context, model),
          if (_hidden.isNotEmpty) ...[
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '已隐藏 ${_hidden.length} 项 · 当前 ${_compact(total)}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _hidden.clear()),
                  child: const Text('恢复全部'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, _StatsModel model) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.max(120.0, (constraints.maxWidth - 36) / 4);
      return Wrap(
        spacing: 12,
        runSpacing: 1,
        children: [
          for (final root in model.roots)
            SizedBox(
              width: width,
              child: InkWell(
                onTap: () => _toggleHidden(root.id),
                borderRadius: BorderRadius.circular(5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: Opacity(
                    opacity: _hidden.contains(root.id) ? .35 : 1,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: root.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            root.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  decoration: _hidden.contains(root.id)
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _tagTable(
    BuildContext context,
    _StatsModel model,
    _StatsNode? selected,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <(_StatsNode, int)>[];
    void walk(_StatsNode node, int depth) {
      rows.add((node, depth));
      if (_expanded.contains(node.id)) {
        for (final child in node.children.where(
          (child) => child.duration > Duration.zero,
        )) {
          walk(child, depth + 1);
        }
      }
    }

    for (final root in model.roots.where(
      (root) => !_hidden.contains(root.id),
    )) {
      walk(root, 0);
    }
    return WorkspacePanel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Text('标签明细', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(width: 33),
                Expanded(
                  child: Text(
                    '标签',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 82,
                  child: Text(
                    '时长',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 124,
                  child: Text(
                    '占比',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    _deltaLabel,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 9),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      _hidden.isEmpty ? '当前区间没有记录' : '所有类别已隐藏',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _tableScroll,
                    child: ListView.builder(
                      controller: _tableScroll,
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final (node, depth) = rows[index];
                        return _tagRow(
                          context,
                          model,
                          node,
                          depth,
                          selected?.id == node.id,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tagRow(
    BuildContext context,
    _StatsModel model,
    _StatsNode node,
    int depth,
    bool active,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final total = node.parentId == null
        ? model.visibleTotal
        : model.nodes[node.parentId]?.duration ?? Duration.zero;
    final share = _percent(node.duration, total);
    final delta = node.duration - node.previous;
    final children = node.children.where(
      (child) => child.duration > Duration.zero,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: .07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _select(model, node),
          child: SizedBox(
            height: 30,
            child: Row(
              children: [
                SizedBox(width: 8 + depth * 14.0),
                SizedBox(
                  width: 18,
                  child: children.isEmpty
                      ? null
                      : InkWell(
                          onTap: () => _toggleExpanded(node.id),
                          borderRadius: BorderRadius.circular(4),
                          child: Icon(
                            _expanded.contains(node.id)
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: node.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
                  ),
                ),
                SizedBox(
                  width: 82,
                  child: Text(
                    _compact(node.duration),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 124,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 58,
                        height: 4,
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: (share / 100).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: node.color,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '$share%',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    delta == Duration.zero
                        ? '—'
                        : '${delta.isNegative ? '↓' : '↑'} ${_compact(delta)}',
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: delta.isNegative
                          ? scheme.error
                          : delta == Duration.zero
                          ? scheme.onSurfaceVariant
                          : scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, _StatsModel model, _StatsNode? node) {
    if (node == null) {
      return WorkspacePanel(
        child: Center(
          child: Text(
            '所有类别已隐藏',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final events = eventsIn(model.window, node.events);
    final kids = node.children
        .where((child) => child.duration > Duration.zero)
        .toList();
    final editable = node.canEdit && events.isNotEmpty;
    return WorkspacePanel(
      child: Column(
        children: [
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: _detailTop(context, model, node, kids),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 10, 4),
            child: Row(
              children: [
                Text(
                  '事件 ${events.length} 条 · $_periodWord',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (editable)
                  TextButton(
                    onPressed: () => setState(() {
                      _editing = !_editing;
                      if (!_editing) _selectedEvents.clear();
                    }),
                    child: Text(_editing ? '完成' : '编辑'),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: events.isEmpty
                ? Center(
                    child: Text(
                      '没有事件',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _eventScroll,
                    child: ListView.builder(
                      controller: _eventScroll,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                      itemCount: events.length,
                      itemBuilder: (context, index) =>
                          _eventRow(context, events[index]),
                    ),
                  ),
          ),
          if (_editing) _selectionBar(context, node),
        ],
      ),
    );
  }

  Widget _detailTop(
    BuildContext context,
    _StatsModel model,
    _StatsNode node,
    List<_StatsNode> kids,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isChild = node.parentId != null;
    final parent = isChild ? model.nodes[node.parentId] : null;
    final total = isChild
        ? parent?.duration ?? Duration.zero
        : model.visibleTotal;
    final share = _percent(node.duration, total);
    final delta = node.duration - node.previous;
    final scope = isChild
        ? '占 ${parent?.name ?? ''} $share%'
        : '占${_hidden.isEmpty ? _periodWord : '当前视图'} $share%';
    final direct = kids.isEmpty
        ? Duration.zero
        : durationIn(model.window, node.directEvents);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '全部标签${isChild ? ' › ${_pathOf(model, node)}' : ' › ${node.name}'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: node.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _compact(node.duration),
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 1),
        Text(
          '$scope · ${delta == Duration.zero ? '—' : '${delta.isNegative ? '−' : '+'}${_compact(delta)}'}',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (kids.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Text('构成', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Text(
                '${kids.length} 个子标签',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 10,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (direct > Duration.zero) ...[
                  Expanded(
                    flex: math.max(1, direct.inMinutes),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: node.color.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (kids.isNotEmpty) const SizedBox(width: 2),
                ],
                for (var index = 0; index < kids.length; index++) ...[
                  if (index > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: math.max(1, kids[index].duration.inMinutes),
                    child: GestureDetector(
                      onTap: () => _select(model, kids[index]),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: kids[index].color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 7),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(100.0, (constraints.maxWidth - 12) / 2);
              return Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  if (direct > Duration.zero)
                    SizedBox(
                      width: width,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: node.color.withValues(alpha: .5),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '直接记录',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                            Text(
                              _compact(direct),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  for (final kid in kids)
                    SizedBox(
                      width: width,
                      child: InkWell(
                        onTap: () => _select(model, kid),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: kid.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  kid.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ),
                              Text(
                                _compact(kid.duration),
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 14),
        Text('时段分布', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        _heatmap(context, model.window, node),
        const SizedBox(height: 14),
        Row(
          children: [
            Text('近 8 周', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text(
              _periodWord,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _trend(context, model.window, node),
      ],
    );
  }

  String _pathOf(_StatsModel model, _StatsNode node) {
    final names = <String>[];
    var current = node;
    while (true) {
      names.add(current.name);
      final parent = current.parentId;
      if (parent == null) break;
      current = model.nodes[parent] ?? current;
      if (current.id == node.id) break;
    }
    return names.reversed.join(' › ');
  }

  Widget _heatmap(BuildContext context, StatsWindow window, _StatsNode node) {
    final scheme = Theme.of(context).colorScheme;
    final grid = heatGrid(window, node.events);
    var maxMinutes = 0;
    for (final row in grid) {
      for (final value in row) {
        if (value.inMinutes > maxMinutes) maxMinutes = value.inMinutes;
      }
    }
    final max = math.max(1, maxMinutes);
    return Column(
      children: [
        for (var day = 0; day < 7; day++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    _weekdayNames[day],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                for (var hour = 0; hour < 24; hour++) ...[
                  if (hour > 0) const SizedBox(width: 2),
                  Expanded(
                    child: Tooltip(
                      message:
                          '${_weekdayNames[day]} $hour:00 · ${grid[day][hour].inMinutes} 分钟',
                      waitDuration: const Duration(milliseconds: 350),
                      child: Container(
                        height: 11,
                        decoration: BoxDecoration(
                          color: grid[day][hour].inMinutes == 0
                              ? scheme.surfaceContainerHigh
                              : node.color.withValues(
                                  alpha:
                                      .12 +
                                      .78 * grid[day][hour].inMinutes / max,
                                ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 22),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final value in ['0', '6', '12', '18', '24'])
                Text(
                  value,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _trend(BuildContext context, StatsWindow window, _StatsNode node) {
    final scheme = Theme.of(context).colorScheme;
    final totals = weeklyTotals(window, node.events);
    final max = totals.fold(
      Duration.zero,
      (value, item) => item > value ? item : value,
    );
    final lastDay = dayStart(
      window.toExclusive.subtract(const Duration(days: 1)),
    );
    final lastMonday = lastDay.subtract(Duration(days: lastDay.weekday - 1));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var index = 0; index < totals.length; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message:
                    '${lastMonday.subtract(Duration(days: (7 - index) * 7)).month}/${lastMonday.subtract(Duration(days: (7 - index) * 7)).day} 那周 · ${_compact(totals[index])}',
                waitDuration: const Duration(milliseconds: 350),
                child: GestureDetector(
                  onTap: () => _applyWeek(
                    lastMonday.subtract(Duration(days: (7 - index) * 7)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 46,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            height:
                                3 +
                                (max == Duration.zero
                                    ? 0
                                    : 43 *
                                          totals[index].inMinutes /
                                          max.inMinutes),
                            decoration: BoxDecoration(
                              color: index == totals.length - 1
                                  ? node.color
                                  : node.color.withValues(alpha: .24),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${lastMonday.subtract(Duration(days: (7 - index) * 7)).month}/${lastMonday.subtract(Duration(days: (7 - index) * 7)).day}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _eventRow(BuildContext context, Event event) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selectedEvents.contains(event.id);
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: .08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _editing
            ? () => setState(() {
                if (!_selectedEvents.add(event.id)) {
                  _selectedEvents.remove(event.id);
                }
              })
            : null,
        child: SizedBox(
          height: 33,
          child: Row(
            children: [
              if (_editing) ...[
                const SizedBox(width: 4),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(3.5),
                  ),
                  child: selected
                      ? Icon(Icons.check, size: 10, color: scheme.onPrimary)
                      : null,
                ),
                const SizedBox(width: 8),
              ],
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: event.tagId == null
                      ? Colors.blueGrey
                      : tagDot(context, widget.journal.store, event.tagId),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  event.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
                ),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  '${event.start.month}/${event.start.day} ${clockText(event.start)}',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                child: Text(
                  _compact(
                    event.end == null
                        ? Duration.zero
                        : event.end!.difference(event.start),
                  ),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectionBar(BuildContext context, _StatsNode node) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
        color: scheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selectedEvents.isEmpty
                  ? '未选择事件'
                  : '已选 ${_selectedEvents.length} 条',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _editing = false;
              _selectedEvents.clear();
            }),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _selectedEvents.isEmpty
                ? null
                : () => _moveSelected(node),
            child: const Text('移动到标签…'),
          ),
        ],
      ),
    );
  }

  _StatsModel _buildModel(BuildContext context) {
    final store = widget.journal.store;
    final window = StatsWindow.days(_from, _to);
    final nodes = <String, _StatsNode>{};
    final byTag = <String, List<Event>>{};
    for (final event in store.events.values) {
      if (event.isUndefined || event.tagId == null) continue;
      (byTag[event.tagId!] ??= <Event>[]).add(event);
    }
    _StatsNode buildTag(Tag tag) {
      final children = <_StatsNode>[
        for (final child in store.tags.values)
          if (child.parentId == tag.id) buildTag(child),
      ];
      final direct = byTag[tag.id] ?? const <Event>[];
      final events = <Event>[
        ...direct,
        for (final child in children) ...child.events,
      ];
      final node = _StatsNode(
        id: tag.id,
        name: tag.name,
        parentId: tag.parentId,
        color: tagDot(context, store, tag.id),
        duration: durationIn(window, events),
        previous: durationIn(window.previous, events),
        children: children,
        events: events,
        directEvents: direct,
        isGap: false,
        isUnclassified: false,
      );
      nodes[tag.id] = node;
      return node;
    }

    final tagRoots =
        <_StatsNode>[
            for (final tag in store.tags.values)
              if (tag.parentId == null) buildTag(tag),
          ]
          ..removeWhere((node) => node.duration == Duration.zero)
          ..sort((a, b) => b.duration.compareTo(a.duration));
    final unclassifiedEvents = store.events.values
        .where((event) => !event.isUndefined && event.tagId == null)
        .toList();
    final undefinedEvents = store.events.values
        .where((event) => event.isUndefined)
        .toList();
    final unclassified = _StatsNode(
      id: _unclassifiedId,
      name: '未分类',
      parentId: null,
      color: Colors.blueGrey.shade400,
      duration: durationIn(window, unclassifiedEvents),
      previous: durationIn(window.previous, unclassifiedEvents),
      children: const [],
      events: unclassifiedEvents,
      directEvents: unclassifiedEvents,
      isGap: false,
      isUnclassified: true,
    );
    final undefined = _StatsNode(
      id: _undefinedId,
      name: '未定义',
      parentId: null,
      color: Colors.grey.shade500,
      duration: durationIn(window, undefinedEvents),
      previous: durationIn(window.previous, undefinedEvents),
      children: const [],
      events: undefinedEvents,
      directEvents: undefinedEvents,
      isGap: true,
      isUnclassified: false,
    );
    nodes[_unclassifiedId] = unclassified;
    nodes[_undefinedId] = undefined;
    final pseudo = [
      if (unclassified.duration > Duration.zero) unclassified,
      if (undefined.duration > Duration.zero) undefined,
    ]..sort((a, b) => b.duration.compareTo(a.duration));
    final roots = [...tagRoots, ...pseudo];
    final visibleTotal = roots
        .where((root) => !_hidden.contains(root.id))
        .fold(Duration.zero, (sum, node) => sum + node.duration);
    return _StatsModel(
      nodes: nodes,
      roots: roots,
      visibleTotal: visibleTotal,
      window: window,
    );
  }
}

class _StatsModel {
  const _StatsModel({
    required this.nodes,
    required this.roots,
    required this.visibleTotal,
    required this.window,
  });
  final Map<String, _StatsNode> nodes;
  final List<_StatsNode> roots;
  final Duration visibleTotal;
  final StatsWindow window;
}

class _StatsNode {
  const _StatsNode({
    required this.id,
    required this.name,
    required this.parentId,
    required this.color,
    required this.duration,
    required this.previous,
    required this.children,
    required this.events,
    required this.directEvents,
    required this.isGap,
    required this.isUnclassified,
  });
  final String id;
  final String name;
  final String? parentId;
  final Color color;
  final Duration duration;
  final Duration previous;
  final List<_StatsNode> children;
  final List<Event> events;
  final List<Event> directEvents;
  final bool isGap;
  final bool isUnclassified;
  bool get canEdit => !isGap;
}

class _MoveTargetDialog extends StatefulWidget {
  const _MoveTargetDialog({
    required this.store,
    required this.count,
    this.initialTarget,
  });
  final Store store;
  final int count;
  final String? initialTarget;
  @override
  State<_MoveTargetDialog> createState() => _MoveTargetDialogState();
}

class _MoveTargetDialogState extends State<_MoveTargetDialog> {
  late String? _target = widget.initialTarget;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('移动 ${widget.count} 条事件'),
    content: SizedBox(
      width: 380,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '只修改标签，事件的时间和标题保持不变。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TagField(
            store: widget.store,
            value: _target,
            onChanged: (value) => setState(() => _target = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _target == widget.initialTarget
            ? null
            : () => Navigator.pop(context, (true, _target)),
        child: const Text('移动'),
      ),
    ],
  );
}

String _compact(Duration value) {
  final minutes = value.inMinutes.abs();
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

int _percent(Duration value, Duration total) {
  if (total.inSeconds <= 0) return 0;
  return (value.inSeconds / total.inSeconds * 100).round().clamp(0, 100);
}
