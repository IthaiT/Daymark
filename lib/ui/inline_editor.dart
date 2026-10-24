import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/journal_controller.dart';
import '../data/store.dart';
import '../domain/model.dart';
import 'pickers.dart';

class EditSession {
  EditSession(this.event, this.column, {this.inTimeline = false})
    : text = TextEditingController(
        text: switch (column) {
          EventColumn.title => event.title,
          EventColumn.tag => '',
          EventColumn.start =>
            '${dateText(event.start)} ${clockText(event.start)}',
          EventColumn.end =>
            '${dateText(event.end ?? event.start.add(const Duration(hours: 1)))} ${clockText(event.end ?? event.start.add(const Duration(hours: 1)))}',
        },
      ),
      tagId = event.tagId,
      pickerOpen = column != EventColumn.title;
  final Event event;
  final EventColumn column;
  final bool inTimeline;
  final TextEditingController text;
  final focus = FocusNode();
  String? committedId;
  String? tagId;
  bool tagInputValid = true;
  bool pickerOpen;
  bool closed = false;
  String? error;
  Object? get value => switch (column) {
    EventColumn.title => text.text,
    EventColumn.tag =>
      tagInputValid
          ? tagId
          : throw const FormatException('没有匹配的标签，请修改搜索内容或选择已有标签。'),
    EventColumn.start => parseEditorTime(text.text, event.start),
    EventColumn.end => parseEditorTime(
      text.text,
      event.end ?? event.start.add(const Duration(hours: 1)),
    ),
  };
  void dispose() {
    if (closed) return;
    closed = true;
    text.dispose();
    focus.dispose();
  }
}

class InlineEditor extends StatefulWidget {
  const InlineEditor({
    super.key,
    required this.session,
    required this.store,
    required this.day,
    required this.onCommit,
    required this.onCancel,
    required this.onNext,
  });
  final EditSession session;
  final Store store;
  final DateTime day;
  final Future<bool> Function() onCommit;
  final VoidCallback onCancel;
  final void Function(bool backwards) onNext;
  @override
  State<InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<InlineEditor> {
  final _tagChoices = GlobalKey<TagChoicesState>();
  String _tagQuery = '';
  @override
  void initState() {
    super.initState();
    widget.session.focus.onKeyEvent = _handleKey;
    if (widget.session.column == EventColumn.tag) {
      widget.session.text.text = widget.store.tagName(widget.session.tagId);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final session = widget.session;
    if (session.column == EventColumn.tag &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      final options =
          _tagChoices.currentState?.visibleIds ??
          matchingTagIds(widget.store, _tagQuery);
      if (options.isNotEmpty) {
        final index = options.indexOf(session.tagId);
        final next = index < 0
            ? 0
            : (index +
                      (event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1))
                  .clamp(0, options.length - 1);
        setState(() {
          session.tagId = options[next];
          session.tagInputValid = true;
          session.error = null;
          session.pickerOpen = true;
        });
      }
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (session.pickerOpen) {
        _closePicker();
      } else {
        widget.onCancel();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      widget.onNext(HardwareKeyboard.instance.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        session.column == EventColumn.tag) {
      widget.onCommit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _closePicker() {
    if (widget.session.closed || !mounted) return;
    setState(() => widget.session.pickerOpen = false);
    widget.session.focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Focus(
      onFocusChange: (focused) {
        if (!focused && !session.pickerOpen && !session.closed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!session.closed &&
                !session.focus.hasFocus &&
                !session.pickerOpen) {
              widget.onCommit();
            }
          });
        }
      },
      onKeyEvent: _handleKey,
      child: PickerPopup(
        open: session.pickerOpen,
        color: session.column == EventColumn.tag
            ? Theme.of(context).colorScheme.surfaceContainer
            : null,
        groupId: session,
        onClose: _closePicker,
        anchor: TextField(
          key: ValueKey('input-${session.event.id}-${session.column.name}'),
          groupId: session,
          controller: session.text,
          focusNode: session.focus,
          autofocus: true,
          decoration: InputDecoration(
            hintText: switch (session.column) {
              EventColumn.tag => '输入标签名称搜索',
              EventColumn.start || EventColumn.end => '例如 2021 或 20:21',
              EventColumn.title => null,
            },
            focusedBorder: session.error == null
                ? null
                : OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                      width: 2,
                    ),
                  ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
          ),
          onChanged: (text) => setState(() {
            session.error = null;
            if (session.column == EventColumn.tag) {
              _tagQuery = text;
              final options = matchingTagIds(widget.store, text);
              session.tagInputValid = options.isNotEmpty;
              if (options.isNotEmpty) session.tagId = options.first;
              session.pickerOpen = true;
            }
          }),
          onEditingComplete: () {},
          onSubmitted: (_) => widget.onCommit(),
          onTap: session.column == EventColumn.title
              ? null
              : () => setState(() => session.pickerOpen = true),
          onTapOutside: (_) {
            if (!session.pickerOpen) widget.onCommit();
          },
        ),
        builder: (context, close) => session.column == EventColumn.tag
            ? TagChoices(
                key: _tagChoices,
                store: widget.store,
                selected: session.tagId,
                query: _tagQuery,
                onChoose: (value) {
                  session.tagId = value;
                  session.tagInputValid = true;
                  session.text.text = widget.store.tagName(value);
                  close();
                  widget.onCommit();
                },
              )
            : DateTimeChoices(
                value: pickerInitialTime(
                  session.text.text,
                  (session.column == EventColumn.start
                          ? session.event.start
                          : session.event.end) ??
                      session.event.start.add(const Duration(hours: 1)),
                ),
                day: widget.day,
                onCancel: close,
                onChoose: (value) {
                  session.text.text = '${dateText(value)} ${clockText(value)}';
                  close();
                  widget.onCommit();
                },
              ),
      ),
    );
  }
}
