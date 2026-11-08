import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../domain/model.dart';
import 'theme.dart';

/// One independently colored label. Shared by item and record displays.
class TagToken extends StatelessWidget {
  const TagToken({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
    this.tooltip,
    this.maxWidth = 160,
  });
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;
  final String? tooltip;
  final double maxWidth;
  static const textStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? label,
    child: Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyle.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The owning item uses a dark neutral badge, outside the tag color palette.
class RecordItemBadge extends StatelessWidget {
  const RecordItemBadge({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => TagToken(
    label: label,
    background: Colors.grey.shade800,
    foreground: Colors.white,
    tooltip: '所属事项：$label',
  );
}

class _RecordLabel {
  const _RecordLabel(this.label, this.child);
  final String label;
  final Widget child;
}

/// A fixed-height strip with a count menu for labels that do not fit.
class RecordTagChips extends StatelessWidget {
  const RecordTagChips({super.key, required this.store, required this.event});
  final Store store;
  final Event event;

  @override
  Widget build(BuildContext context) {
    final tokens = <_RecordLabel>[];
    if (event.itemId != null) {
      final name = store.ownerLabels(event).first;
      tokens.add(
        _RecordLabel(
          name,
          RecordItemBadge(
            key: ValueKey('record-item-${event.id}'),
            label: name,
          ),
        ),
      );
    }
    for (final id in event.tagIds) {
      if (!store.tags.containsKey(id)) continue;
      final (bg, fg) = tagEventColors(context, store, id);
      final name = store.tagName(id);
      tokens.add(
        _RecordLabel(
          name,
          TagToken(
            key: ValueKey('record-tag-${event.id}-$id'),
            label: name,
            background: bg,
            foreground: fg,
          ),
        ),
      );
    }
    if (tokens.isEmpty) {
      final (bg, fg) = tagEventColors(context, store, null);
      tokens.add(
        _RecordLabel(
          '未归类',
          TagToken(label: '未归类', background: bg, foreground: fg),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        double measure(String label) {
          final painter = TextPainter(
            text: TextSpan(
              text: label,
              style: DefaultTextStyle.of(
                context,
              ).style.merge(TagToken.textStyle),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final widths = [
          for (final token in tokens)
            math.min(160.0, measure(token.label) + 17),
        ];
        // Keep the item visible before folding tags, truncating a long name.
        if (event.itemId != null && tokens.length > 1) {
          final itemSpace = available - measure('+${tokens.length - 1}') - 28;
          if (itemSpace >= measure('…') + 17) {
            widths[0] = math.min(widths[0], itemSpace);
          }
        }
        var used = 0.0;
        var visible = 0;
        for (var index = 0; index < tokens.length; index++) {
          final next = used + (index == 0 ? 0 : 6) + widths[index];
          final remaining = tokens.length - index - 1;
          final reserve = remaining == 0 ? 0 : measure('+$remaining') + 28;
          if (next + reserve > available) break;
          used = next;
          visible++;
        }
        // A single long label truncates within the column instead of disappearing.
        if (tokens.length == 1) visible = 1;
        final hidden = tokens.skip(visible).toList();
        return Row(
          children: [
            for (var index = 0; index < visible; index++) ...[
              if (index > 0) const SizedBox(width: 6),
              SizedBox(
                width: tokens.length == 1
                    ? math.min(widths[index], available)
                    : widths[index],
                child: tokens[index].child,
              ),
            ],
            if (hidden.isNotEmpty) ...[
              if (visible > 0) const SizedBox(width: 6),
              Flexible(
                fit: FlexFit.loose,
                child: PopupMenuButton<void>(
                  key: ValueKey('record-tags-overflow-${event.id}'),
                  tooltip: hidden.map((token) => token.label).join('、'),
                  itemBuilder: (context) => [
                    for (final token in hidden)
                      PopupMenuItem<void>(
                        enabled: false,
                        height: 36,
                        child: token.child,
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+${hidden.length}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TagToken.textStyle,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
