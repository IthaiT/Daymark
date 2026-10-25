import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../domain/appearance.dart';
import '../domain/model.dart';
import '../domain/tag_colors.dart';
import 'pickers.dart';
import 'theme.dart';

String errorText(Object error) =>
    error is FormatException ? error.message : error.toString();

Future<void> showTagEditor(
  BuildContext context,
  JournalController journal, {
  String? id,
  String? parentId,
  TagColor? color,
  TagDisplay? display,
  TagStyleChanged? onStyleChanged,
  Future<void> Function(String id, TagColor? color)? onColorChanged,
}) => showDialog<void>(
  context: context,
  builder: (_) => _TagEditor(
    journal: journal,
    id: id,
    parentId: parentId,
    color: color,
    display: display,
    onStyleChanged: onStyleChanged,
    onColorChanged: onColorChanged,
  ),
);

class _TagEditor extends StatefulWidget {
  const _TagEditor({
    required this.journal,
    this.id,
    this.parentId,
    this.color,
    this.display,
    this.onStyleChanged,
    this.onColorChanged,
  });
  final JournalController journal;
  final String? id;
  final String? parentId;
  final TagColor? color;
  final TagDisplay? display;
  final TagStyleChanged? onStyleChanged;
  final Future<void> Function(String id, TagColor? color)? onColorChanged;
  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  late final _name = TextEditingController(
    text: widget.journal.store.tags[widget.id]?.name ?? '',
  );
  late String? _parent = widget.id == null
      ? widget.parentId
      : widget.journal.store.tags[widget.id]!.parentId;
  late TagColor? _color = widget.color;
  late TagColor? _lastIndependentColor = widget.color;
  late TagDisplay? _display = widget.display;
  String? _savedId;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // A failed colour write keeps the dialog open; reuse the created tag
      // instead of adding a duplicate on retry.
      final tag = await widget.journal.saveTag(
        _name.text,
        _parent,
        id: widget.id ?? _savedId,
      );
      _savedId = tag.id;
      if (widget.onStyleChanged != null &&
          (_color != widget.color || _display != widget.display)) {
        await widget.onStyleChanged!(tag.id, _color, _display);
      } else if (widget.onStyleChanged == null && _color != widget.color) {
        await widget.onColorChanged?.call(tag.id, _color);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.id == null ? '新增标签' : '修改 / 移动标签'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '标签名称'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            TagField(
              store: widget.journal.store,
              value: _parent,
              emptyLabel: '（一级标签）',
              excluded: widget.id == null
                  ? {}
                  : widget.journal.store.descendants(widget.id!),
              onChanged: (value) => setState(() => _parent = value),
            ),
            if (widget.onStyleChanged != null) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const ValueKey('tag-display'),
                initialValue: _display?.name ?? 'inherit',
                decoration: const InputDecoration(labelText: '显示方式'),
                items: const [
                  DropdownMenuItem(value: 'inherit', child: Text('跟随父标签')),
                  DropdownMenuItem(value: 'normal', child: Text('普通事项')),
                  DropdownMenuItem(value: 'routine', child: Text('日常背景')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _display = value == 'inherit'
                            ? null
                            : TagDisplay.values.firstWhere(
                                (item) => item.name == value,
                              );
                      }),
              ),
              const SizedBox(height: 6),
              const Text('日常背景在关注视图中折叠，完整一天中以灰色显示。'),
            ],
            if (widget.onColorChanged != null ||
                widget.onStyleChanged != null) ...[
              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '标签颜色',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('tag-color-source'),
                initialValue: _color == null ? 'inherit' : 'own',
                decoration: const InputDecoration(labelText: '颜色来源'),
                items: const [
                  DropdownMenuItem(value: 'inherit', child: Text('自动／继承')),
                  DropdownMenuItem(value: 'own', child: Text('独立颜色')),
                ],
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        if (value == 'inherit') {
                          _lastIndependentColor = _color;
                          _color = null;
                        } else {
                          _color =
                              _lastIndependentColor ??
                              suggestTagColor(
                                widget.journal.store.tags.values,
                                tagColorOverrides(context),
                                exceptId: widget.id,
                              );
                        }
                      }),
              ),
              if (_color != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final color in TagColor.values)
                        ChoiceChip(
                          key: ValueKey('tag-color-${color.name}'),
                          avatar: CircleAvatar(
                            backgroundColor: tagColorSwatch(color)[500],
                            radius: 8,
                          ),
                          label: Text(tagColorText(color)),
                          selected: _color == color,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() {
                                  _color = color;
                                  _lastIndependentColor = color;
                                }),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '子标签继承最近的独立颜色；独立颜色固定，不随日期或排序变化。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _saving ? null : _save, child: const Text('保存')),
    ],
  );
}

