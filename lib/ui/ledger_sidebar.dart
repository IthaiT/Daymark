import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/ledger_controller.dart';
import '../domain/ledger.dart';
import '../domain/model.dart';
import 'ledger_category_style.dart';
import 'ledger_dialogs.dart';

class _Entry {
  final amount = TextEditingController();
  final notes = TextEditingController();
  final focus = FocusNode();
  bool notesOpen = false;
  void dispose() {
    amount.dispose();
    notes.dispose();
    focus.dispose();
  }
}

class LedgerSidebar extends StatefulWidget {
  const LedgerSidebar({super.key, required this.ledger, required this.onError});
  final LedgerController ledger;
  final ValueChanged<Object> onError;
  @override
  State<LedgerSidebar> createState() => LedgerSidebarState();
}

class LedgerSidebarState extends State<LedgerSidebar> {
  final _entries = <String, _Entry>{};
  final _collapsed = <String>{};
  final _scroll = ScrollController();
  late DateTime _day = dayStart(widget.ledger.clock());
  late final _date = TextEditingController(text: dateText(_day));
  MoneyKind _kind = MoneyKind.expense;
  bool _saving = false;
  bool _movingFocus = false;
  LedgerState get _state => widget.ledger.state;
  bool get _busy => _saving || widget.ledger.busy;
  @override
  void dispose() {
    _date.dispose();
    _scroll.dispose();
    for (final entry in _entries.values) {
      entry.dispose();
    }
    super.dispose();
  }

  void _dateChanged() {
    DateTime day;
    try {
      day = parseDate(_date.text);
    } on FormatException {
      return;
    }
    if (day == _day) return;
    setState(() {
      _day = day;
      for (final entry in _entries.values) {
        entry.amount.clear();
        entry.notes.clear();
        entry.notesOpen = false;
      }
    });
  }

  void _stepDay(int delta) {
    try {
      final day = parseDate(_date.text).add(Duration(days: delta));
      if (day.year < 1 || day.year > 9999) return;
      _date.text = dateText(day);
      _dateChanged();
    } catch (error) {
      widget.onError(error);
    }
  }

  Future<void> saveAll({String? focusId}) =>
      _save(_entries.keys.toList(), focusId: focusId);

  Future<void> _focusAmount(String id, {int direction = 1, int? caret}) async {
    final entry = _entries[id];
    if (entry == null) return;
    var fieldContext = entry.focus.context;
    while (mounted && fieldContext == null && _scroll.hasClients) {
      final position = _scroll.position;
      final next =
          (position.pixels + direction * position.viewportDimension * .7).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          );
      if (next == position.pixels) break;
      await _scroll.animateTo(
        next,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
      if (!mounted) return;
      fieldContext = entry.focus.context;
    }
    if (!mounted || fieldContext == null || !fieldContext.mounted) return;
    entry.focus.requestFocus();
    if (caret != null) {
      entry.amount.selection = TextSelection.collapsed(
        offset: caret.clamp(0, entry.amount.text.length),
      );
    }
    await Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 100),
      alignmentPolicy: direction > 0
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  Future<void> _moveAmount(String id, int direction) async {
    if (_busy || _movingFocus) return;
    final categories = _categories();
    final index = categories.indexWhere((item) => item.id == id);
    final next = index + direction;
    if (index < 0 || next < 0 || next >= categories.length) return;
    _movingFocus = true;
    try {
      await _focusAmount(
        categories[next].id,
        direction: direction,
        caret: _entries[id]!.amount.selection.extentOffset,
      );
    } finally {
      _movingFocus = false;
    }
  }

  Future<void> _revealInvalid(String id) async {
    setState(() {
      _kind = _state.categories[id]!.kind;
      for (final parent in _state.ancestors(id)) {
        _collapsed.remove(parent.id);
      }
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) await _focusAmount(id);
  }

  Widget _entryShortcuts(
    String id,
    TextEditingController controller,
    Widget child, {
    bool arrows = false,
  }) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    child: child,
    builder: (context, value, child) => CallbackShortcuts(
      bindings: {
        if (!value.composing.isValid || value.composing.isCollapsed) ...{
          const SingleActivator(LogicalKeyboardKey.enter): () =>
              unawaited(saveAll(focusId: id)),
          const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
              unawaited(saveAll(focusId: id)),
          if (arrows) ...{
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                unawaited(_moveAmount(id, -1)),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                unawaited(_moveAmount(id, 1)),
          },
        },
      },
      child: child!,
    ),
  );

