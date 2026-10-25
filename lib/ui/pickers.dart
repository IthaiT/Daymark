import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../domain/model.dart';
import '../domain/unicode.dart';
import 'tag_tree_tile.dart';

/// Open a picker at the current input without replacing invalid typed text.
DateTime pickerInitialTime(String text, DateTime fallback) {
  try {
    return parseEditorTime(text, fallback);
  } on FormatException {
    return fallback;
  }
}

/// An anchored, focusable overlay. Outside taps continue to their target.
class PickerPopup extends StatefulWidget {
  const PickerPopup({
    super.key,
    required this.anchor,
    required this.builder,
    required this.open,
    required this.onClose,
    this.width = 340,
    this.groupId,
    this.color,
  });
  final Widget anchor;
  final Widget Function(BuildContext, VoidCallback) builder;
  final bool open;
  final VoidCallback onClose;
  final double width;
  final Object? groupId;
  final Color? color;
  @override
  State<PickerPopup> createState() => _PickerPopupState();
}

class _PickerPopupState extends State<PickerPopup> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _group = Object();
  final _anchorKey = GlobalKey();
  @override
  void didUpdateWidget(PickerPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (widget.open) {
          _portal.show();
        } else {
          _portal.hide();
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.open) _portal.show();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // A popup opened from another popup joins that popup's region, so a tap
    // inside the parent keeps both open. Its own region is what a tap elsewhere
    // - including on the parent - dismisses, so a nested picker closes alone
    // instead of taking the whole stack with it.
    final parentGroup = widget.groupId ?? _PickerGroupScope.maybeOf(context);
    return CompositedTransformTarget(
      key: _anchorKey,
      link: _link,
      child: TapRegion(
        groupId: parentGroup ?? _group,
        child: TapRegion(
          groupId: _group,
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (overlayContext) {
              final screen = MediaQuery.sizeOf(overlayContext);
              final box =
                  _anchorKey.currentContext?.findRenderObject() as RenderBox?;
              final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
              final height = box?.size.height ?? 36;
              final below = screen.height - position.dy - height - 8;
              final above = position.dy - 8;
              final up = below < 250 && above > below;
              final width = widget.width.clamp(0.0, screen.width - 16);
              final left = position.dx.clamp(8.0, screen.width - width - 8);
              return Positioned(
                width: width,
                child: CompositedTransformFollower(
                  link: _link,
                  showWhenUnlinked: false,
                  targetAnchor: up ? Alignment.topLeft : Alignment.bottomLeft,
                  followerAnchor: up ? Alignment.bottomLeft : Alignment.topLeft,
                  offset: Offset(left - position.dx, up ? -4 : 4),
                  child: TapRegion(
                    groupId: parentGroup ?? _group,
                    child: TapRegion(
                      groupId: _group,
                      onTapOutside: (_) => widget.onClose(),
                      child: Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.escape) {
                            widget.onClose();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Material(
                          color: widget.color,
                          elevation: 8,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: (up ? above : below).clamp(
                                80.0,
                                screen.height * .65,
                              ),
                            ),
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: _PickerGroupScope(
                                  group: _group,
                                  child: widget.builder(
                                    overlayContext,
                                    widget.onClose,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: widget.anchor,
          ),
        ),
      ),
    );
  }
}

class _PickerGroupScope extends InheritedWidget {
  const _PickerGroupScope({required this.group, required super.child});
  final Object group;
  static Object? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PickerGroupScope>()?.group;
  @override
  bool updateShouldNotify(_PickerGroupScope oldWidget) =>
      group != oldWidget.group;
}

/// Search full tag paths, keeping stable IDs even when names are repeated.
List<String?> matchingTagIds(
  Store store,
  String query, {
  Set<String> excluded = const {},
  String emptyLabel = '未分类',
  bool includeUnclassified = true,
}) {
  final needle = caseFold(query.trim());
  return [
    if (includeUnclassified && caseFold(emptyLabel).contains(needle)) null,
    for (final tag in store.orderedTags())
      if (!excluded.contains(tag.id) &&
          caseFold(
            store.ancestors(tag.id).map((tag) => tag.name).join(' / '),
          ).contains(needle))
        tag.id,
  ];
}

class TagChoices extends StatefulWidget {
  const TagChoices({
    super.key,
    required this.store,
    required this.onChoose,
    this.selected,
    this.excluded = const {},
    this.emptyLabel = '未分类',
    this.query = '',
    this.showSelection = true,
    this.includeUnclassified = true,
  });
  final Store store;
  final ValueChanged<String?> onChoose;
  final String? selected;
  final Set<String> excluded;
  final String emptyLabel;
  final String query;
  final bool showSelection;
  final bool includeUnclassified;
  @override
  State<TagChoices> createState() => TagChoicesState();
}

class TagChoicesState extends State<TagChoices> {
  final _collapsed = <String>{};
  final _highlight = GlobalKey();

  List<String?> get visibleIds =>
      matchingTagIds(
            widget.store,
            widget.query,
            excluded: widget.excluded,
            emptyLabel: widget.emptyLabel,
            includeUnclassified: widget.includeUnclassified,
          )
          .where(
            (id) =>
                id == null ||
                widget.query.trim().isNotEmpty ||
                !widget.store
                    .ancestors(id)
                    .take(widget.store.ancestors(id).length - 1)
                    .any((parent) => _collapsed.contains(parent.id)),
          )
          .toList();

  @override
  void didUpdateWidget(TagChoices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.query != widget.query ||
        oldWidget.showSelection != widget.showSelection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _highlight.currentContext;
        if (mounted && target != null) {
          Scrollable.ensureVisible(target, duration: Duration.zero);
        }
      });
    }
  }

  Widget _tile(String? id) => KeyedSubtree(
    key: widget.showSelection && id == widget.selected
        ? _highlight
        : ValueKey(('tag-option', id)),
    child: id == null
        ? TagTreeTile(
            key: const ValueKey('tag-choice-unclassified'),
            store: widget.store,
            selected: widget.showSelection && widget.selected == null,
            label: widget.emptyLabel,
            onTap: () => widget.onChoose(null),
          )
        : TagTreeTile(
            key: ValueKey('tag-choice-$id'),
            store: widget.store,
            tagId: id,
            label: widget.query.trim().isEmpty
                ? widget.store.tagName(id)
                : widget.store.ancestors(id).map((tag) => tag.name).join(' / '),
            depth: widget.query.trim().isEmpty
                ? widget.store.ancestors(id).length - 1
                : 0,
            selected: widget.showSelection && widget.selected == id,
            collapsed: _collapsed.contains(id),
            onToggle:
                widget.query.trim().isEmpty &&
                    widget.store.tags.values.any(
                      (child) => child.parentId == id,
                    )
                ? () => setState(() {
                    if (!_collapsed.add(id)) _collapsed.remove(id);
                  })
                : null,
            onTap: () => widget.onChoose(id),
          ),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (visibleIds.isEmpty) const Text('没有匹配的标签'),
      for (final id in visibleIds) _tile(id),
    ],
  );
}

/// Search input using the same paths, tree and popup as event tag completion.
class TagSearchField extends StatefulWidget {
  const TagSearchField({
    super.key,
    required this.store,
    required this.value,
    required this.onChanged,
    this.allSelected = false,
    this.onChooseAll,
    this.clearAfterSelection = false,
    this.chips = const [],
    this.excluded = const {},
  }) : assert(!allSelected || onChooseAll != null);

  final Store store;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool allSelected;
  final VoidCallback? onChooseAll;
  final bool clearAfterSelection;
  final List<Widget> chips;
  final Set<String?> excluded;

  @override
  State<TagSearchField> createState() => _TagSearchFieldState();
}

typedef _TagSearchOption = ({String? id, bool all});

class _TagSearchFieldState extends State<TagSearchField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _choices = GlobalKey<TagChoicesState>();
  final _allChoice = GlobalKey();
  final _group = Object();
  bool _open = false;
  String _query = '';
  late String _label;
  _TagSearchOption? _active;

  String get _selectionLabel => widget.clearAfterSelection
      ? ''
      : widget.allSelected
      ? '全部标签'
      : widget.value == null
      ? '未分类'
      : widget.store.ancestors(widget.value).map((tag) => tag.name).join(' / ');

  bool get _composing =>
      _text.value.composing.isValid && !_text.value.composing.isCollapsed;

  List<_TagSearchOption> _options({bool visible = false}) => [
    if (widget.onChooseAll != null &&
        caseFold('全部标签').contains(caseFold(_query.trim())))
      (id: null, all: true),
    for (final id
        in visible
            ? _choices.currentState?.visibleIds ?? _matchingIds()
            : _matchingIds())
      (id: id, all: false),
  ];

  List<String?> _matchingIds() => matchingTagIds(
    widget.store,
    _query,
    excluded: widget.excluded.nonNulls.toSet(),
    includeUnclassified: !widget.excluded.contains(null),
  );

  @override
  void initState() {
    super.initState();
    _label = _selectionLabel;
    _restoreText();
    _focus.onKeyEvent = _handleKey;
    _focus.addListener(_focusChanged);
  }

  @override
  void didUpdateWidget(TagSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final label = _selectionLabel;
    if (!widget.clearAfterSelection &&
        (oldWidget.value != widget.value ||
            oldWidget.allSelected != widget.allSelected ||
            label != _label)) {
      _label = label;
      _open = false;
      _query = '';
      _restoreText();
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _restoreText() {
    _text.value = TextEditingValue(
      text: _label,
      selection: TextSelection.collapsed(offset: _label.length),
    );
  }

  void _focusChanged() {
    if (_focus.hasFocus) {
      _show();
    } else {
      _close();
    }
    if (widget.clearAfterSelection) setState(() {});
  }

  void _show() {
    if (_open) return;
    setState(() {
      _open = true;
      _query = '';
      _active = widget.clearAfterSelection
          ? _options().firstOrNull
          : (id: widget.value, all: widget.allSelected);
      _text.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _text.text.length,
      );
    });
  }

  void _close() {
    if (!_open) return;
    setState(() {
      _open = false;
      _query = '';
      _restoreText();
    });
  }

  void _choose(_TagSearchOption option) {
    if (widget.clearAfterSelection && !option.all) {
      setState(() {
        _query = '';
        _active = null;
        _text.clear();
      });
      _focus.requestFocus();
      widget.onChanged(option.id);
      return;
    }
    _close();
    if (option.all) {
      widget.onChooseAll?.call();
    } else {
      widget.onChanged(option.id);
    }
  }

  void _confirm() {
    if (_composing || !_open || _active == null) return;
    _choose(_active!);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) || _composing) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _close();
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _show();
      final options = _options(visible: true);
      if (options.isNotEmpty) {
        final active = _active;
        final index = active == null ? -1 : options.indexOf(active);
        final next = index < 0
            ? 0
            : (index +
                      (event.logicalKey == LogicalKeyboardKey.arrowUp ? -1 : 1))
                  .clamp(0, options.length - 1);
        setState(() => _active = options[next]);
        if (_active!.all) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final target = _allChoice.currentContext;
            if (mounted && target != null) Scrollable.ensureVisible(target);
          });
        }
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _confirm();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final input = TextField(
      groupId: _group,
      controller: _text,
      focusNode: _focus,
      decoration: widget.clearAfterSelection
          ? const InputDecoration(
              hintText: '搜索标签',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            )
          : const InputDecoration(
              hintText: '输入标签名称搜索',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
      onTap: _show,
      onChanged: (text) => setState(() {
        _query = text;
        _open = true;
        _active = _options().firstOrNull;
      }),
      onEditingComplete: () {},
      onSubmitted: (_) => _confirm(),
      onTapOutside: (_) => _close(),
    );
    return PickerPopup(
      open: _open,
      groupId: _group,
      color: Theme.of(context).colorScheme.surfaceContainer,
      onClose: _close,
      anchor: !widget.clearAfterSelection
          ? input
          : GestureDetector(
              onTap: () {
                _focus.requestFocus();
                _show();
              },
              child: InputDecorator(
                isFocused: _focus.hasFocus,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
                child: SizedBox(
                  height: 70,
                  child: SingleChildScrollView(
                    key: const ValueKey('tag-search-chips'),
                    primary: false,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 70),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        heightFactor: 1,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ...widget.chips,
                            SizedBox(
                              key: const ValueKey('tag-search-input'),
                              width: 180,
                              child: input,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
      builder: (context, close) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_options().any((option) => option.all))
            TagTreeTile(
              key: _allChoice,
              store: widget.store,
              label: '全部标签',
              selected: _active?.all == true,
              onTap: () => _choose((id: null, all: true)),
            ),
          if (_options().any((option) => !option.all) || _options().isEmpty)
            TagChoices(
              key: _choices,
              store: widget.store,
              query: _query,
              excluded: widget.excluded.nonNulls.toSet(),
              includeUnclassified: !widget.excluded.contains(null),
              selected: _active?.id,
              showSelection: _active != null && !_active!.all,
              onChoose: (id) => _choose((id: id, all: false)),
            ),
        ],
      ),
    );
  }
}