Future<void> showEventEditor(
  BuildContext context,
  JournalController journal,
  Event event,
) => showDialog<void>(
  context: context,
  builder: (_) => _EventEditor(journal: journal, event: event),
);

class _EventEditor extends StatefulWidget {
  const _EventEditor({required this.journal, required this.event});
  final JournalController journal;
  final Event event;
  @override
  State<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends State<_EventEditor> {
  late final _title = TextEditingController(text: widget.event.title);
  late final _notes = TextEditingController(text: widget.event.notes);
  late final _start = TextEditingController(
    text: '${dateText(widget.event.start)} ${clockText(widget.event.start)}',
  );
  late final _end = TextEditingController(
    text:
        '${dateText(widget.event.end ?? widget.event.start.add(const Duration(hours: 1)))} ${clockText(widget.event.end ?? widget.event.start.add(const Duration(hours: 1)))}',
  );
  late String? _tag = widget.event.tagId;
  bool _startOpen = false;
  bool _endOpen = false;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    for (final controller in [_title, _notes, _start, _end]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final start = parseEditorTime(_start.text, widget.event.start);
      final end = parseEditorTime(
        _end.text,
        widget.event.end ?? widget.event.start.add(const Duration(hours: 1)),
      );
      await widget.journal.updateEvent(
        widget.event.copyWith(
          title: _title.text.trim(),
          tagId: _tag,
          clearTag: _tag == null,
          start: start,
          end: end,
          notes: _notes.text,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('编辑事件'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: '事件名称'),
            ),
            const SizedBox(height: 16),
            TagField(
              store: widget.journal.store,
              value: _tag,
              onChanged: (value) => setState(() {
                _tag = value;
                if (value != null && _title.text.trim().isEmpty) {
                  _title.text = widget.journal.store.tagName(value);
                }
              }),
            ),
            const SizedBox(height: 16),
            for (final start in [true, false])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PickerPopup(
                  open: start ? _startOpen : _endOpen,
                  onClose: () => setState(() {
                    if (start) {
                      _startOpen = false;
                    } else {
                      _endOpen = false;
                    }
                  }),
                  anchor: TextField(
                    controller: start ? _start : _end,
                    decoration: InputDecoration(labelText: start ? '开始' : '结束'),
                    onSubmitted: (_) => setState(() {
                      if (start) {
                        _startOpen = false;
                      } else {
                        _endOpen = false;
                      }
                    }),
                    onTap: () => setState(() {
                      if (start) {
                        _startOpen = true;
                      } else {
                        _endOpen = true;
                      }
                    }),
                  ),
                  builder: (context, close) => DateTimeChoices(
                    value: pickerInitialTime(
                      (start ? _start : _end).text,
                      (start ? widget.event.start : widget.event.end) ??
                          widget.event.start.add(const Duration(hours: 1)),
                    ),
                    day: widget.journal.day,
                    onCancel: close,
                    onChoose: (value) {
                      (start ? _start : _end).text =
                          '${dateText(value)} ${clockText(value)}';
                      close();
                    },
                  ),
                ),
              ),
            TextField(
              controller: _notes,
              minLines: 4,
              maxLines: 6,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _saving ? null : _save, child: const Text('保存')),
    ],
  );
}
