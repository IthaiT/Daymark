import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/journal_controller.dart';
import '../domain/appearance.dart';
import '../domain/event_clipboard.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'event_table.dart';
import 'inline_editor.dart';
import 'journal_viewport.dart';
import 'pickers.dart';
import 'tag_sidebar.dart';
import 'timeline.dart';
import 'title_bar.dart';
import 'workspace_style.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({
    super.key,
    required this.journal,
    this.showTitleBar = true,
    this.tagColors = const {},
    this.onTagColorChanged,
  });
  final JournalController journal;
  final bool showTitleBar;
  final Map<String, TagColor> tagColors;
  final Future<void> Function(String id, TagColor? color)? onTagColorChanged;
  @override
  State<JournalScreen> createState() => JournalScreenState();
}

class JournalScreenState extends State<JournalScreen> {
  final _table = GlobalKey<EventTableState>();
  final _timeline = GlobalKey<TimelineState>();
  final _focus = FocusNode();
  late final _date = TextEditingController(text: dateText(widget.journal.day));
  EditSession? _edit;
  Future<bool>? _committing;
  bool _calendarOpen = false;
  EventTableMode _tableMode = EventTableMode.chronological;
  @override
  void dispose() {
    _edit?.dispose();
    _date.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _showError(Object error) {
    if (!mounted) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('操作未完成'),
          content: Text(errorText(error)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> commit() {
    if (_committing != null) return _committing!;
    final session = _edit;
    if (session == null || session.closed) return Future.value(true);
    final result = _commitSession(session);
    _committing = result;
    unawaited(result.whenComplete(() => _committing = null));
    return result;
  }

  Future<bool> _commitSession(EditSession session) async {
    try {
      session.committedId = await widget.journal.editCell(
        session.event.id,
        session.column,
        session.value,
      );
      if (mounted && identical(_edit, session)) {
        setState(() => _edit = null);
        // Keep the controller alive until the old field leaves the widget tree.
        WidgetsBinding.instance.addPostFrameCallback((_) => session.dispose());
        _focus.requestFocus();
      }
      return true;
    } catch (error) {
      if (mounted && !session.closed) {
        setState(() => session.error = errorText(error));
        session.focus.requestFocus();
      }
      return false;
    }
  }

  Future<void> _action(
    Future<void> Function() action, {
    bool clear = false,
  }) async {
    if (!await commit() || !mounted) return;
    try {
      await action();
      if (clear) widget.journal.clearSelection();
    } catch (error) {
      _showError(error);
    }
    if (mounted) _date.text = dateText(widget.journal.day);
  }

  Future<bool> _beforeAction() async {
    if (!await commit()) return false;
    widget.journal.clearSelection();
    return true;
  }

  Future<void> _clear() async {
    if (await commit() && mounted) {
      widget.journal.clearSelection();
      _focus.requestFocus();
    }
  }

  Future<void> _startEdit(
    String id,
    EventColumn column, {
    bool timeline = false,
  }) async {
    if (!await commit() || !mounted) return;
    final event = widget.journal.event(id);
    if (event == null ||
        event.isUndefined &&
            column != EventColumn.title &&
            column != EventColumn.tag) {
      return;
    }
    widget.journal.select(id);
    final session = EditSession(event, column, inTimeline: timeline);
    setState(() => _edit = session);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_edit, session) && !session.closed) {
        session.focus.requestFocus();
        session.text.selection = TextSelection(
          baseOffset: 0,
          extentOffset: session.text.text.length,
        );
      }
    });
  }

  Future<void> _cell(String id, EventColumn? column) async {
    final alreadySelected = widget.journal.selected.contains(id);
    final wasEditing = _edit != null;
    final sameRow = _edit?.event.id == id;
    if (!await commit() || !mounted) return;
    final control = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    widget.journal.select(
      id,
      toggle: control,
      range: shift,
      orderedIds: _table.currentState?.selectionOrder,
    );
    _focus.requestFocus();
    if (!control &&
        !shift &&
        column != null &&
        (alreadySelected || wasEditing && sameRow)) {
      await _startEdit(id, column);
    }
  }

  Future<void> _add([DateTime? start]) async {
    if (!await commit() || !mounted) return;
    try {
      final id = await widget.journal.addDraft(start: start);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _table.currentState?.reveal(id);
          unawaited(_startEdit(id, EventColumn.title));
        }
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _cancelEdit() async {
    final session = _edit;
    if (session == null || _committing != null) return;
    if (widget.journal.drafts.containsKey(session.event.id)) {
      try {
        await widget.journal.discardDraft(session.event.id);
      } catch (error) {
        _showError(error);
        return;
      }
    }
    if (!mounted) return;
    setState(() => _edit = null);
    WidgetsBinding.instance.addPostFrameCallback((_) => session.dispose());
    _focus.requestFocus();
  }

  Future<void> _copy() async {
    if (!await commit() || !mounted) return;
    try {
      final clipboard = widget.journal.copySelected();
      if (clipboard != null) {
        await Clipboard.setData(ClipboardData(text: clipboard.encode()));
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _paste() async {
    if (!await commit() || !mounted) return;
    _timeline.currentState?.cancelDrag();
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      final clipboard = EventClipboard.tryDecode(data?.text);
      if (clipboard == null) return;
      final ids = await widget.journal.pasteEvents(clipboard);
      if (!mounted || ids.isEmpty) return;
      _focus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _table.currentState?.reveal(ids.first);
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _moveSelection(int direction) async {
    if (_edit != null) return;
    final order = _table.currentState?.selectionOrder.toList() ?? <String>[];
    if (order.isEmpty) return;
    final selected = widget.journal.selected;
    final index = direction > 0
        ? order.lastIndexWhere(selected.contains)
        : order.indexWhere(selected.contains);
    final next = index < 0
        ? (direction > 0 ? 0 : order.length - 1)
        : (index + direction).clamp(0, order.length - 1);
    widget.journal.select(order[next]);
    _table.currentState?.reveal(order[next]);
    _focus.requestFocus();
  }

  KeyEventResult _tableKey(FocusNode node, KeyEvent event) {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused?.widget is EditableText ||
        focused?.findAncestorStateOfType<EditableTextState>() != null ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (!HardwareKeyboard.instance.isControlPressed) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        unawaited(
          _moveSelection(
            event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1,
          ),
        );
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          widget.journal.selected.length == 1) {
        unawaited(
          _startEdit(widget.journal.selected.single, EventColumn.title),
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      unawaited(_copy());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV) {
      unawaited(_paste());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _next(bool backwards) async {
    final session = _edit;
    if (session == null || !await commit()) return;
    final index =
        EventColumn.values.indexOf(session.column) + (backwards ? -1 : 1);
    if (index >= 0 && index < EventColumn.values.length) {
      await _startEdit(
        session.committedId ?? session.event.id,
        EventColumn.values[index],
      );
    }
  }

  Widget? _editor() => _edit == null
      ? null
      : InlineEditor(
          key: ObjectKey(_edit),
          session: _edit!,
          store: widget.journal.store,
          day: widget.journal.day,
          onCommit: commit,
          onCancel: () => unawaited(_cancelEdit()),
          onNext: (backwards) => unawaited(_next(backwards)),
        );

  Future<void> _context(Offset position, String? id, {DateTime? start}) async {
    if (!await commit() || !mounted) return;
    _timeline.currentState?.cancelDrag();
    if (id != null && !widget.journal.selected.contains(id)) {
      widget.journal.select(id);
    }
    final event = id == null ? null : widget.journal.event(id);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (start != null)
          const PopupMenuItem(value: 'add', child: Text('在此新增事件')),
        if (event?.isUndefined == true)
          const PopupMenuItem(value: 'tag', child: Text('设置标签')),
        if (event != null && !event.isUndefined) ...[
          const PopupMenuItem(value: 'delete', child: Text('删除')),
          if (!widget.journal.drafts.containsKey(id))
            const PopupMenuItem(value: 'details', child: Text('编辑详情')),
        ],
      ],
    );
    if (!mounted) return;
    switch (value) {
      case 'add':
        await _add(start);
      case 'tag':
        await _startEdit(id!, EventColumn.tag);
      case 'delete':
        await _action(widget.journal.deleteSelected);
      case 'details':
        await showEventEditor(context, widget.journal, event!);
    }
  }

  Future<void> _setDate() async {
    final requested = _date.text;
    await _action(
      () => widget.journal.setDay(parseDate(requested)),
      clear: true,
    );
  }

  Future<void> _setTableMode(EventTableMode mode) async {
    if (_tableMode == mode || !await commit() || !mounted) return;
    setState(() => _tableMode = mode);
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
          unawaited(_add()),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () =>
          unawaited(_action(() => widget.journal.shiftDay(-1), clear: true)),
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () =>
          unawaited(_action(() => widget.journal.shiftDay(1), clear: true)),
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          unawaited(
            _action(() async {
              await widget.journal.undo();
            }),
          ),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
          unawaited(
            _action(() async {
              await widget.journal.redo();
            }),
          ),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): () => unawaited(
        _action(() async {
          await widget.journal.redo();
        }),
      ),
      const SingleActivator(LogicalKeyboardKey.delete): () {
        if (_edit == null) unawaited(_action(widget.journal.deleteSelected));
      },
    },
    child: Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _tableKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => unawaited(_clear()),
        child: Scaffold(
          body: Column(
            children: [
              if (widget.showTitleBar) const WindowTitleBar(),
              Expanded(
                child: AnimatedBuilder(
                  animation: widget.journal,
                  builder: (context, _) => JournalViewport(
                    child: WorkspaceLayout(
                      sidebar: TagSidebar(
                        journal: widget.journal,
                        beforeAction: _beforeAction,
                        onError: _showError,
                        tagColors: widget.tagColors,
                        onTagColorChanged: widget.onTagColorChanged,
                      ),
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                key: const ValueKey('previous-day'),
                                tooltip: '前一天',
                                onPressed: () => unawaited(
                                  _action(
                                    () => widget.journal.shiftDay(-1),
                                    clear: true,
                                  ),
                                ),
                                icon: const Icon(Icons.chevron_left),
                              ),
                              SizedBox(
                                width: 170,
                                child: PickerPopup(
                                  open: _calendarOpen,
                                  width: 320,
                                  onClose: () =>
                                      setState(() => _calendarOpen = false),
                                  anchor: TextField(
                                    key: const ValueKey('day-input'),
                                    controller: _date,
                                    decoration: const InputDecoration(
                                      suffixIcon: Icon(
                                        Icons.calendar_today,
                                        size: 18,
                                      ),
                                    ),
                                    onSubmitted: (_) => unawaited(_setDate()),
                                    onTap: () async {
                                      if (await commit() && mounted) {
                                        setState(() => _calendarOpen = true);
                                      }
                                    },
                                  ),
                                  builder: (context, close) => CalendarChoices(
                                    value: widget.journal.day,
                                    onChoose: (value) {
                                      close();
                                      unawaited(
                                        _action(
                                          () => widget.journal.setDay(value),
                                          clear: true,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('next-day'),
                                tooltip: '后一天',
                                onPressed: () => unawaited(
                                  _action(
                                    () => widget.journal.shiftDay(1),
                                    clear: true,
                                  ),
                                ),
                                icon: const Icon(Icons.chevron_right),
                              ),
                              TextButton(
                                onPressed: () => unawaited(
                                  _action(
                                    () => widget.journal.setDay(
                                      dayStart(widget.journal.clock()),
                                    ),
                                    clear: true,
                                  ),
                                ),
                                child: const Text('今天'),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                '星期${'一二三四五六日'[widget.journal.day.weekday - 1]}',
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: WorkspacePanel(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Timeline(
                                  key: _timeline,
                                  journal: widget.journal,
                                  beforeAction: commit,
                                  onRename: (id) => unawaited(
                                    _startEdit(
                                      id,
                                      EventColumn.title,
                                      timeline: true,
                                    ),
                                  ),
                                  onContext: (position, id, start) => unawaited(
                                    _context(position, id, start: start),
                                  ),
                                  onError: _showError,
                                  editorEventId: _edit?.inTimeline == true
                                      ? _edit?.event.id
                                      : null,
                                  titleEditor: _edit?.inTimeline == true
                                      ? _editor()
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              AppSegmentedButton<EventTableMode>(
                                segments: const [
                                  ButtonSegment(
                                    value: EventTableMode.chronological,
                                    label: Text('时间顺序'),
                                    icon: Icon(Icons.schedule),
                                  ),
                                  ButtonSegment(
                                    value: EventTableMode.summary,
                                    label: Text('汇总'),
                                    icon: Icon(Icons.view_agenda_outlined),
                                  ),
                                ],
                                selected: {_tableMode},
                                onSelectionChanged: (values) =>
                                    unawaited(_setTableMode(values.single)),
                              ),
                              const Spacer(),
                              FilledButton.icon(
                                key: const ValueKey('add-event'),
                                onPressed: () => unawaited(_add()),
                                icon: const Icon(Icons.add),
                                label: const Text('新增事件'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: WorkspacePanel(
                              child: EventTable(
                                key: _table,
                                journal: widget.journal,
                                mode: _tableMode,
                                onCell: (id, column) =>
                                    unawaited(_cell(id, column)),
                                onBlank: () => unawaited(_clear()),
                                onAdd: () => unawaited(_add()),
                                onContext: (position, id) =>
                                    unawaited(_context(position, id)),
                                beforeScroll: commit,
                                editorId: _edit?.inTimeline == false
                                    ? _edit?.event.id
                                    : null,
                                editorColumn: _edit?.inTimeline == false
                                    ? _edit?.column
                                    : null,
                                editor: _edit?.inTimeline == false
                                    ? _editor()
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