class TagField extends StatefulWidget {
  const TagField({
    super.key,
    required this.store,
    required this.value,
    required this.onChanged,
    this.excluded = const {},
    this.emptyLabel = '未分类',
  });
  final Store store;
  final String? value;
  final ValueChanged<String?> onChanged;
  final Set<String> excluded;
  final String emptyLabel;
  @override
  State<TagField> createState() => _TagFieldState();
}

class _TagFieldState extends State<TagField> {
  bool _open = false;
  @override
  Widget build(BuildContext context) => PickerPopup(
    open: _open,
    color: Theme.of(context).colorScheme.surfaceContainer,
    onClose: () => setState(() => _open = false),
    anchor: OutlinedButton(
      onPressed: () => setState(() => _open = !_open),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.value == null
                  ? widget.emptyLabel
                  : widget.store.tagName(widget.value),
            ),
          ),
          const Icon(Icons.expand_more),
        ],
      ),
    ),
    builder: (context, close) => TagChoices(
      store: widget.store,
      selected: widget.value,
      excluded: widget.excluded,
      emptyLabel: widget.emptyLabel,
      onChoose: (value) {
        close();
        widget.onChanged(value);
      },
    ),
  );
}

class CalendarChoices extends StatelessWidget {
  const CalendarChoices({
    super.key,
    required this.value,
    required this.onChoose,
  });
  final DateTime value;
  final ValueChanged<DateTime> onChoose;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CalendarDatePicker(
        initialDate: DateTime(value.year, value.month, value.day),
        firstDate: DateTime(1),
        lastDate: DateTime(9999, 12, 31),
        onDateChanged: (date) => onChoose(dayStart(date)),
      ),
      TextButton(
        onPressed: () => onChoose(dayStart(DateTime.now())),
        child: const Text('今天'),
      ),
    ],
  );
}

