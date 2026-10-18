import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/store.dart';
import '../domain/model.dart';
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

class TagChoices extends StatefulWidget {
  const TagChoices({
    super.key,
    required this.store,
    required this.onChoose,
    this.selected,
    this.excluded = const {},
    this.emptyLabel = '未分类',
  });
  final Store store;
  final ValueChanged<String?> onChoose;
  final String? selected;
  final Set<String> excluded;
  final String emptyLabel;
  @override
  State<TagChoices> createState() => _TagChoicesState();
}

class _TagChoicesState extends State<TagChoices> {
  final _collapsed = <String>{};
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TagTreeTile(
        key: const ValueKey('tag-choice-unclassified'),
        store: widget.store,
        selected: widget.selected == null,
        label: widget.emptyLabel,
        onTap: () => widget.onChoose(null),
      ),
      for (final tag in widget.store.orderedTags())
        if (!widget.excluded.contains(tag.id) &&
            !widget.store
                .ancestors(tag.id)
                .take(widget.store.ancestors(tag.id).length - 1)
                .any((parent) => _collapsed.contains(parent.id)))
          TagTreeTile(
            key: ValueKey('tag-choice-${tag.id}'),
            store: widget.store,
            tagId: tag.id,
            label: tag.name,
            depth: widget.store.ancestors(tag.id).length - 1,
            selected: widget.selected == tag.id,
            collapsed: _collapsed.contains(tag.id),
            onToggle:
                widget.store.tags.values.any(
                  (child) => child.parentId == tag.id,
                )
                ? () => setState(() {
                    if (!_collapsed.add(tag.id)) _collapsed.remove(tag.id);
                  })
                : null,
            onTap: () => widget.onChoose(tag.id),
          ),
    ],
  );
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

/// Hour and minute columns with a readout of the current selection. The picked
/// tile keeps a filled background, so a manual choice is always identifiable.
class TimeChoices extends StatefulWidget {
  const TimeChoices({
    super.key,
    required this.value,
    required this.onChoose,
    this.onChanged,
  });
  final DateTime value;
  final ValueChanged<DateTime> onChoose;

  /// Reports every manual hour or minute pick, so the caller can preview the
  /// pending time while this picker stays open.
  final ValueChanged<DateTime>? onChanged;
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

class DateTimeChoices extends StatefulWidget {
  const DateTimeChoices({
    super.key,
    required this.value,
    required this.onChoose,
    required this.onCancel,
  });
  final DateTime value;
  final ValueChanged<DateTime> onChoose;
  final VoidCallback onCancel;
  @override
  State<DateTimeChoices> createState() => _DateTimeChoicesState();
}

class _DateTimeChoicesState extends State<DateTimeChoices> {
  late final _date = TextEditingController(text: dateText(widget.value));
  late final _time = TextEditingController(text: clockText(widget.value));
  bool _calendar = false;
  bool _clock = false;
  String? _error;
  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    super.dispose();
  }

  void _confirm() {
    try {
      widget.onChoose(
        parseTimestamp('${_date.text.trim()}T${_time.text.trim()}:00'),
      );
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      PickerPopup(
        open: _calendar,
        width: 320,
        onClose: () => setState(() => _calendar = false),
        anchor: TextField(
          controller: _date,
          decoration: const InputDecoration(labelText: '日期'),
          onSubmitted: (_) => _confirm(),
          onTap: () => setState(() {
            _calendar = true;
            _clock = false;
          }),
        ),
        builder: (context, close) => CalendarChoices(
          value: pickerInitialTime('${_date.text} ${_time.text}', widget.value),
          onChoose: (value) {
            _date.text = dateText(value);
            close();
          },
        ),
      ),
      const SizedBox(height: 12),
      PickerPopup(
        open: _clock,
        width: 260,
        onClose: () => setState(() => _clock = false),
        anchor: TextField(
          controller: _time,
          decoration: const InputDecoration(labelText: '时间'),
          onSubmitted: (_) => _confirm(),
          onTap: () => setState(() {
            _clock = true;
            _calendar = false;
          }),
        ),
        builder: (context, close) => TimeChoices(
          value: pickerInitialTime('${_date.text} ${_time.text}', widget.value),
          // Show the pending hour and minute in the field at once, so Enter
          // confirms exactly the time that was just picked.
          onChanged: (value) => _time.text = clockText(value),
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
