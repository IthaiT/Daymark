import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../domain/ledger.dart';
import 'ledger_category_style.dart';
import 'ledger_dialogs.dart';
import 'theme_tokens.dart';
import 'workspace_style.dart';

class LedgerStatistics extends StatefulWidget {
  const LedgerStatistics({
    super.key,
    required this.state,
    required this.anchor,
    required this.period,
    required this.kind,
    required this.parentId,
    required this.onParentChanged,
  });
  final LedgerState state;
  final DateTime anchor;
  final LedgerPeriod period;
  final MoneyKind kind;
  final String? parentId;
  final ValueChanged<String?> onParentChanged;

  @override
  State<LedgerStatistics> createState() => _LedgerStatisticsState();
}

class _LedgerStatisticsState extends State<LedgerStatistics> {
  LedgerState get state => widget.state;
  DateTime get anchor => widget.anchor;
  LedgerPeriod get period => widget.period;
  MoneyKind get kind => widget.kind;
  String? get parentId => widget.parentId;
  ValueChanged<String?> get onParentChanged => widget.onParentChanged;
  bool _exclude = true;
  Set<String?> _selection = {};
  bool get _filtered => !_exclude || _selection.isNotEmpty;

  @override
  void didUpdateWidget(LedgerStatistics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != kind) {
      _exclude = true;
      _selection = {};
    }
  }

  Future<void> _filter() async {
    final result = await showDialog<({bool exclude, Set<String?> ids})>(
      context: context,
      builder: (_) => _CategoryFilterDialog(
        state: state,
        kind: kind,
        exclude: _exclude,
        selection: _selection,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _exclude = result.exclude;
        _selection = result.ids;
      });
    }
  }

  String _name(CategoryAmount row, MoneyCategory? parent) => row.direct
      ? (parent == null ? '未分类' : '${parent.name}（直接记录）')
      : state.categories[row.categoryId]!.name;

  @override
  Widget build(BuildContext context) {
    final parent = state.categories[parentId];
    final rows = state.categoryBreakdown(
      anchor,
      period,
      kind,
      parentId: parent?.id,
      includedCategoryIds: _exclude ? null : _selection,
      excludedCategoryIds: _exclude ? _selection : const {},
    );
    final total = rows.fold<int>(0, (sum, row) => sum + row.amountCents);
    final count = rows.fold<int>(0, (sum, row) => sum + row.count);
    final chart = _chart(context, rows, total, count);
    final list = ListView(
      key: const ValueKey('ledger-statistics-list'),
      children: [for (final row in rows) _row(context, row, parent, total)],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (parent != null)
              IconButton(
                key: const ValueKey('stats-back'),
                tooltip: '返回上一级',
                onPressed: () => onParentChanged(parent.parentId),
                icon: const Icon(Icons.arrow_back),
              ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      parent == null
                          ? '全部${moneyKindText(kind)}'
                          : state.categoryLabel(parent.id),
                      key: const ValueKey('stats-path'),
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    key: const ValueKey('stats-filter'),
                    onPressed: _filter,
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: Text(
                      _filtered
                          ? '${_exclude ? '已排除' : '仅包含'} ${_selection.length} 个标签'
                          : '筛选标签',
                    ),
                  ),
                  if (_filtered)
                    TextButton(
                      key: const ValueKey('stats-filter-reset'),
                      onPressed: () => setState(() {
                        _exclude = true;
                        _selection = {};
                      }),
                      child: const Text('重置筛选'),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('$count 笔'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    _filtered
                        ? '筛选后暂无${moneyKindText(kind)}'
                        : '${period == LedgerPeriod.month ? '本月' : '本年'}暂无${moneyKindText(kind)}',
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 760) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 300, height: 300, child: chart),
                          const SizedBox(width: 24),
                          Expanded(child: list),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        SizedBox(
                          height: math.min(210, constraints.maxHeight * .45),
                          child: chart,
                        ),
                        const SizedBox(height: 12),
                        Expanded(child: list),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _chart(
    BuildContext context,
    List<CategoryAmount> rows,
    int total,
    int count,
  ) => _LedgerDonut(
    key: const ValueKey('ledger-donut-chart'),
    rows: rows,
    names: rows.map((row) => _name(row, state.categories[parentId])).toList(),
    colors: rows
        .map(
          (row) => DaymarkColors.of(
            context,
          ).categoryAccent(ledgerCategoryColor(state, row.categoryId)),
        )
        .toList(),
    kind: kind,
    total: total,
    count: count,
    filtered: _filtered,
  );

  Widget _row(
    BuildContext context,
    CategoryAmount row,
    MoneyCategory? parent,
    int total,
  ) {
    final name = _name(row, parent);
    final percentage = row.amountCents / total;
    final swatch = ledgerCategorySwatch(state, row.categoryId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey(
          'stats-${row.categoryId ?? 'unclassified'}-${row.direct}',
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: LedgerCategoryBadge(
          state: state,
          id: row.categoryId,
          size: 36,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '¥ ${moneyText(row.amountCents)}  ${(percentage * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${row.count} 笔',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: percentage,
                minHeight: 5,
                borderRadius: BorderRadius.circular(4),
                color: DaymarkColors.of(
                  context,
                ).categoryAccent(ledgerCategoryColor(state, row.categoryId)),
                backgroundColor: swatch[50],
              ),
            ],
          ),
        ),
        trailing: row.direct ? null : const Icon(Icons.chevron_right),
        onTap: row.direct ? null : () => onParentChanged(row.categoryId),
      ),
    );
  }
}

