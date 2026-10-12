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
  String? tagId;
  bool pickerOpen;
  bool closed = false;
  String? error;
  Object? get value => switch (column) {
    EventColumn.title => text.text,
    EventColumn.tag => tagId,
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
    required this.onCommit,
    required this.onCancel,
    required this.onNext,
  });
  final EditSession session;
  final Store store;
  final Future<bool> Function() onCommit;
  final VoidCallback onCancel;
  final void Function(bool backwards) onNext;
  @override
  State<InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<InlineEditor> {
  @override
  void initState() {
    super.initState();
    widget.session.focus.onKeyEvent = _handleKey;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final session = widget.session;
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
          controller: session.column == EventColumn.tag ? null : session.text,
          focusNode: session.focus,
          autofocus: true,
          readOnly: session.column == EventColumn.tag,
          decoration: InputDecoration(
            hintText: session.column == EventColumn.tag
                ? widget.store.tagName(session.tagId)
                : null,
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
                store: widget.store,
                selected: session.tagId,
                onChoose: (value) {
                  session.tagId = value;
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
