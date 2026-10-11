import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/journal_controller.dart';
import '../domain/model.dart';
import '../domain/timeline_interaction.dart';
import 'theme.dart';

class Timeline extends StatefulWidget {
  const Timeline({
    super.key,
    required this.journal,
    required this.beforeAction,
    required this.onRename,
    required this.onContext,
    required this.onError,
    this.editorEventId,
    this.titleEditor,
  });
  final JournalController journal;
  final Future<bool> Function() beforeAction;
  final ValueChanged<String> onRename;
  final void Function(Offset, String?, DateTime) onContext;
  final ValueChanged<Object> onError;
  final String? editorEventId;
  final Widget? titleEditor;
  @override
  State<Timeline> createState() => TimelineState();
}

class TimelineState extends State<Timeline> {
  final horizontal = ScrollController();
  final vertical = ScrollController();
  final _focus = FocusNode();
  late final Timer _clockTimer = Timer.periodic(const Duration(minutes: 1), (
    _,
  ) {
    if (mounted) setState(() {});
  });
  double zoom = 1;
  double _dayWidth = 650;
  double _height = 280;
  double _viewportWidth = 700;
  Event? _original;
  Event? _preview;
  DragEdge? _edge;
  double _anchorX = 0;
  bool _moved = false;
  int? _pointer;
  int? _pendingPointer;
  DateTime? _snap;
  String? _hoverId;
  Offset? _hoverPosition;
  MouseCursor _cursor = SystemMouseCursors.basic;
  Map<String, List<Rect>> _pieces = {};
  @override
  void initState() {
    super.initState();
    _clockTimer;
  }

  @override
  void dispose() {
    horizontal.dispose();
    vertical.dispose();
    _focus.dispose();
    _clockTimer.cancel();
    super.dispose();
  }

  List<Event> get _events => [
    for (final event in widget.journal.visibleEvents)
      event.id == _preview?.id ? _preview! : event,
  ];
  List<Event> get _displayEvents => [
    ..._events,
    for (final gap in undefinedEvents([
      for (final event in widget.journal.regularEvents)
        event.id == _preview?.id ? _preview! : event,
    ], widget.journal.day))
      gap.copyWith(title: widget.journal.event(gap.id)?.title ?? gap.title),
  ];
  double _x(DateTime value) =>
      24 +
      value.difference(widget.journal.day).inMicroseconds /
          const Duration(days: 1).inMicroseconds *
          _dayWidth;
  Offset _content(Offset point) =>
      point +
      Offset(
        horizontal.hasClients ? horizontal.offset : 0,
        vertical.hasClients ? vertical.offset : 0,
      );
  Event? _hit(Offset content) {
    for (final entry in _pieces.entries.toList().reversed) {
      if (entry.value.any((rect) => rect.inflate(2).contains(content))) {
        return _displayEvents
            .where((event) => event.id == entry.key)
            .firstOrNull;
      }
    }
    return null;
  }

  (Event, DragEdge)? _handle(Offset content) {
    final candidates = <(double, bool, Event, DragEdge)>[];
    for (final event in _events) {
      final pieces = _pieces[event.id];
      final interval = event.intervalOn(widget.journal.day);
      if (pieces == null || interval == null) continue;
      for (final edge in [DragEdge.start, DragEdge.end]) {
        final value = edge == DragEdge.start ? event.start : event.end!;
        final clipped = edge == DragEdge.start ? interval.start : interval.end;
        final rectangle = edge == DragEdge.start ? pieces.first : pieces.last;
        final distance = (content.dx - _x(value)).abs();
        if (value == clipped &&
            distance <= 6 &&
            content.dy >= rectangle.top - 2 &&
            content.dy <= rectangle.bottom + 2) {
          candidates.add((
            distance,
            !widget.journal.selected.contains(event.id),
            event,
            edge,
          ));
        }
      }
    }
    candidates.sort((a, b) {
      final diff = a.$1.compareTo(b.$1);
      return diff != 0 ? diff : (a.$2 ? 1 : 0).compareTo(b.$2 ? 1 : 0);
    });
    return candidates.isEmpty
        ? null
        : (candidates.first.$3, candidates.first.$4);
  }