class _LedgerDonut extends StatefulWidget {
  const _LedgerDonut({
    super.key,
    required this.rows,
    required this.names,
    required this.colors,
    required this.kind,
    required this.total,
    required this.count,
    required this.filtered,
  });
  final List<CategoryAmount> rows;
  final List<String> names;
  final List<Color> colors;
  final MoneyKind kind;
  final int total;
  final int count;
  final bool filtered;
  @override
  State<_LedgerDonut> createState() => _LedgerDonutState();
}

class _LedgerDonutState extends State<_LedgerDonut> {
  int? _hovered;

  @override
  void didUpdateWidget(_LedgerDonut oldWidget) {
    super.didUpdateWidget(oldWidget);
    _hovered = null;
  }

  void _hover(Offset position, Size size) {
    final offset = position - size.center(Offset.zero);
    final radius = offset.distance;
    int? hit;
    // Match the painted ring's inner/outer radius and gaps.
    if (radius >= size.shortestSide * .32 &&
        radius <= size.shortestSide * .5 &&
        widget.total > 0) {
      final angle =
          (math.atan2(offset.dy, offset.dx) + math.pi / 2) % (math.pi * 2);
      var start = 0.0;
      for (var i = 0; i < widget.rows.length; i++) {
        final sweep = widget.rows[i].amountCents / widget.total * math.pi * 2;
        final gap = widget.rows.length > 1 ? math.min(.024, sweep * .12) : 0.0;
        if (angle >= start + gap / 2 && angle < start + sweep - gap / 2) {
          hit = i;
          break;
        }
        start += sweep;
      }
    }
    if (hit != _hovered) setState(() => _hovered = hit);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '${moneyKindText(widget.kind)}标签占比，共${widget.count}笔，${moneyText(widget.total)}元',
    child: Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, constraints) => MouseRegion(
            onEnter: (event) =>
                _hover(event.localPosition, constraints.biggest),
            onHover: (event) =>
                _hover(event.localPosition, constraints.biggest),
            onExit: (_) => setState(() => _hovered = null),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    key: const ValueKey('ledger-donut'),
                    painter: _DonutPainter(
                      amounts: widget.rows
                          .map((row) => row.amountCents)
                          .toList(),
                      colors: widget.colors,
                      hovered: _hovered,
                      background: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: .58,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _hovered == null
                            ? '${widget.filtered ? '筛选后' : '总'}${moneyKindText(widget.kind)}'
                            : widget.names[_hovered!],
                        key: const ValueKey('ledger-donut-label'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        child: Text(
                          '¥ ${moneyText(_hovered == null ? widget.total : widget.rows[_hovered!].amountCents)}',
                          key: const ValueKey('ledger-donut-amount'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (_hovered != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${(widget.rows[_hovered!].amountCents / widget.total * 100).toStringAsFixed(1)}%',
                          key: const ValueKey('ledger-donut-percentage'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CategoryFilterDialog extends StatefulWidget {
  const _CategoryFilterDialog({
    required this.state,
    required this.kind,
    required this.exclude,
    required this.selection,
  });
  final LedgerState state;
  final MoneyKind kind;
  final bool exclude;
  final Set<String?> selection;
  @override
  State<_CategoryFilterDialog> createState() => _CategoryFilterDialogState();
}

class _CategoryFilterDialogState extends State<_CategoryFilterDialog> {
  late bool _exclude = widget.exclude;
  late final Set<String?> _selection = {...widget.selection};

  @override
  Widget build(BuildContext context) {
    final categories = widget.state.orderedCategories(widget.kind);
    final ids = <String?>[null, ...categories.map((item) => item.id)];
    return AlertDialog(
      title: const Text('筛选统计标签'),
      content: SizedBox(
        width: 440,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('排除所选')),
                ButtonSegment(value: false, label: Text('仅包含所选')),
              ],
              selected: {_exclude},
              onSelectionChanged: (values) =>
                  setState(() => _exclude = values.single),
            ),
            const SizedBox(height: 12),
            const Text('选择父标签会包含其所有子标签。占比按筛选后的总额计算。'),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _selection.addAll(ids)),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selection.clear),
                  child: const Text('清空选择'),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final id in ids)
                    CheckboxListTile(
                      key: ValueKey('stats-filter-${id ?? 'unclassified'}'),
                      value: _selection.contains(id),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.only(
                        left: id == null
                            ? 0
                            : (widget.state.ancestors(id).length - 1) * 16.0,
                      ),
                      title: Text(
                        id == null ? '未分类' : widget.state.categories[id]!.name,
                      ),
                      onChanged: (checked) => setState(() {
                        if (checked == true) {
                          _selection.add(id);
                        } else {
                          _selection.remove(id);
                        }
                      }),
                    ),
                ],
              ),
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
          onPressed: () =>
              Navigator.pop(context, (exclude: _exclude, ids: _selection)),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.amounts,
    required this.colors,
    required this.background,
    this.hovered,
  });
  final List<int> amounts;
  final List<Color> colors;
  final Color background;
  final int? hovered;
  @override
  void paint(Canvas canvas, Size size) {
    final width = size.shortestSide * .18;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - width) / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = background;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);
    final total = amounts.fold<int>(0, (sum, amount) => sum + amount);
    if (total == 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < amounts.length; i++) {
      final sweep = amounts[i] / total * math.pi * 2;
      final gap = amounts.length > 1 ? math.min(.024, sweep * .12) : 0.0;
      paint.color = hovered == null || hovered == i
          ? colors[i]
          : colors[i].withValues(alpha: .35);
      canvas.drawArc(rect, start + gap / 2, sweep - gap, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.hovered != hovered ||
      !listEquals(oldDelegate.amounts, amounts) ||
      !listEquals(oldDelegate.colors, colors);
}
