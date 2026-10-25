import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Interval;
import 'package:flutter/services.dart';

import '../application/journal_controller.dart';
import '../domain/appearance.dart';
import '../domain/journal_presentation.dart';
import '../domain/journal_view_preferences.dart';
import '../domain/model.dart';
import '../domain/timeline_interaction.dart';
import '../domain/timeline_axis.dart';
import 'hidden_events_dialog.dart';
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
    this.presentation,
    this.onShowAll,
  });
  final JournalController journal;
  final Future<bool> Function() beforeAction;
  final ValueChanged<String> onRename;
  final void Function(Offset, String?, DateTime) onContext;
  final ValueChanged<Object> onError;
  final String? editorEventId;
  final Widget? titleEditor;
  final JournalPresentation? presentation;
  final Future<void> Function()? onShowAll;
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
  double _anchorScroll = 0;
  double _scrollCompensation = 0;
  double _dragScale = 1;
  DateTime? _dragAnchorTime;
  bool _expandedDrag = false;
  bool _moved = false;
  int? _pointer;
  int? _pendingPointer;
  DateTime? _snap;
  String? _hoverId;
  Offset? _hoverPosition;
  MouseCursor _cursor = SystemMouseCursors.basic;
  Map<String, List<Rect>> _pieces = {};
  late TimelineAxis _layoutAxis = TimelineAxis(
    day: widget.journal.day,
    width: _dayWidth,
    events: const [],
  );
  TimelineAxis? _dragAxis;
  TimelineAxis get axis => _dragAxis ?? _layoutAxis;
  DateTime? _hoverFoldStart;
  bool _foldDialogOpen = false;
  late DateTime _axisDay = widget.journal.day;

  @override
  void didUpdateWidget(covariant Timeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_axisDay != widget.journal.day) {
      _axisDay = widget.journal.day;
      _original = null;
      _preview = null;
      _pointer = null;
      _pendingPointer = null;
      _dragAxis = null;
      _expandedDrag = false;
      _snap = null;
      _hoverId = null;
      _hoverFoldStart = null;
    }
  }

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
  JournalPresentation get _presentation =>
      widget.presentation ??
      JournalPresentation(
        tags: widget.journal.store.tags,
        autoUndefined: widget.journal.autoUndefined,
        view: JournalViewPreferences.fullDay,
      );
  List<Event> get _allDisplayEvents => [
    ..._events,
    if (widget.journal.autoUndefined)
      for (final gap in undefinedEvents([
        for (final event in widget.journal.regularEvents)
          event.id == _preview?.id ? _preview! : event,
      ], widget.journal.day))
        gap.copyWith(
          title: widget.journal.event(gap.id)?.title ?? gap.title,
          notes: widget.journal.event(gap.id)?.notes ?? gap.notes,
        ),
  ];
  List<Event> get _displayEvents =>
      _allDisplayEvents.where(_presentation.includes).toList()
        ..sort(compareEvents);
  double _x(DateTime value) => 24 + axis.x(value);
  Offset _content(Offset point) =>
      point +
      Offset(
        horizontal.hasClients ? horizontal.offset : 0,
        vertical.hasClients ? vertical.offset : 0,
      );
  TimelineAxisSpan? _foldHit(Offset point) =>
      point.dy >= 32 && point.dy <= _height - 26
      ? axis.foldAt(point.dx - 24)
      : null;

  String _clock(DateTime value) =>
      value == dayEnd(widget.journal.day) ? '24:00' : clockText(value);

  String _foldDescription(TimelineAxisSpan span) {
    return '${_clock(span.start)} — ${_clock(span.end)} · ${durationText(span.duration)}\n'
        '单击查看隐藏事项';
  }

  Future<void> showHiddenEvents() async {
    if (!await widget.beforeAction() || !mounted) return;
    await _showHiddenEvents();
  }

  Future<void> _showHiddenEvents({TimelineAxisSpan? span}) async {
    if (_foldDialogOpen || !mounted) return;
    _foldDialogOpen = true;
    try {
      final within = span == null ? null : Interval(span.start, span.end);
      await showHiddenEventsDialog(
        context,
        store: widget.journal.store,
        day: widget.journal.day,
        events: _presentation.hiddenEvents(
          _allDisplayEvents,
          widget.journal.day,
          within: within,
        ),
        within: within,
      );
    } finally {
      _foldDialogOpen = false;
    }
  }

  Event? _hit(Offset content) {
    // Narrow gaps must win exact hits before a neighbor's edge tolerance.
    for (final tolerance in [0.0, 2.0]) {
      for (final entry in _pieces.entries.toList().reversed) {
        if (entry.value.any(
          (rect) => rect.inflate(tolerance).contains(content),
        )) {
          return _displayEvents
              .where((event) => event.id == entry.key)
              .firstOrNull;
        }
      }
    }
    return null;
  }

  (Event, DragEdge)? _handle(Offset content) {
    final candidates = <(double, bool, Event, DragEdge)>[];
    for (final event in _events) {
      if (!widget.journal.canEditEvent(event)) continue;
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
    final fold = _foldHit(content);
    if (fold != null && handle == null) {
      if (!await widget.beforeAction() || !mounted) return;
      widget.journal.clearSelection();
      await _showHiddenEvents(span: fold);
      return;
    }
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
      orderedIds: _displayEvents.map((event) => event.id),
    );
    _focus.requestFocus();
    if (hit.isUndefined ||
        widget.editorEventId == hit.id ||
        !widget.journal.canEditEvent(hit)) {
      return;
    }
    setState(() {
      _dragAxis = axis;
      _dragScale = axis.pixelsPerMinute;
      _dragAnchorTime = axis.timeAt(content.dx - 24, snapFold: false);
      _anchorScroll = horizontal.hasClients ? horizontal.offset : 0;
      _scrollCompensation = 0;
      _expandedDrag = false;
      _original = widget.journal.event(hit.id);
      _preview = _original;
      _edge = handle?.$2 ?? DragEdge.move;
      _anchorX = pointer.localPosition.dx;
      _pointer = pointer.pointer;
      _moved = false;
      _hoverId = null;
    });
  }

  void _move(PointerMoveEvent pointer) {
    if (_original == null || _pointer != pointer.pointer) return;
    if (!widget.journal.canEditEvent(_original!)) {
      cancelDrag();
      return;
    }
    double dragPixels() =>
        pointer.localPosition.dx -
        _anchorX +
        (horizontal.hasClients ? horizontal.offset : 0) -
        _anchorScroll -
        _scrollCompensation;
    if (!_moved && dragPixels().abs() < (_edge == DragEdge.move ? 4 : 2)) {
      return;
    }
    if (!_moved && axis.isFolded) {
      // Preserve visible precision while editing, including newly exposed time.
      _dragAxis = TimelineAxis(
        day: widget.journal.day,
        width: _dragScale * 1440,
        events: const [],
      );
      _expandedDrag = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _original == null ||
            !_expandedDrag ||
            !horizontal.hasClients) {
          return;
        }
        final target = (_x(_dragAnchorTime!) - _anchorX).clamp(
          0.0,
          horizontal.position.maxScrollExtent,
        );
        _scrollCompensation += target - horizontal.offset;
        horizontal.jumpTo(target);
      });
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
      deltaMinutes: dragPixels() / _dragScale,
      dayWidth: _dragScale * 1440,
      events: _events,
      alt: HardwareKeyboard.instance.isAltPressed,
      granularity: widget.journal.dragMinutes,
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
    final restoreScroll = _expandedDrag ? _anchorScroll : null;
    setState(() {
      _original = null;
      _preview = null;
      _pointer = null;
      _snap = null;
      _moved = false;
      _dragAxis = null;
      _expandedDrag = false;
    });
    _restoreScroll(restoreScroll);
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
    final restoreScroll = _expandedDrag ? _anchorScroll : null;
    setState(() {
      _original = null;
      _preview = null;
      _pointer = null;
      _pendingPointer = null;
      _snap = null;
      _moved = false;
      _dragAxis = null;
      _expandedDrag = false;
    });
    _restoreScroll(restoreScroll);
    if (active) widget.journal.clearSelection();
  }

  void _restoreScroll(double? offset) {
    if (offset == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && horizontal.hasClients && _original == null) {
        horizontal.jumpTo(
          offset.clamp(0.0, horizontal.position.maxScrollExtent),
        );
      }
    });
  }

  void _hover(PointerHoverEvent pointer) {
    if (_original != null) return;
    final content = _content(pointer.localPosition);
    final handle = _handle(content);
    final fold = handle == null ? _foldHit(content) : null;
    final hit = _hit(content);
    setState(() {
      _cursor = fold != null
          ? SystemMouseCursors.click
          : handle != null
          ? SystemMouseCursors.resizeLeftRight
          : hit != null && !hit.isUndefined && widget.journal.canEditEvent(hit)
          ? SystemMouseCursors.move
          : SystemMouseCursors.basic;
      _hoverId = handle == null ? _hit(content)?.id : null;
      _hoverFoldStart = fold?.start;
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
        final anchor = axis.timeAt(
          _content(event.localPosition).dx - 24,
          snapFold: false,
        );
        setState(() {
          zoom = next;
          _hoverId = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && horizontal.hasClients) {
            horizontal.jumpTo(
              (_x(anchor) - event.localPosition.dx).clamp(
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
    final fold = _foldHit(point);
    if (fold != null) {
      unawaited(() async {
        if (await widget.beforeAction() && mounted) {
          await _showHiddenEvents(span: fold);
        }
      }());
      return;
    }
    final step = snapInterval(zoom);
    final minute =
        ((axis
                            .timeAt(point.dx - 24)
                            .difference(widget.journal.day)
                            .inMicroseconds /
                        Duration.microsecondsPerMinute /
                        step)
                    .round() *
                step)
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
        _dayWidth =
            _dragAxis?.width ?? math.max(650, constraints.maxWidth - 50) * zoom;
        _height = math.max(140, constraints.maxHeight - 14);
        final events = _displayEvents;
        final hiddenCount = _allDisplayEvents
            .where((event) => !_presentation.includes(event))
            .length;
        _layoutAxis = TimelineAxis(
          day: widget.journal.day,
          width: _dayWidth,
          events: events,
          foldEmptyTime: _presentation.foldsEmptyTime,
        );
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
        final hoverFold = axis.folds
            .where((span) => span.start == _hoverFoldStart)
            .firstOrNull;
        final hoverText = hover != null
            ? '${hover.title}\n${widget.journal.store.tagOutline(hover.tagId)}\n'
                  '${_clock(hover.intervalOn(widget.journal.day)!.start)} — '
                  '${_clock(hover.intervalOn(widget.journal.day)!.end)} · '
                  '${durationText(hover.intervalOn(widget.journal.day)!.duration)}'
            : hoverFold == null
            ? null
            : _foldDescription(hoverFold);
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
          onExit: (_) => setState(() {
            _hoverId = null;
            _hoverFoldStart = null;
          }),
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
              onDoubleTapDown: _pieces.isEmpty
                  ? null
                  : (pointer) {
                      final hit = _hit(_content(pointer.localPosition));
                      if (hit != null) {
                        cancelDrag();
                        widget.onRename(hit.id);
                      }
                    },
              onDoubleTap: _pieces.isEmpty ? null : () {},
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
                                    zoom: zoom,
                                    scheme: Theme.of(context).colorScheme,
                                    tagColors: tagColorOverrides(context),
                                    tagDisplays: tagDisplayOverrides(context),
                                    axis: axis,
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
                  if (_pieces.isEmpty)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            hiddenCount > 0
                                ? '当前没有可显示的事项，已隐藏 $hiddenCount 条记录。'
                                : events.isEmpty
                                ? '这一天还没有记录。'
                                : '补齐结束时间后，记录会显示在时间轴上。',
                          ),
                          if (hiddenCount > 0 && widget.onShowAll != null)
                            TextButton(
                              onPressed: widget.onShowAll,
                              child: const Text('显示全部事项'),
                            ),
                        ],
                      ),
                    ),
                  if (_expandedDrag)
                    const Positioned(
                      left: 24,
                      bottom: 14,
                      child: IgnorePointer(child: Text('拖动时临时展开 · 松手后恢复折叠')),
                    ),
                  if (hoverText != null && _hoverPosition != null)
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
                                hoverText,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
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
    required this.zoom,
    required this.scheme,
    required this.tagColors,
    required this.tagDisplays,
    required this.axis,
    required this.textStyle,
    this.preview,
    this.snap,
  });
  final JournalController journal;
  final List<Event> events;
  final Map<String, List<Rect>> pieces;
  final double zoom;
  final ColorScheme scheme;
  final Map<String, TagColor> tagColors;
  final Map<String, TagDisplay> tagDisplays;
  final TimelineAxis axis;
  final TextStyle textStyle;
  final Event? preview;
  final DateTime? snap;
  double _x(DateTime value) => 24 + axis.x(value);
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
    if (axis.isFolded) {
      major = const [1, 5, 10, 15, 30, 60, 120, 240, 480].firstWhere(
        (step) => axis.pixelsPerMinute * step >= 64,
        orElse: () => 1440,
      );
    } else {
      while (axis.pixelsPerMinute * major < 56) {
        major *= 2;
      }
    }
    var minor = major >= 120
        ? 60
        : major == 60
        ? 15
        : major == 30
        ? 10
        : 5;
    minor = math.min(minor, major);
    if (preview != null) minor = math.min(minor, snapInterval(zoom));
    bool visibleTime(DateTime value) =>
        !axis.isFolded ||
        axis.spans.any(
          (span) =>
              !span.folded &&
              !value.isBefore(span.start) &&
              !value.isAfter(span.end),
        );
    final labels = <DateTime>{};
    for (var minute = 0; minute <= 1440; minute += minor) {
      final time = journal.day.add(Duration(minutes: minute));
      if (!visibleTime(time)) continue;
      final x = _x(time);
      canvas.drawLine(
        Offset(x, 43),
        Offset(x, minute % major == 0 || preview != null ? bottom : 49),
        border,
      );
      if (minute % major == 0) {
        labels.add(time);
      }
    }
    if (axis.isFolded) {
      for (final span in axis.spans.where((span) => !span.folded)) {
        labels.addAll([span.start, span.end]);
      }
    }
    final orderedLabels = labels.toList()..sort();
    final positions = <(double, String)>[];
    for (final (index, time) in orderedLabels.indexed) {
      final left = (_x(time) - 18)
          .clamp(4.0, math.max(4.0, size.width - 43))
          .toDouble();
      if (index == orderedLabels.length - 1) {
        while (positions.length > 1 && left < positions.last.$1 + 44) {
          positions.removeLast();
        }
      }
      if (positions.isEmpty || left >= positions.last.$1 + 44) {
        positions.add((
          left,
          time == dayEnd(journal.day) ? '24:00' : clockText(time),
        ));
      }
    }
    for (final (left, text) in positions) {
      _text(canvas, text, Offset(left, 16));
    }
    for (final span in axis.folds) {
      final rect = Rect.fromLTRB(
        24 + span.left + 1,
        50,
        24 + span.right - 1,
        bottom,
      );
      if (rect.width > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()..color = scheme.surfaceContainerLow,
        );
      }
      final center = 24 + span.left + span.width / 2;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(24 + span.left, 30, 24 + span.right, bottom),
      );
      _text(
        canvas,
        '⋯',
        Offset(center - 6, (50 + bottom) / 2 - 8),
        color: scheme.outline,
      );
      canvas.restore();
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
      final (background, foreground) = eventColorsFor(
        journal.store,
        event,
        tagColors,
        selected: selected,
        tagDisplays: tagDisplays,
      );
      canvas.drawPath(path, Paint()..color = background);
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..color = selected ? scheme.onSurface : scheme.outline
        ..strokeWidth = selected ? 2 : 1;
      if (selected) {
        canvas.drawPath(path, outline);
      }
      final largest = rectangles.reduce(
        (a, b) => a.width * a.height >= b.width * b.height ? a : b,
      );
      if (largest.width >= 32 && largest.height >= 18) {
        final title = event.title.isEmpty ? '新事件' : event.title;
        if (axis.isFolded && largest.height >= 90) {
          final interval = event.intervalOn(journal.day)!;
          final primary = event.tagId == null
              ? title
              : journal.store.tagName(event.tagId);
          _text(
            canvas,
            primary,
            Offset(largest.left + 8, largest.center.dy - 35),
            width: largest.width - 14,
            color: foreground,
            bold: true,
          );
          if (primary != title) {
            _text(
              canvas,
              title,
              Offset(largest.left + 8, largest.center.dy - 15),
              width: largest.width - 14,
              color: foreground,
            );
          }
          if (largest.width >= 85) {
            _text(
              canvas,
              '${clockText(interval.start)}–${interval.end == dayEnd(journal.day) ? '24:00' : clockText(interval.end)}',
              Offset(largest.left + 8, largest.center.dy + 5),
              width: largest.width - 14,
              color: foreground,
            );
          }
          _text(
            canvas,
            durationText(interval.duration),
            Offset(largest.left + 8, largest.center.dy + 25),
            width: largest.width - 14,
            color: foreground,
          );
        } else {
          _text(
            canvas,
            title,
            Offset(largest.left + 8, largest.center.dy - 7),
            width: largest.width - 14,
            color: foreground,
            bold: selected,
          );
        }
      }
    }
    final now = civilTime(journal.clock());
    if (dayStart(now) == journal.day && axis.foldAt(axis.x(now)) == null) {
      final paint = Paint()
        ..color = scheme.tertiary
        ..strokeWidth = 2;
      canvas.drawLine(Offset(_x(now), 42), Offset(_x(now), bottom), paint);
    }
    if (axis.isFolded) {
      _text(
        canvas,
        '可见覆盖 ${durationText(axis.visibleDuration)}',
        Offset(24, size.height - 21),
        width: size.width - 48,
        color: scheme.onSurfaceVariant,
      );
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
