import 'package:flutter/material.dart';

enum TagDropPosition { before, inside, after }

/// Row edges reorder siblings; the middle moves a tag into a branch.
class TagDropTarget extends StatefulWidget {
  const TagDropTarget({
    super.key,
    required this.canAccept,
    required this.onDrop,
    required this.child,
  });
  final bool Function(String source, TagDropPosition position) canAccept;
  final void Function(String source, TagDropPosition position) onDrop;
  final Widget child;
  @override
  State<TagDropTarget> createState() => _TagDropTargetState();
}

class _TagDropTargetState extends State<TagDropTarget> {
  TagDropPosition? _position;
  TagDropPosition _at(Offset offset) {
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(offset).dy;
    if (y < box.size.height * .25) return TagDropPosition.before;
    if (y > box.size.height * .75) return TagDropPosition.after;
    return TagDropPosition.inside;
  }

  @override
  Widget build(BuildContext context) => DragTarget<String>(
    onWillAcceptWithDetails: (details) =>
        widget.canAccept(details.data, _at(details.offset)),
    onMove: (details) {
      final position = _at(details.offset);
      setState(
        () => _position = widget.canAccept(details.data, position)
            ? position
            : null,
      );
    },
    onLeave: (_) => setState(() => _position = null),
    onAcceptWithDetails: (details) {
      final position = _at(details.offset);
      setState(() => _position = null);
      if (widget.canAccept(details.data, position)) {
        widget.onDrop(details.data, position);
      }
    },
    builder: (context, candidates, _) => Stack(
      children: [
        ColoredBox(
          color: candidates.isNotEmpty && _position == TagDropPosition.inside
              ? Theme.of(context).colorScheme.secondaryContainer
              : Colors.transparent,
          child: widget.child,
        ),
        if (candidates.isNotEmpty &&
            _position != null &&
            _position != TagDropPosition.inside)
          Positioned(
            left: 0,
            right: 0,
            top: _position == TagDropPosition.before ? 0 : null,
            bottom: _position == TagDropPosition.after ? 0 : null,
            child: IgnorePointer(
              child: Container(
                height: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
      ],
    ),
  );
}
