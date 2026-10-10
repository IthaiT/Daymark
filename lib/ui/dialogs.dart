import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../domain/model.dart';
import 'pickers.dart';

String errorText(Object error) =>
    error is FormatException ? error.message : error.toString();

Future<void> showTagEditor(
  BuildContext context,
  JournalController journal, {
  String? id,
  String? parentId,
}) => showDialog<void>(
  context: context,
  builder: (_) => _TagEditor(journal: journal, id: id, parentId: parentId),
);

class _TagEditor extends StatefulWidget {
  const _TagEditor({required this.journal, this.id, this.parentId});
  final JournalController journal;
  final String? id;
  final String? parentId;
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
      await widget.journal.saveTag(_name.text, _parent, id: widget.id);
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
              onChanged: (value) => setState(() => _tag = value),
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
