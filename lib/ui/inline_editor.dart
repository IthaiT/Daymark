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
      owner = event.owner,
      pickerOpen = column != EventColumn.title;
  final Event event;
  final EventColumn column;
  final bool inTimeline;
  final TextEditingController text;
  final focus = FocusNode();
  String? committedId;
  OwnerRef? owner;
  bool ownerInputValid = true;
  bool pickerOpen;
  bool closed = false;
  String? error;

  /// Highlighted row of the name-column suggestions.
  int titleIndex = 0;
  Object? get value => switch (column) {
    EventColumn.title => (title: text.text, owner: owner),
    EventColumn.tag =>
      ownerInputValid
          ? owner
          : throw const FormatException('没有匹配的标签或项目，请修改搜索内容或选择已有项。'),
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
    required this.onCompleteTag,
    required this.onCancel,
    required this.onNext,
  });
  final EditSession session;
  final Store store;
  final DateTime day;
  final Future<bool> Function() onCommit;
  final VoidCallback onCompleteTag;
  final VoidCallback onCancel;
  final void Function(bool backwards) onNext;
  @override
  State<InlineEditor> createState() => _InlineEditorState();
}

class _InlineEditorState extends State<InlineEditor> {
  final _ownerChoices = GlobalKey<OwnerChoicesState>();
  String _ownerQuery = '';
  bool get _composing {
    final range = widget.session.text.value.composing;
    return range.isValid && !range.isCollapsed;
  }

  void _submit() {
    if (_composing) return;
    final session = widget.session;
    if (session.column == EventColumn.tag && session.pickerOpen) {
      widget.onCompleteTag();
      return;
    }
    if (session.column == EventColumn.title && session.pickerOpen) {
      final choices = titleChoices(widget.store, session.text.text);
      if (choices.isNotEmpty) {
        _applyTitle(choices[session.titleIndex.clamp(0, choices.length - 1)]);
        return;
      }
    }
    widget.onCommit();
  }

  /// Chooses a suggestion: the title and its owner are committed together, so
  /// one keystroke records both.
  void _applyTitle(TitleChoice choice) {
    final session = widget.session;
    setState(() {
      session.text.text = choice.title;
      session.text.selection = TextSelection.collapsed(
        offset: choice.title.length,
      );
      session.owner = choice.owner;
      session.pickerOpen = false;
      session.titleIndex = 0;
    });
    widget.onCommit();
  }

  @override
  void initState() {
    super.initState();
    widget.session.focus.onKeyEvent = _handleKey;
    if (widget.session.column == EventColumn.tag) {
      widget.session.text.text = widget.store.ownerLabel(widget.session.owner);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_composing) return KeyEventResult.ignored;
    final session = widget.session;
    final keyboard = HardwareKeyboard.instance;
    final commandModifier =
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed;
    final vertical =
        event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown;
    if (session.column == EventColumn.title &&
        session.pickerOpen &&
        !commandModifier &&
        !keyboard.isShiftPressed &&
        vertical) {
      final choices = titleChoices(widget.store, session.text.text);
      if (choices.isNotEmpty) {
        final delta = event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1;
        setState(() {
          session.titleIndex = (session.titleIndex + delta).clamp(
            0,
            choices.length - 1,
          );
        });
      }
      return KeyEventResult.handled;
    }
    if (session.column == EventColumn.tag &&
        !commandModifier &&
        !keyboard.isShiftPressed &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown)) {
      final current = session.owner;
      final options =
          _ownerChoices.currentState?.visibleOwners ??
          <OwnerRef?>[...matchingOwners(widget.store, _ownerQuery)];
      if (options.isNotEmpty) {
        final index = options.indexWhere(
          (owner) => owner == null
              ? current == null
              : current != null &&
                    current.id == owner.id &&
                    current.isItem == owner.isItem,
        );
        final next = index < 0
            ? 0
            : (index +
                      (event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1))
                  .clamp(0, options.length - 1);
        setState(() {
          session.owner = options[next];
          session.ownerInputValid = true;
          session.error = null;
          session.pickerOpen = true;
        });
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab && !commandModifier) {
      widget.onNext(keyboard.isShiftPressed);
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
    if ((event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        session.column == EventColumn.tag) {
      _submit();
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
            if (mounted &&
                !session.closed &&
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
              EventColumn.tag => '输入标签或项目搜索',
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
              _ownerQuery = text;
              final options = matchingOwners(widget.store, text);
              session.ownerInputValid = options.isNotEmpty;
              if (options.isNotEmpty) session.owner = options.first;
              session.pickerOpen = true;
            } else if (session.column == EventColumn.title) {
              session.titleIndex = 0;
              // Suggestions stay out of the way while an IME composes.
              session.pickerOpen =
                  !_composing && titleChoices(widget.store, text).isNotEmpty;
            }
          }),
          onEditingComplete: () {},
          onSubmitted: (_) => _submit(),
          onTap: session.column == EventColumn.title
              ? () => setState(() {
                  session.pickerOpen = titleChoices(
                    widget.store,
                    session.text.text,
                  ).isNotEmpty;
                })
              : () => setState(() => session.pickerOpen = true),
          onTapOutside: (_) {
            if (!session.pickerOpen) widget.onCommit();
          },
        ),
        builder: (context, close) => switch (session.column) {
          EventColumn.title => TitleChoices(
            store: widget.store,
            query: session.text.text,
            selected: session.titleIndex,
            onChoose: _applyTitle,
          ),
          EventColumn.tag => OwnerChoices(
            key: _ownerChoices,
            store: widget.store,
            selected: session.owner,
            query: _ownerQuery,
            onChoose: (value) {
              session.owner = value;
              session.ownerInputValid = true;
              session.text.text = widget.store.ownerLabel(value);
              close();
              widget.onCompleteTag();
            },
          ),
          _ => DateTimeChoices(
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
        },
      ),
    );
  }
}
