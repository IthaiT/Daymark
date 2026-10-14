import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Frameless title bar in the Windows convention: the whole bar drags the
/// window and doubles on double-tap to maximize; flat caption buttons sit at
/// the far right. The native title bar is hidden in main().
class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({
    super.key,
    this.leading,
    this.leadingWidth = 250,
    this.backgroundColor,
    this.actions,
    this.height = 36,
  });
  final Widget? leading;
  final double leadingWidth;
  final Color? backgroundColor;
  final Widget? actions;
  final double height;
  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> with WindowListener {
  bool _maximized = false;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      child: Row(
        children: [
          // Melt into the sidebar's surface so the bar reads as part of it.
          Container(
            width: widget.leadingWidth,
            color: widget.backgroundColor ?? scheme.surfaceContainerLow,
            child:
                widget.leading ??
                const DragToMoveArea(child: SizedBox.expand()),
          ),
          Expanded(
            child: ColoredBox(
              color: widget.backgroundColor ?? scheme.surfaceContainerLow,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DragToMoveArea(child: SizedBox.expand()),
                  if (widget.actions != null) widget.actions!,
                ],
              ),
            ),
          ),
          _CaptionButton(
            height: widget.height,
            icon: Icons.remove,
            tooltip: '最小化',
            onPressed: windowManager.minimize,
          ),
          _CaptionButton(
            height: widget.height,
            icon: _maximized ? Icons.filter_none : Icons.crop_square,
            tooltip: _maximized ? '向下还原' : '最大化',
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _CaptionButton(
            height: widget.height,
            icon: Icons.close,
            tooltip: '关闭',
            close: true,
            onPressed: windowManager.close,
          ),
        ],
      ),
    );
  }
}

/// A flat 46x32 Windows-style caption button with a quiet hover wash; the
/// close button warms to the conventional red on hover.
class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.close = false,
    this.height = 36,
  });
  final IconData icon;
  final String tooltip;
  final Future<void> Function() onPressed;
  final bool close;
  final double height;
  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: widget.height,
            alignment: Alignment.center,
            color: _hover
                ? (widget.close
                      ? scheme.errorContainer
                      : scheme.surfaceContainerHighest)
                : Colors.transparent,
            child: Icon(
              widget.icon,
              size: 17,
              color: _hover && widget.close
                  ? scheme.onErrorContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
