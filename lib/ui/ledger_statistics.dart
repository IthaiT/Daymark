import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../domain/ledger.dart';
import 'ledger_category_style.dart';
import 'ledger_dialogs.dart';
import 'theme_tokens.dart';

class LedgerStatistics extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final parent = state.categories[parentId];
    final rows = state.categoryBreakdown(
      anchor,
      period,
      kind,
      parentId: parent?.id,
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
              child: Text(
                parent == null
                    ? '全部${moneyKindText(kind)}'
                    : state.categoryPath(parent.id),
                key: const ValueKey('stats-path'),
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('$count 笔'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    '${period == LedgerPeriod.month ? '本月' : '本年'}暂无${moneyKindText(kind)}',
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
  ) => Semantics(
    label: '${moneyKindText(kind)}标签占比，共$count笔，${moneyText(total)}元',
    child: Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                key: const ValueKey('ledger-donut'),
                painter: _DonutPainter(
                  amounts: rows.map((row) => row.amountCents).toList(),
                  colors: rows
                      .map(
                        (row) => DaymarkColors.of(context).categoryAccent(
                          ledgerCategoryColor(state, row.categoryId),
                        ),
                      )
                      .toList(),
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
                    '总${moneyKindText(kind)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    child: Text(
                      '¥ ${moneyText(total)}',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _row(
    BuildContext context,
    CategoryAmount row,
    MoneyCategory? parent,
    int total,
  ) {
    final name = row.direct
        ? (parent == null ? '未分类' : '${parent.name}（直接记录）')
        : state.categories[row.categoryId]!.name;
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

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.amounts,
    required this.colors,
    required this.background,
  });
  final List<int> amounts;
  final List<Color> colors;
  final Color background;
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
      paint.color = colors[i];
      canvas.drawArc(rect, start + gap / 2, sweep - gap, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.background != background ||
      !listEquals(oldDelegate.amounts, amounts) ||
      !listEquals(oldDelegate.colors, colors);
}
