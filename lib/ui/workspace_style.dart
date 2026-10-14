import 'package:flutter/material.dart';

abstract final class WorkspaceStyle {
  static const sidebarWidth = 304.0;
  static const gap = 20.0;
  static const sectionGap = 16.0;
  static const panelRadius = 16.0;
  static const controlRadius = 10.0;
  static const tagSize = 24.0;
  static const tagIndent = 12.0;
  static const padding = EdgeInsets.fromLTRB(16, 16, 20, 20);
  static const panelPadding = EdgeInsets.all(16);
}

/// Both workspaces share the same surfaces, corner treatment and clipping.
class WorkspacePanel extends StatelessWidget {
  const WorkspacePanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    borderRadius: BorderRadius.circular(WorkspaceStyle.panelRadius),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class WorkspaceLayout extends StatelessWidget {
  const WorkspaceLayout({
    super.key,
    required this.sidebar,
    required this.content,
  });
  final Widget sidebar;
  final Widget content;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = Padding(
        padding: WorkspaceStyle.padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: WorkspaceStyle.sidebarWidth, child: sidebar),
            const SizedBox(width: WorkspaceStyle.gap),
            Expanded(child: content),
          ],
        ),
      );
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: constraints.maxWidth < 980 ? 980 : constraints.maxWidth,
          height: constraints.maxHeight,
          child: layout,
        ),
      );
    },
  );
}

/// Mode switches share typography, spacing and the same quiet selected state.
class AppSegmentedButton<T> extends SegmentedButton<T> {
  const AppSegmentedButton({
    super.key,
    required super.segments,
    required super.selected,
    super.onSelectionChanged,
  }) : super(showSelectedIcon: false);
}

class WorkspaceSectionHeader extends StatelessWidget {
  const WorkspaceSectionHeader({
    super.key,
    required this.title,
    this.actions = const [],
  });
  final String title;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...actions,
      ],
    ),
  );
}
