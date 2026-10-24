import 'package:flutter/material.dart';

import '../data/store.dart';
import 'theme.dart';
import 'workspace_style.dart';

/// Shared tag row for the sidebar and event tag pickers.
class TagTreeTile extends StatelessWidget {
  const TagTreeTile({
    super.key,
    required this.store,
    required this.label,
    required this.onTap,
    this.tagId,
    this.depth = 0,
    this.selected = false,
    this.collapsed = false,
    this.onToggle,
  });

  final Store store;
  final String label;
  final String? tagId;
  final int depth;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minLeadingWidth: WorkspaceStyle.tagSize,
    horizontalTitleGap: 8,
    selected: selected,
    selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
    selectedColor: Theme.of(context).colorScheme.onSecondaryContainer,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    contentPadding: EdgeInsets.only(
      left: 4 + depth * WorkspaceStyle.tagIndent,
      right: 4,
    ),
    leading: SizedBox(
      width: WorkspaceStyle.tagSize,
      child: Center(
        child: Container(
          key: ValueKey('tag-dot-${tagId ?? 'unclassified'}'),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: tagDot(context, store, tagId),
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
    title: Text(
      label,
      style: Theme.of(context).textTheme.bodyMedium,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: onToggle == null
        ? null
        : Tooltip(
            message: collapsed ? '展开$label' : '收起$label',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  collapsed ? Icons.chevron_right : Icons.keyboard_arrow_down,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
    onTap: onTap,
  );
}