/// Hour and minute columns. The picked tile keeps a filled background, so a
/// manual choice is always identifiable.
class TimeChoices extends StatefulWidget {
  const TimeChoices({
    super.key,
    required this.value,
    required this.onChoose,
    this.onChanged,
    this.onNow,
  });
  final DateTime value;
  final ValueChanged<DateTime> onChoose;

  /// Reports every manual hour or minute pick, so the caller can preview the
  /// pending time while this picker stays open.
  final ValueChanged<DateTime>? onChanged;

  /// Takes over the "现在" button so it can set the whole timestamp, date
  /// included, instead of only the clock part.
  final VoidCallback? onNow;
  @override
  State<TimeChoices> createState() => _TimeChoicesState();
}

class _TimeChoicesState extends State<TimeChoices> {
  static const _extent = 36.0;
  static const _viewport = 180.0;
  late int _hour = widget.value.hour;
  late int _minute = widget.value.minute;
  late final _hours = ScrollController(
    initialScrollOffset: _centeredOffset(_hour, 24),
  );
  late final _minutes = ScrollController(
    initialScrollOffset: _centeredOffset(_minute, 60),
  );

  static double _centeredOffset(int index, int count) =>
      (index * _extent - (_viewport - _extent) / 2).clamp(
        0.0,
        count * _extent - _viewport,
      );

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  DateTime get _time => DateTime.utc(
    widget.value.year,
    widget.value.month,
    widget.value.day,
    _hour,
    _minute,
  );