  Future<void> _save(List<String> ids, {String? focusId}) async {
    if (_busy) return;
    setState(() => _saving = true);
    try {
      final date = parseDate(_date.text);
      final selected = ids
          .where(
            (id) =>
                _state.categories.containsKey(id) &&
                (_entries[id]!.amount.text.trim().isNotEmpty ||
                    _entries[id]!.notes.text.trim().isNotEmpty),
          )
          .toList();
      if (selected.isEmpty) throw const FormatException('请填写金额。');
      final inputs = <MoneyInput>[];
      for (final id in selected) {
        final entry = _entries[id]!;
        int cents;
        try {
          cents = parseMoney(entry.amount.text);
          if (cents <= 0) throw const FormatException('金额必须大于零。');
        } on FormatException catch (error) {
          await _revealInvalid(id);
          throw FormatException(
            '${_state.categories[id]!.name}：${error.message}',
          );
        }
        inputs.add(
          MoneyInput(
            kind: _state.categories[id]!.kind,
            amountCents: cents,
            date: date,
            categoryId: id,
            notes: entry.notes.text,
          ),
        );
      }
      await widget.ledger.saveInputs(inputs);
      if (!mounted) return;
      for (final id in selected) {
        _entries[id]!.amount.clear();
        _entries[id]!.notes.clear();
      }
      if (focusId != null) _entries[focusId]?.focus.requestFocus();
    } catch (error) {
      widget.onError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    try {
      await action();
    } catch (error) {
      widget.onError(error);
    }
  }

  List<MoneyCategory> _categories() {
    final ordered = _state.orderedCategories(_kind);
    final presetOrder = {
      for (final (index, item) in defaultMoneyCategories.indexed)
        item.id: index,
    };
    final result = <MoneyCategory>[];
    void visit(String? parent) {
      final children = ordered
          .where((item) => item.parentId == parent)
          .toList();
      children.sort((a, b) {
        int rank(MoneyCategory item) {
          final pin = _state.pinned.indexOf(item.id);
          if (parent != null && pin >= 0) return pin;
          return 100 + (presetOrder[item.id] ?? 1000 + ordered.indexOf(item));
        }

        return rank(a).compareTo(rank(b));
      });
      for (final child in children) {
        result.add(child);
        if (!_collapsed.contains(child.id)) visit(child.id);
      }
    }

    visit(null);
    return result;
  }

  bool _validDrop(String source, String? target) =>
      !_busy &&
      _state.categories[source]?.kind == _kind &&
      source != target &&
      (target == null || !_state.descendants(source).contains(target));

  Widget _target(MoneyCategory? category, Widget child) => DragTarget<String>(
    onWillAcceptWithDetails: (details) =>
        _validDrop(details.data, category?.id),
    onAcceptWithDetails: (details) {
      final source = _state.categories[details.data]!;
      unawaited(
        _run(
          () => widget.ledger.saveCategory(
            source.name,
            source.kind,
            category?.id,
            id: source.id,
          ),
        ),
      );
    },
    builder: (context, candidates, _) => ColoredBox(
      color: candidates.isEmpty
          ? Colors.transparent
          : Theme.of(context).colorScheme.secondaryContainer,
      child: child,
    ),
  );

  Future<void> _menu(Offset position, MoneyCategory? category) async {
    if (_busy) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'add',
          child: Text(category == null ? '新增一级标签' : '新增子标签'),
        ),
        if (category != null) ...[
          const PopupMenuItem(value: 'edit', child: Text('修改标签')),
          if (category.parentId != null)
            const PopupMenuItem(value: 'root', child: Text('移至一级标签')),
          const PopupMenuItem(value: 'delete', child: Text('删除标签')),
        ],
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'add':
        await showLedgerCategoryEditor(
          context,
          widget.ledger,
          _kind,
          parentId: category?.id,
        );
      case 'edit':
        await showLedgerCategoryEditor(
          context,
          widget.ledger,
          _kind,
          category: category,
        );
      case 'root':
        await _run(
          () => widget.ledger.saveCategory(
            category!.name,
            category.kind,
            null,
            id: category.id,
          ),
        );
      case 'delete':
        await _run(() => widget.ledger.deleteCategory(category!.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories();
    final totals =
        _state.dailyTotals[_day] ?? (expenseCents: 0, incomeCents: 0);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _target(
              null,
              GestureDetector(
                onSecondaryTapDown: (details) =>
                    unawaited(_menu(details.globalPosition, null)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '记${moneyKindText(_kind)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: '新增标签',
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                              showLedgerCategoryEditor(
                                context,
                                widget.ledger,
                                _kind,
                              ),
                            ),
                      icon: const Icon(Icons.add),
                    ),
                    IconButton(
                      tooltip: '管理分类',
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                              showLedgerCategories(context, widget.ledger),
                            ),
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<MoneyKind>(
              segments: const [
                ButtonSegment(value: MoneyKind.expense, label: Text('支出标签')),
                ButtonSegment(value: MoneyKind.income, label: Text('收入标签')),
              ],
              selected: {_kind},
              onSelectionChanged: _busy
                  ? null
                  : (values) => setState(() => _kind = values.single),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('money-previous-day'),
                  tooltip: '上一天',
                  onPressed: _busy ? null : () => _stepDay(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: MoneyDateField(
                    controller: _date,
                    showLabel: false,
                    enabled: !_busy,
                    onChanged: _dateChanged,
                  ),
                ),
                IconButton(
                  key: const ValueKey('money-next-day'),
                  tooltip: '下一天',
                  onPressed: _busy ? null : () => _stepDay(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(
                  '当日支出  ¥ ${moneyText(totals.expenseCents)}',
                  key: const ValueKey('entry-day-expense'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  '当日收入  ¥ ${moneyText(totals.incomeCents)}',
                  key: const ValueKey('entry-day-income'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: Scrollbar(
                  controller: _scroll,
                  child: ListView(
                    controller: _scroll,
                    key: const ValueKey('ledger-tags'),
                    children: [
                      for (final (index, category) in categories.indexed)
                        _row(category, index),
                      _target(null, const SizedBox(height: 64)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('save-all-money'),
              onPressed: _busy ? null : () => unawaited(saveAll()),
              child: const Text('保存已填项目'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(MoneyCategory category, int index) {
    final entry = _entries.putIfAbsent(category.id, _Entry.new);
    final hasChildren = _state.categories.values.any(
      (item) => item.parentId == category.id,
    );
    final depth = _state.ancestors(category.id).length - 1;
    final pinned = _state.pinned.contains(category.id);
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LedgerCategoryBadge(state: _state, id: category.id, size: 24),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            category.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    return _target(
      category,
      GestureDetector(
        key: ValueKey('ledger-tag-${category.id}'),
        onSecondaryTapDown: (details) =>
            unawaited(_menu(details.globalPosition, category)),
        child: Padding(
          padding: EdgeInsets.only(
            left: (depth * 12.0).clamp(0, 36),
            bottom: 8,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: hasChildren
                        ? IconButton(
                            key: ValueKey('ledger-fold-${category.id}'),
                            tooltip: _collapsed.contains(category.id)
                                ? '展开标签'
                                : '收起标签',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => setState(() {
                              if (!_collapsed.add(category.id)) {
                                _collapsed.remove(category.id);
                              }
                            }),
                            icon: Icon(
                              _collapsed.contains(category.id)
                                  ? Icons.chevron_right
                                  : Icons.expand_more,
                              size: 20,
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Draggable<String>(
                      data: category.id,
                      maxSimultaneousDrags: _busy ? 0 : 1,
                      feedback: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(category.name),
                        ),
                      ),
                      child: Tooltip(
                        message: _state.categoryPath(category.id),
                        child: label,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 82,
                    child: FocusTraversalOrder(
                      order: NumericFocusOrder(index * 2.0),
                      child: _entryShortcuts(
                        category.id,
                        entry.amount,
                        TextField(
                          key: ValueKey('quick-${category.id}'),
                          controller: entry.amount,
                          focusNode: entry.focus,
                          readOnly: _busy,
                          decoration: const InputDecoration(
                            prefixText: '¥ ',
                            hintText: '金额',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) =>
                              unawaited(saveAll(focusId: category.id)),
                        ),
                        arrows: true,
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('notes-toggle-${category.id}'),
                    tooltip: '填写备注',
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 36,
                    ),
                    padding: const EdgeInsets.all(4),
                    onPressed: _busy
                        ? null
                        : () => setState(
                            () => entry.notesOpen = !entry.notesOpen,
                          ),
                    icon: Icon(
                      entry.notesOpen ? Icons.notes : Icons.notes_outlined,
                      size: 18,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '标签操作',
                    enabled: !_busy,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    iconSize: 18,
                    onSelected: (value) {
                      if (value == 'edit') {
                        unawaited(
                          showLedgerCategoryEditor(
                            context,
                            widget.ledger,
                            _kind,
                            category: category,
                          ),
                        );
                        return;
                      }
                      final ids = [..._state.pinned];
                      final position = ids.indexOf(category.id);
                      if (value == 'unpin') ids.remove(category.id);
                      if (value == 'pin') ids.add(category.id);
                      if (value == 'up') {
                        ids.removeAt(position);
                        ids.insert(position - 1, category.id);
                      }
                      if (value == 'down') {
                        ids.removeAt(position);
                        ids.insert(position + 1, category.id);
                      }
                      unawaited(_run(() => widget.ledger.setPinned(ids)));
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('修改标签')),
                      if (_kind == MoneyKind.expense) ...[
                        PopupMenuItem(
                          value: pinned ? 'unpin' : 'pin',
                          child: Text(pinned ? '取消固定' : '固定为常用'),
                        ),
                        if (pinned) ...[
                          PopupMenuItem(
                            value: 'up',
                            enabled: _state.pinned.first != category.id,
                            child: const Text('向上移'),
                          ),
                          PopupMenuItem(
                            value: 'down',
                            enabled: _state.pinned.last != category.id,
                            child: const Text('向下移'),
                          ),
                        ],
                      ],
                    ],
                  ),
                ],
              ),
              if (entry.notesOpen)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 24),
                  child: FocusTraversalOrder(
                    order: NumericFocusOrder(index * 2.0 + 1),
                    child: _entryShortcuts(
                      category.id,
                      entry.notes,
                      TextField(
                        key: ValueKey('quick-notes-${category.id}'),
                        controller: entry.notes,
                        readOnly: _busy,
                        decoration: const InputDecoration(hintText: '备注（可选）'),
                        maxLines: 2,
                        onSubmitted: (_) =>
                            unawaited(saveAll(focusId: category.id)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
