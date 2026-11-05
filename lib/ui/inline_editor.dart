import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/journal_controller.dart';
import '../data/store.dart';
import '../domain/model.dart';
import 'pickers.dart';

/// Where one record is filed while it is being edited: an optional project and
/// any number of tags. The two are independent, so a record may carry both.
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
      itemId = event.itemId,
      tagIds = event.tagIds,
      pickerOpen = column != EventColumn.title;
  final Event event;
  final EventColumn column;
  final bool inTimeline;
  final TextEditingController text;
  final focus = FocusNode();
  String? committedId;
  String? itemId;
  List<String> tagIds;
  bool ownerInputValid = true;
  bool pickerOpen;
  bool closed = false;
  String? error;

  /// Highlighted row of the name-column suggestions.
  int titleIndex = 0;

  /// Highlighted row of the owner list; -1 means nothing is highlighted.
  int ownerIndex = -1;
  Object? get value => switch (column) {
    EventColumn.title => (title: text.text, itemId: itemId, tagIds: tagIds),
    EventColumn.tag =>
      ownerInputValid
          ? (itemId: itemId, tagIds: tagIds)
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
  TextRange _composing = TextRange.empty;

  /// One arrow press is handled inside a single frame; a second delivery of
  /// the same press would otherwise move the highlight twice.
  bool _arrowLatch = false;

  bool get _isComposing {
    final range = widget.session.text.value.composing;
    return range.isValid && !range.isCollapsed;
  }

  void _submit() {
    if (_isComposing) return;
    final session = widget.session;
    if (session.column == EventColumn.tag) {
      if (session.pickerOpen) {
        _applyPendingOwner();
        widget.onCompleteTag();
        return;
      }
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

  /// Applies what the owner list is pointing at.
  ///
  /// Arrows win when used; otherwise typing then Enter or Tab takes the first
  /// match. An empty query points at nothing, so it never clears the owner.
  void _applyPendingOwner() {
    final session = widget.session;
    if (session.column != EventColumn.tag || !session.pickerOpen) return;
    final options = _ownerOptions();
    final index = session.ownerIndex >= 0
        ? session.ownerIndex.clamp(0, options.length - 1)
        : _ownerQuery.trim().isEmpty
        ? -1
        : 0;
    if (index < 0 || options.isEmpty) return;
    final option = options[index];
    // Enter can arrive from both the field and the wrapper; applying twice
    // would toggle the same tag back off.
    if (_isCurrent(option)) return;
    _applyOwner(option);
  }

  bool _isCurrent(OwnerRef? owner) {
    final session = widget.session;
    if (owner == null) return session.itemId == null && session.tagIds.isEmpty;
    if (owner.isItem) return session.itemId == owner.id;
    return session.tagIds.contains(owner.id);
  }

  /// Chooses a suggestion: the title and the classification it carries are
  /// committed together, so one keystroke records both.
  void _applyTitle(TitleChoice choice) {
    final session = widget.session;
    setState(() {
      session.text.text = choice.title;
      session.text.selection = TextSelection.collapsed(
        offset: choice.title.length,
      );
      if (choice.owner.isItem) {
        session.itemId = choice.owner.id;
        session.tagIds = normalizeTagIds([
          ...session.tagIds,
          ...widget.store.effectiveItemTagIds(choice.owner.id),
        ]);
      } else {
        session.tagIds = normalizeTagIds([...session.tagIds, choice.owner.id]);
      }
      session.pickerOpen = false;
      session.titleIndex = 0;
    });
    widget.onCommit();
  }

  /// Options for the current query, computed from the live text rather than
  /// the last built list: typing and pressing a key in the same frame must not
  /// act on the previous query.
  List<OwnerRef?> _ownerOptions() => matchingOwners(widget.store, _ownerQuery);

  /// Applies one owner choice to the pending classification.
  ///
  /// An item is single-valued and brings the tags it inherits; a tag toggles,
  /// so the same list both adds and removes. Nothing is written until commit.
  void _applyOwner(OwnerRef? owner) {
    final session = widget.session;
    setState(() {
      if (owner == null) {
        session.itemId = null;
        session.tagIds = const [];
      } else if (owner.isItem) {
        session.itemId = owner.id;
        session.tagIds = normalizeTagIds([
          ...session.tagIds,
          ...widget.store.effectiveItemTagIds(owner.id),
        ]);
      } else {
        // One tag is chosen at a time. Picking replaces the previous manual
        // tag while the tags inherited from the project stay attached, and
        // picking the same tag again falls back to just those defaults.
        final inherited = session.itemId == null
            ? const <String>[]
            : widget.store.effectiveItemTagIds(session.itemId!);
        session.tagIds = session.tagIds.contains(owner.id)
            ? normalizeTagIds(inherited)
            : normalizeTagIds([...inherited, owner.id]);
      }
      session.ownerInputValid = true;
      session.error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    // The wrapper Focus below already receives key events from the field, so
    // attaching the handler to the node as well would run it twice per press.
    if (widget.session.column == EventColumn.tag) {
      widget.session.text.text = widget.store.ownerName(widget.session.event);
    }
    // Ending an IME composition may not change the text at all, so the value
    // listener is what makes suggestions appear again after the candidate is
    // confirmed.
    widget.session.text.addListener(_onTextValueChanged);
  }

  @override
  void dispose() {
    widget.session.text.removeListener(_onTextValueChanged);
    super.dispose();
  }

  void _onTextValueChanged() {
    final session = widget.session;
    if (session.closed || !mounted) return;
    final composing = session.text.value.composing;
    final composingNow = composing.isValid && !composing.isCollapsed;
    final wasComposing = _composing.isValid && !_composing.isCollapsed;
    _composing = composing;
    if (session.column != EventColumn.title) return;
    if (wasComposing && !composingNow) {
      final hasChoices = titleChoices(
        widget.store,
        session.text.text,
      ).isNotEmpty;
      if (session.pickerOpen != hasChoices) {
        setState(() {
          session.titleIndex = 0;
          session.pickerOpen = hasChoices;
        });
      }
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_isComposing) return KeyEventResult.ignored;
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
        vertical) {
      final options = _ownerOptions();
      if (options.isNotEmpty && !_arrowLatch) {
        _arrowLatch = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _arrowLatch = false,
        );
        final delta = event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1;
        // The first match is what typing alone would take, so the first arrow
        // moves past it instead of landing on it again.
        final start = session.ownerIndex >= 0 ? session.ownerIndex : 0;
        session.ownerIndex = (start + delta).clamp(0, options.length - 1);
        setState(() {});
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab && !commandModifier) {
      _applyPendingOwner();
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
              session.ownerIndex = -1;
              session.pickerOpen = true;
            } else if (session.column == EventColumn.title) {
              session.titleIndex = 0;
              // Suggestions stay out of the way while an IME composes.
              session.pickerOpen =
                  !_isComposing && titleChoices(widget.store, text).isNotEmpty;
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
            itemId: session.itemId,
            tagIds: session.tagIds,
            query: _ownerQuery,
            highlighted: session.ownerIndex,
            onChoose: (OwnerRef? value) {
              // Picking from the list closes and saves, so a single click is
              // still enough; Enter and Tab go through the same path.
              _applyOwner(value);
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