  void _pick({required bool hours, required int value}) {
    setState(() {
      if (hours) {
        _hour = value;
      } else {
        _minute = value;
      }
    });
    widget.onChanged?.call(_time);
  }

  void _reveal(ScrollController controller, int index, int count) {
    if (!controller.hasClients) return;
    controller.animateTo(
      _centeredOffset(index, count),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _tile(int value, {required bool hours}) {
    final scheme = Theme.of(context).colorScheme;
    final selected = value == (hours ? _hour : _minute);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        key: ValueKey('time-${hours ? 'hour' : 'minute'}-$value'),
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _pick(hours: hours, value: value),
          child: Center(
            child: Text(
              value.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (final hours in [true, false])
              Expanded(
                child: Column(
                  children: [
                    Text(
                      hours ? '小时' : '分钟',
                      style: theme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: _viewport,
                      child: Scrollbar(
                        controller: hours ? _hours : _minutes,
                        child: ListView.builder(
                          controller: hours ? _hours : _minutes,
                          itemExtent: _extent,
                          itemCount: hours ? 24 : 60,
                          itemBuilder: (context, index) =>
                              _tile(index, hours: hours),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        Row(
          children: [
            TextButton(
              onPressed: () {
                if (widget.onNow != null) {
                  widget.onNow!();
                  return;
                }
                final now = DateTime.now();
                setState(() {
                  _hour = now.hour;
                  _minute = now.minute;
                });
                widget.onChanged?.call(_time);
                _reveal(_hours, _hour, 24);
                _reveal(_minutes, _minute, 60);
              },
              child: const Text('现在'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => widget.onChoose(_time),
              child: const Text('确定'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The day before, the viewed day itself and the day after. Records never
/// realistically start further away, so three choices beat a full calendar.
class DayChoices extends StatelessWidget {
  const DayChoices({
    super.key,
    required this.day,
    required this.value,
    required this.onChoose,
  });

  /// The viewed day; the choices follow it instead of the wall clock.
  final DateTime day;
  final DateTime value;
  final ValueChanged<DateTime> onChoose;

  static const _labels = ['昨天', '今天', '明天'];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < _labels.length; index++)
        Expanded(child: _choice(context, index)),
    ],
  );

  Widget _choice(BuildContext context, int index) {
    final theme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final date = dayStart(day).add(Duration(days: index - 1));
    final selected = dayStart(value) == date;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        key: ValueKey('day-choice-${dateText(date)}'),
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? Colors.transparent : scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onChoose(date),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _labels[index],
                  style: theme.labelMedium?.copyWith(
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${date.month.toString().padLeft(2, '0')}-'
                  '${date.day.toString().padLeft(2, '0')}',
                  style: theme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DateTimeChoices extends StatefulWidget {
  const DateTimeChoices({
    super.key,
    required this.value,
    required this.day,
    required this.onChoose,
    required this.onCancel,
  });
  final DateTime value;

  /// The viewed day that the date choices are relative to.
  final DateTime day;
  final ValueChanged<DateTime> onChoose;
  final VoidCallback onCancel;
  @override
  State<DateTimeChoices> createState() => _DateTimeChoicesState();
}

class _DateTimeChoicesState extends State<DateTimeChoices> {
  late final _time = TextEditingController(text: clockText(widget.value));
  late DateTime _day = dayStart(widget.value);
  bool _clock = false;
  String? _error;
  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  void _confirm() {
    try {
      widget.onChoose(
        parseEditorTime('${dateText(_day)} ${_time.text}', widget.value),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  /// The chosen day can fall outside the three choices, for example when the
  /// wall clock moves an old record to today, so keep it visible.
  bool get _outsideChoices {
    final base = dayStart(widget.day);
    for (var offset = -1; offset <= 1; offset++) {
      if (base.add(Duration(days: offset)) == _day) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_outsideChoices)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '当前日期：${dateText(_day)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      DayChoices(
        day: widget.day,
        value: _day,
        onChoose: (value) => setState(() {
          _day = value;
          _error = null;
        }),
      ),
      const SizedBox(height: 12),
      PickerPopup(
        open: _clock,
        width: 260,
        onClose: () => setState(() => _clock = false),
        anchor: TextField(
          controller: _time,
          decoration: const InputDecoration(
            labelText: '时间',
            hintText: '例如 2021 或 20:21',
          ),
          onChanged: (_) => setState(() => _error = null),
          onEditingComplete: () {},
          onSubmitted: (_) => _confirm(),
          onTap: () => setState(() => _clock = true),
        ),
        builder: (context, close) => TimeChoices(
          value: pickerInitialTime(
            '${dateText(_day)} ${_time.text}',
            widget.value,
          ),
          // Show the pending hour and minute in the field at once, so Enter
          // confirms exactly the time that was just picked.
          onChanged: (value) => _time.text = clockText(value),
          // A record created while viewing an older day belongs to today once
          // its time is set to now, so the day follows the wall clock too.
          onNow: () {
            final now = DateTime.now();
            setState(() {
              _day = dayStart(now);
              _time.text = clockText(now);
              _clock = false;
              _error = null;
            });
          },
          onChoose: (value) {
            _time.text = clockText(value);
            close();
          },
        ),
      ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: widget.onCancel, child: const Text('取消')),
          FilledButton(onPressed: _confirm, child: const Text('确定')),
        ],
      ),
    ],
  );
}