  Future<void> _down(PointerDownEvent pointer) async {
    if (pointer.buttons == kSecondaryMouseButton) return;
    _pendingPointer = pointer.pointer;
    final content = _content(pointer.localPosition);
    final handle = _handle(content);
    final hit = handle?.$1 ?? _hit(content);
    if (widget.editorEventId != null &&
        handle == null &&
        hit?.id == widget.editorEventId) {
      return;
    }
    if (!await widget.beforeAction() ||
        !mounted ||
        _pendingPointer != pointer.pointer) {
      return;
    }
    if (hit == null) {
      widget.journal.clearSelection();
      return;
    }
    widget.journal.select(
      hit.id,
      toggle: HardwareKeyboard.instance.isControlPressed,
      range: HardwareKeyboard.instance.isShiftPressed,
    );
    _focus.requestFocus();
    if (hit.isUndefined || widget.editorEventId == hit.id) return;
    setState(() {
      _original = widget.journal.event(hit.id);
      _preview = _original;
      _edge = handle?.$2 ?? DragEdge.move;
      _anchorX = content.dx;
      _pointer = pointer.pointer;
      _moved = false;
      _hoverId = null;
    });
  }

  void _move(PointerMoveEvent pointer) {
    if (_original == null || _pointer != pointer.pointer) return;
    final content = _content(pointer.localPosition);
    if (!_moved &&
        (content.dx - _anchorX).abs() < (_edge == DragEdge.move ? 4 : 2)) {
      return;
    }
    if (horizontal.hasClients) {
      if (pointer.localPosition.dx < 16) {
        horizontal.jumpTo(math.max(0, horizontal.offset - 20));
      } else if (pointer.localPosition.dx > _viewportWidth - 16) {
        horizontal.jumpTo(
          math.min(horizontal.position.maxScrollExtent, horizontal.offset + 20),
        );
      }
    }
    final preview = previewDrag(
      original: _original!,
      day: widget.journal.day,
      edge: _edge!,
      deltaMinutes:
          (_content(pointer.localPosition).dx - _anchorX) / _dayWidth * 1440,
      zoom: zoom,
      dayWidth: _dayWidth,
      events: _events,
      alt: HardwareKeyboard.instance.isAltPressed,
    );
    setState(() {
      _preview = preview.event;
      _snap = preview.snap;
      _moved = true;
    });
  }

  Future<void> _up(PointerUpEvent pointer) async {
    _pendingPointer = null;
    if (_pointer != pointer.pointer) return;
    final preview = _preview;
    final original = _original;
    final moved = _moved;
    setState(() {
      _original = null;
      _preview = null;
      _pointer = null;
      _snap = null;
      _moved = false;
    });
    if (moved && preview != null && preview != original) {
      try {
        await widget.journal.updateEvent(preview);
      } catch (error) {
        widget.onError(error);
      }
    }
    if (moved) widget.journal.clearSelection();
  }

  void cancelDrag() {
    final active = _original != null;
    setState(() {
      _original = null;
      _preview = null;
      _pointer = null;
      _pendingPointer = null;
      _snap = null;
      _moved = false;
    });
    if (active) widget.journal.clearSelection();
  }

  void _hover(PointerHoverEvent pointer) {
    if (_original != null) return;
    final content = _content(pointer.localPosition);
    final handle = _handle(content);
    setState(() {
      _cursor = handle != null
          ? SystemMouseCursors.resizeLeftRight
          : _hit(content)?.isUndefined == false
          ? SystemMouseCursors.move
          : SystemMouseCursors.basic;
      _hoverId = handle == null ? _hit(content)?.id : null;
      _hoverPosition = pointer.localPosition;
    });
  }

