import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Frameless title bar: three window-control dots and a draggable caption
/// area, without any caption text. The native title bar is hidden in main().
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget dragArea(Widget child) => DragToMoveArea(child: child);
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          // Melt into the sidebar's surface so the bar reads as part of it.
          Container(
            width: 250,
            color: scheme.surfaceContainer,
            child: dragArea(
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: Row(
                  children: [
                    _WindowDot(
                      color: Colors.red.shade400,
                      icon: Icons.close,
                      tooltip: '关闭',
                      onPressed: windowManager.close,
                    ),
                    const SizedBox(width: 8),
                    _WindowDot(
                      color: Colors.amber.shade400,
                      icon: Icons.remove,
                      tooltip: '最小化',
                      onPressed: windowManager.minimize,
                    ),
                    const SizedBox(width: 8),
                    _WindowDot(
                      color: Colors.green.shade400,
                      icon: Icons.filter_none,
                      tooltip: '最大化 / 还原',
                      onPressed: () async {
                        if (await windowManager.isMaximized()) {
                          await windowManager.unmaximize();
                        } else {
                          await windowManager.maximize();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: dragArea(
              ColoredBox(
                color: scheme.surfaceContainerLow,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowDot extends StatefulWidget {
  const _WindowDot({
    required this.color,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final Color color;
  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  @override
  State<_WindowDot> createState() => _WindowDotState();
}

class _WindowDotState extends State<_WindowDot> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => unawaited(widget.onPressed()),
        child: Container(
          width: 12,
          height: 12,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
          child: _hover
              ? Icon(widget.icon, size: 8, color: Colors.black87)
              : null,
        ),
      ),
    ),
  );
}