  void _wheel(PointerSignalEvent pointer) {
    if (pointer is! PointerScrollEvent || _original != null) return;
    GestureBinding.instance.pointerSignalResolver.register(pointer, (signal) {
      final event = signal as PointerScrollEvent;
      if (HardwareKeyboard.instance.isControlPressed) {
        final next = (zoom + (event.scrollDelta.dy < 0 ? .25 : -.25)).clamp(
          1.0,
          4.0,
        );
        final fraction = (_content(event.localPosition).dx - 24) / _dayWidth;
        setState(() {
          zoom = next;
          _hoverId = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && horizontal.hasClients) {
            horizontal.jumpTo(
              (24 + fraction * _dayWidth - event.localPosition.dx).clamp(
                0.0,
                horizontal.position.maxScrollExtent,
              ),
            );
          }
        });
      } else {
        final scroll = HardwareKeyboard.instance.isShiftPressed
            ? vertical
            : horizontal;
        if (scroll.hasClients) {
          scroll.jumpTo(
            (scroll.offset +
                    (event.scrollDelta.dy != 0
                        ? event.scrollDelta.dy
                        : event.scrollDelta.dx))
                .clamp(0.0, scroll.position.maxScrollExtent),
          );
        }
      }
    });
  }

  void _context(TapDownDetails pointer) {
    final point = _content(pointer.localPosition);
    final step = snapInterval(zoom);
    final minute = (((point.dx - 24) / _dayWidth * 1440 / step).round() * step)
        .clamp(0, 1439);
    widget.onContext(
      pointer.globalPosition,
      _hit(point)?.id,
      widget.journal.day.add(Duration(minutes: minute)),
    );
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          _original != null) {
        cancelDrag();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth;
        _dayWidth = math.max(650, constraints.maxWidth - 50) * zoom;
        _height = math.max(140, constraints.maxHeight - 14);
        final events = _displayEvents;
        final segments = timelineSegments(events, widget.journal.day);
        _pieces = {};
        for (final segment in segments) {
          final top = 50 + (_height - 76) * segment.slot / segment.total;
          final bottom =
              50 + (_height - 76) * (segment.slot + 1) / segment.total;
          (_pieces[segment.event.id] ??= []).add(
            Rect.fromLTRB(
              _x(segment.start),
              top,
              math.max(_x(segment.start) + 3, _x(segment.end)),
              bottom,
            ),
          );
        }
        final hover = events.where((event) => event.id == _hoverId).firstOrNull;
        final editorPieces = _pieces[widget.editorEventId];
        Rect? editorRect;
        if (editorPieces != null) {
          final visible = Rect.fromLTWH(
            horizontal.hasClients ? horizontal.offset : 0,
            vertical.hasClients ? vertical.offset : 0,
            constraints.maxWidth,
            constraints.maxHeight,
          );
          final pieces =
              editorPieces
                  .map((rect) => rect.intersect(visible))
                  .where((rect) => rect.width > 0 && rect.height > 0)
                  .toList()
                ..sort(
                  (a, b) => (b.width * b.height).compareTo(a.width * a.height),
                );
          if (pieces.isNotEmpty) {
            final rect = pieces.first;
            final width = math.min(
              math.max(120, rect.width - 12),
              constraints.maxWidth - 16,
            );
            editorRect = Rect.fromLTWH(
              (rect.center.dx - width / 2).clamp(
                visible.left + 8,
                visible.right - width - 8,
              ),
              rect.center.dy - 18,
              width.toDouble(),
              36,
            );
          }
        }
        return MouseRegion(
          cursor: _cursor,
          onHover: _hover,
          onExit: (_) => setState(() => _hoverId = null),
          child: Listener(
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: (_) => cancelDrag(),
            onPointerSignal: _wheel,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Pointer handlers select immediately; consume the resolved tap
              // so it cannot clear selection in the screen's blank-area handler.
              onTap: () {},
              onSecondaryTapDown: _context,
              onDoubleTapDown: (pointer) {
                final hit = _hit(_content(pointer.localPosition));
                if (hit != null) {
                  cancelDrag();
                  widget.onRename(hit.id);
                }
              },
              onDoubleTap: () {},
              child: Stack(
                children: [
                  Scrollbar(
                    controller: horizontal,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: horizontal,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Scrollbar(
                        controller: vertical,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.vertical,
                        child: SingleChildScrollView(
                          controller: vertical,
                          physics: const NeverScrollableScrollPhysics(),
                          child: SizedBox(
                            width: _dayWidth + 48,
                            height: _height,
                            child: Stack(
                              children: [
                                CustomPaint(
                                  size: Size(_dayWidth + 48, _height),
                                  painter: _TimelinePainter(
                                    journal: widget.journal,
                                    events: events,
                                    pieces: _pieces,
                                    dayWidth: _dayWidth,
                                    zoom: zoom,
                                    scheme: Theme.of(context).colorScheme,
                                    textStyle: Theme.of(
                                      context,
                                    ).textTheme.bodySmall!,
                                    preview: _moved ? _preview : null,
                                    snap: _snap,
                                  ),
                                ),
                                if (editorRect != null &&
                                    widget.titleEditor != null)
                                  Positioned.fromRect(
                                    rect: editorRect,
                                    child: widget.titleEditor!,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (hover != null && _hoverPosition != null)
                    Positioned(
                      left: _hoverPosition!.dx.clamp(
                        0,
                        math.max(0, constraints.maxWidth - 310),
                      ),
                      top: (_hoverPosition!.dy + 18).clamp(
                        0,
                        math.max(0, constraints.maxHeight - 95),
                      ),
                      child: IgnorePointer(
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 285,
                              child: Text(
                                '${hover.title}\n${widget.journal.store.tagOutline(hover.tagId)}\n${clockText(hover.intervalOn(widget.journal.day)!.start)} — '
                                '${hover.intervalOn(widget.journal.day)!.end == dayEnd(widget.journal.day) ? '24:00' : clockText(hover.intervalOn(widget.journal.day)!.end)} · ${durationText(hover.intervalOn(widget.journal.day)!.duration)}',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.journal,
    required this.events,
    required this.pieces,
    required this.dayWidth,
    required this.zoom,
    required this.scheme,
    required this.textStyle,
    this.preview,
    this.snap,
  });
  final JournalController journal;
  final List<Event> events;
  final Map<String, List<Rect>> pieces;
  final double dayWidth;
  final double zoom;
  final ColorScheme scheme;
  final TextStyle textStyle;
  final Event? preview;
  final DateTime? snap;
  double _x(DateTime value) =>
      24 +
      value.difference(journal.day).inMicroseconds /
          const Duration(days: 1).inMicroseconds *
          dayWidth;
  void _text(
    Canvas canvas,
    String text,
    Offset offset, {
    double? width,
    Color? color,
    bool bold = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(
          color: color ?? scheme.onSurface,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width ?? double.infinity);
    painter.paint(canvas, offset);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - 26;
    // The enclosing card draws the frame; the grid lines share this paint.
    final border = Paint()
      ..color = scheme.outlineVariant
      ..style = PaintingStyle.stroke;
    var major = zoom == 1
        ? 120
        : zoom < 2
        ? 60
        : zoom < 3
        ? 30
        : 15;
    while (dayWidth * major / 1440 < 56) {
      major *= 2;
    }
    var minor = major >= 120
        ? 60
        : major == 60
        ? 15
        : major == 30
        ? 10
        : 5;
    if (preview != null) minor = math.min(minor, snapInterval(zoom));
    for (var minute = 0; minute <= 1440; minute += minor) {
      final x = 24 + minute / 1440 * dayWidth;
      canvas.drawLine(
        Offset(x, 43),
        Offset(x, minute % major == 0 || preview != null ? bottom : 49),
        border,
      );
      if (minute % major == 0) {
        _text(
          canvas,
          '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}',
          Offset(x - 18, 16),
        );
      }
    }
    for (final event in events) {
      final rectangles = pieces[event.id];
      if (rectangles == null) continue;
      // Chip look: shave a hair off each side so neighbouring segments and
      // lanes breathe, and round the corners. Hit testing keeps using the
      // raw rectangles, so the interactive targets do not shrink.
      final path = Path();
      for (final rect in rectangles) {
        final body = rect.deflate(1);
        final radius = math.min(6.0, math.min(body.width, body.height) / 2);
        path.addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius)));
      }
      final selected = journal.selected.contains(event.id);
      final (background, foreground) = eventColors(
        journal.store,
        event,
        selected: selected,
      );
      canvas.drawPath(path, Paint()..color = background);
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..color = selected ? scheme.onSurface : scheme.outline
        ..strokeWidth = selected ? 2 : 1;
      if (event.tagId == null) {
        for (final metric in path.computeMetrics()) {
          for (double distance = 0; distance < metric.length; distance += 7) {
            canvas.drawPath(
              metric.extractPath(
                distance,
                math.min(metric.length, distance + 4),
              ),
              outline,
            );
          }
        }
      } else {
        canvas.drawPath(path, outline);
      }
      final largest = rectangles.reduce(
        (a, b) => a.width * a.height >= b.width * b.height ? a : b,
      );
      if (largest.width >= 32 && largest.height >= 18) {
        _text(
          canvas,
          event.title.isEmpty ? '新事件' : event.title,
          Offset(largest.left + 8, largest.center.dy - 7),
          width: largest.width - 14,
          color: foreground,
          bold: selected,
        );
      }
    }
    if (pieces.isEmpty) {
      _text(canvas, '这一天还没有记录。', Offset(size.width / 2 - 65, size.height / 2));
    }
    final now = civilTime(journal.clock());
    if (dayStart(now) == journal.day) {
      final paint = Paint()
        ..color = scheme.tertiary
        ..strokeWidth = 2;
      canvas.drawLine(Offset(_x(now), 42), Offset(_x(now), bottom), paint);
    }
    if (preview != null) {
      final interval = preview!.intervalOn(journal.day)!;
      for (final (index, value) in [interval.start, interval.end].indexed) {
        final x = _x(value);
        canvas.drawLine(
          Offset(x, 42),
          Offset(x, bottom),
          Paint()..color = scheme.primary,
        );
        final label = value == dayEnd(journal.day) ? '24:00' : clockText(value);
        final labelX = x.clamp(24.0, size.width - 55);
        final labelY = index == 0 ? 31.0 : bottom - 20;
        canvas.drawRect(
          Rect.fromLTWH(labelX - 3, labelY - 2, 53, 20),
          Paint()..color = scheme.surface,
        );
        _text(
          canvas,
          label,
          Offset(labelX, labelY),
          color: scheme.primary,
          bold: true,
        );
      }
      if (snap != null) {
        canvas.drawLine(
          Offset(_x(snap!), 43),
          Offset(_x(snap!), bottom),
          Paint()
            ..color = scheme.primary
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) => true;
}
