import 'dart:async';

import 'package:flutter/material.dart';

import '../application/ledger_controller.dart';
import '../domain/ledger.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'ledger_category_style.dart';
import 'workspace_style.dart';

String moneyKindText(MoneyKind kind) => switch (kind) {
  MoneyKind.expense => '支出',
  MoneyKind.income => '收入',
  MoneyKind.transfer => '转账',
  MoneyKind.adjustment => '余额校准',
};

class MoneyDateField extends StatelessWidget {
  const MoneyDateField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onChanged,
    this.showLabel = true,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback? onChanged;
  final bool showLabel;
  @override
  Widget build(BuildContext context) => Semantics(
    label: showLabel ? null : '记账日期',
    child: TextField(
      key: const ValueKey('money-date'),
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: showLabel ? '日期' : null,
        suffixIcon: IconButton(
          tooltip: '选择日期',
          onPressed: enabled
              ? () async {
                  DateTime initial;
                  try {
                    initial = parseDate(controller.text);
                  } catch (_) {
                    initial = dayStart(DateTime.now());
                  }
                  final value = await showDatePicker(
                    context: context,
                    initialDate: DateTime(
                      initial.year,
                      initial.month,
                      initial.day,
                    ),
                    firstDate: DateTime(1),
                    lastDate: DateTime(9999, 12, 31),
                  );
                  if (value != null) {
                    controller.text = dateText(value);
                    onChanged?.call();
                  }
                }
              : null,
          icon: const Icon(Icons.calendar_today, size: 18),
        ),
      ),
      onChanged: (_) => onChanged?.call(),
    ),
  );
}

Future<void> showMoneyEditor(
  BuildContext context,
  LedgerController ledger, {
  MoneyKind kind = MoneyKind.expense,
  MoneyRecord? record,
}) => showDialog<void>(
  context: context,
  builder: (_) => _MoneyEditor(ledger: ledger, kind: kind, record: record),
);

class _MoneyEditor extends StatefulWidget {
  const _MoneyEditor({required this.ledger, required this.kind, this.record});
  final LedgerController ledger;
  final MoneyKind kind;
  final MoneyRecord? record;
  @override
  State<_MoneyEditor> createState() => _MoneyEditorState();
}

class _MoneyEditorState extends State<_MoneyEditor> {
  late MoneyKind _kind = widget.record?.kind ?? widget.kind;
  late String? _category =
      widget.record?.categoryId ??
      widget.ledger.state.orderedCategories(_kind).firstOrNull?.id;
  late final _amount = TextEditingController(
    text: widget.record == null ? '' : moneyText(widget.record!.amountCents),
  );
  late final _date = TextEditingController(
    text: dateText(widget.record?.date ?? widget.ledger.clock()),
  );
  late final _notes = TextEditingController(text: widget.record?.notes ?? '');
  late String _account =
      widget.record?.accountId ?? widget.ledger.state.defaultCashId;
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.ledger.saveInputs([
        MoneyInput(
          kind: _kind,
          amountCents: parseMoney(_amount.text),
          date: parseDate(_date.text),
          categoryId: _category,
          notes: _notes.text,
          accountId: _account,
        ),
      ], editId: widget.record?.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.record == null ? '记一笔${moneyKindText(_kind)}' : '修改流水'),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSegmentedButton<MoneyKind>(
              segments: const [
                ButtonSegment(value: MoneyKind.expense, label: Text('支出')),
                ButtonSegment(value: MoneyKind.income, label: Text('收入')),
              ],
              selected: {_kind},
              onSelectionChanged: _saving
                  ? null
                  : (values) => setState(() {
                      _kind = values.single;
                      _category = widget.ledger.state
                          .orderedCategories(_kind)
                          .firstOrNull
                          ?.id;
                    }),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('record-amount'),
              controller: _amount,
              autofocus: true,
              enabled: !_saving,
              decoration: const InputDecoration(
                labelText: '金额',
                prefixText: '¥ ',
              ),
              onSubmitted: (_) => unawaited(_save()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('record-category-$_kind'),
              initialValue: _category ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: '分类'),
              items: [
                const DropdownMenuItem(value: '', child: Text('未分类')),
                for (final item in widget.ledger.state.orderedCategories(_kind))
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(widget.ledger.state.categoryPath(item.id)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) =>
                        setState(() => _category = value == '' ? null : value),
            ),
            const SizedBox(height: 16),
            MoneyDateField(controller: _date, enabled: !_saving),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const ValueKey('record-account'),
              initialValue: _account,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _kind == MoneyKind.income ? '入账账户' : '支出账户',
              ),
              items: [
                for (final account in widget.ledger.state.accounts.values)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _account = value!),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('record-notes'),
              controller: _notes,
              enabled: !_saving,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注（可选）'),
              onSubmitted: (_) => unawaited(_save()),
            ),
            if (widget.record?.affectsBalance == false)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('启用前的历史流水，修改不影响当前余额。'),
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
      FilledButton(
        onPressed: _saving ? null : () => unawaited(_save()),
        child: const Text('保存'),
      ),
    ],
  );
}

Future<void> showMoneyMovement(
  BuildContext context,
  LedgerController ledger,
  MoneyKind kind, {
  String? accountId,
  MoneyRecord? record,
}) => showDialog<void>(
  context: context,
  builder: (_) => _MovementDialog(
    ledger: ledger,
    kind: kind,
    accountId: accountId,
    record: record,
  ),
);

Future<void> showMoneyNotes(
  BuildContext context,
  LedgerController ledger,
  MoneyRecord record,
) => showDialog<void>(
  context: context,
  builder: (_) => _NotesDialog(ledger: ledger, record: record),
);

class _NotesDialog extends StatefulWidget {
  const _NotesDialog({required this.ledger, required this.record});
  final LedgerController ledger;
  final MoneyRecord record;
  @override
  State<_NotesDialog> createState() => _NotesDialogState();
}

class _NotesDialogState extends State<_NotesDialog> {
  late final _notes = TextEditingController(text: widget.record.notes);
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.ledger.updateNotes(widget.record.id, _notes.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改备注'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('bill-notes'),
            controller: _notes,
            autofocus: true,
            enabled: !_saving,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '备注（可选）'),
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
      FilledButton(
        onPressed: _saving ? null : () => unawaited(_save()),
        child: const Text('保存'),
      ),
    ],
  );
}

class _MovementDialog extends StatefulWidget {
  const _MovementDialog({
    required this.ledger,
    required this.kind,
    this.accountId,
    this.record,
  });
  final LedgerController ledger;
  final MoneyKind kind;
  final String? accountId;
  final MoneyRecord? record;
  @override
  State<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends State<_MovementDialog> {
  late String _from =
      widget.record?.accountId ??
      widget.accountId ??
      widget.ledger.state.defaultCashId;
  late String? _to =
      widget.record?.toAccountId ??
      widget.ledger.state.accounts.keys.where((id) => id != _from).firstOrNull;
  late final _amount = TextEditingController(
    text: widget.record == null ? '' : moneyText(widget.record!.amountCents),
  );
  late final _date = TextEditingController(
    text: dateText(widget.record?.date ?? widget.ledger.clock()),
  );
  late final _notes = TextEditingController(text: widget.record?.notes ?? '');
  String? _error;
  bool _saving = false;
  bool get _transfer => widget.kind == MoneyKind.transfer;
  @override
  void dispose() {
    _amount.dispose();
    _date.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cents = parseMoney(_amount.text, signed: !_transfer);
      final date = parseDate(_date.text);
      if (_transfer) {
        if (_to == null) throw const FormatException('请选择转入账户。');
        await widget.ledger.transfer(
          _from,
          _to!,
          cents,
          date,
          notes: _notes.text,
          editId: widget.record?.id,
        );
      } else if (widget.record != null) {
        await widget.ledger.updateAdjustment(
          widget.record!.id,
          _from,
          cents,
          date,
          notes: _notes.text,
        );
      } else {
        await widget.ledger.calibrate(_from, cents, date, notes: _notes.text);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorText(error);
        });
      }
    }
  }

  Widget _account(String label, String? value, ValueChanged<String?> changed) =>
      DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final account in widget.ledger.state.accounts.values)
            DropdownMenuItem(
              value: account.id,
              child: Text(
                '${account.name}  ¥ ${moneyText(account.balanceCents)}',
              ),
            ),
        ],
        onChanged: _saving ? null : changed,
      );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.record == null ? '' : '修改'}${moneyKindText(widget.kind)}',
    ),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _account(
              _transfer ? '转出账户' : '账户',
              _from,
              (value) => setState(() => _from = value!),
            ),
            if (_transfer) ...[
              const SizedBox(height: 16),
              _account('转入账户', _to, (value) => setState(() => _to = value)),
            ],
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('movement-amount'),
              controller: _amount,
              autofocus: true,
              enabled: !_saving,
              decoration: InputDecoration(
                labelText: _transfer
                    ? '转账金额'
                    : widget.record == null
                    ? '当前实际余额'
                    : '调整差额',
                prefixText: '¥ ',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => unawaited(_save()),
            ),
            if (!_transfer)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  widget.record == null
                      ? _deltaText()
                      : '正数增加余额，负数减少余额；后续流水保留。',
                ),
              ),
            const SizedBox(height: 16),
            MoneyDateField(controller: _date, enabled: !_saving),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('bill-notes'),
              controller: _notes,
              enabled: !_saving,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注（可选）'),
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
      FilledButton(
        onPressed: _saving ? null : () => unawaited(_save()),
        child: const Text('保存'),
      ),
    ],
  );
  String _deltaText() {
    try {
      final delta =
          parseMoney(_amount.text, signed: true) -
          widget.ledger.state.accounts[_from]!.balanceCents;
      return '调整差额：${delta > 0 ? '+' : ''}¥ ${moneyText(delta)}';
    } catch (_) {
      return '输入实际余额后自动计算差额';
    }
  }
}

Future<void> showLedgerCategories(
  BuildContext context,
  LedgerController ledger,
) => showDialog<void>(
  context: context,
  builder: (_) => _CategoryManager(ledger: ledger),
);

class _CategoryManager extends StatefulWidget {
  const _CategoryManager({required this.ledger});
  final LedgerController ledger;
  @override
  State<_CategoryManager> createState() => _CategoryManagerState();
}

class _CategoryManagerState extends State<_CategoryManager> {
  MoneyKind _kind = MoneyKind.expense;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    }
  }

  Future<void> _menu(Offset position, MoneyCategory category) async {
    if (widget.ledger.busy) return;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('修改标签')),
        PopupMenuItem(value: 'child', child: Text('新增子标签')),
        PopupMenuItem(value: 'delete', child: Text('删除标签')),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'delete') {
      await _run(() => widget.ledger.deleteCategory(category.id));
    } else {
      await showLedgerCategoryEditor(
        context,
        widget.ledger,
        _kind,
        category: choice == 'edit' ? category : null,
        parentId: choice == 'child' ? category.id : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.ledger,
    builder: (context, _) => AlertDialog(
      title: const Text('记账分类'),
      content: SizedBox(
        width: 620,
        height: 470,
        child: Column(
          children: [
            Row(
              children: [
                AppSegmentedButton<MoneyKind>(
                  segments: const [
                    ButtonSegment(value: MoneyKind.expense, label: Text('支出')),
                    ButtonSegment(value: MoneyKind.income, label: Text('收入')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (values) =>
                      setState(() => _kind = values.single),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.ledger.busy
                      ? null
                      : () => unawaited(
                          showLedgerCategoryEditor(
                            context,
                            widget.ledger,
                            _kind,
                          ),
                        ),
                  icon: const Icon(Icons.add),
                  label: const Text('新增分类'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                key: const ValueKey('category-manager-list'),
                children: [
                  for (final category in widget.ledger.state.orderedCategories(
                    _kind,
                  ))
                    GestureDetector(
                      onSecondaryTapUp: (details) =>
                          unawaited(_menu(details.globalPosition, category)),
                      child: ListTile(
                        key: ValueKey('category-manage-${category.id}'),
                        contentPadding: EdgeInsets.only(
                          left:
                              12 +
                              (widget.ledger.state
                                          .ancestors(category.id)
                                          .length -
                                      1) *
                                  WorkspaceStyle.tagIndent,
                        ),
                        title: Row(
                          children: [
                            LedgerCategoryBadge(
                              state: widget.ledger.state,
                              id: category.id,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(category.name)),
                          ],
                        ),
                        onTap: widget.ledger.busy
                            ? null
                            : () => unawaited(
                                showLedgerCategoryEditor(
                                  context,
                                  widget.ledger,
                                  _kind,
                                  category: category,
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    ),
  );
}

Future<void> showLedgerCategoryEditor(
  BuildContext context,
  LedgerController ledger,
  MoneyKind kind, {
  MoneyCategory? category,
  String? parentId,
}) => showDialog<void>(
  context: context,
  builder: (_) => _NameDialog(
    ledger: ledger,
    category: category,
    kind: kind,
    parentId: parentId,
  ),
);

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.ledger,
    this.category,
    this.kind,
    this.parentId,
    this.account,
  });
  final LedgerController ledger;
  final MoneyCategory? category;
  final MoneyKind? kind;
  final String? parentId;
  final MoneyAccount? account;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(
    text: widget.category?.name ?? widget.account?.name ?? '',
  );
  late String? _parent = widget.category?.parentId ?? widget.parentId;
  late CategoryColor? _color = widget.category?.color;
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
      if (widget.kind != null) {
        await widget.ledger.saveCategory(
          _name.text,
          widget.kind!,
          _parent,
          id: widget.category?.id,
          color: _color,
          inheritColor: _color == null,
        );
      } else {
        await widget.ledger.saveAccount(_name.text, id: widget.account?.id);
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = errorText(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.kind != null
          ? (widget.category == null ? '新增分类' : '修改分类')
          : (widget.account == null ? '新增账户' : '重命名账户'),
    ),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('ledger-name'),
              controller: _name,
              autofocus: true,
              enabled: !_saving,
              decoration: const InputDecoration(labelText: '名称'),
              onSubmitted: (_) => unawaited(_save()),
            ),
            if (widget.kind != null) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _parent ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: '父分类'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('一级分类')),
                  for (final item in widget.ledger.state.orderedCategories(
                    widget.kind!,
                  ))
                    if (widget.category == null ||
                        !widget.ledger.state
                            .descendants(widget.category!.id)
                            .contains(item.id))
                      DropdownMenuItem(
                        value: item.id,
                        child: Text(widget.ledger.state.categoryPath(item.id)),
                      ),
                ],
                onChanged: _saving
                    ? null
                    : (value) =>
                          setState(() => _parent = value == '' ? null : value),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '标签颜色',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('自动／继承'),
                    selected: _color == null,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _color = null),
                  ),
                  for (final color in CategoryColor.values)
                    ChoiceChip(
                      key: ValueKey('category-color-${color.name}'),
                      avatar: CircleAvatar(
                        backgroundColor: categorySwatch(color)[500],
                        radius: 8,
                      ),
                      label: Text(categoryColorText(color)),
                      selected: _color == color,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _color = color),
                    ),
                ],
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
      FilledButton(
        onPressed: _saving ? null : () => unawaited(_save()),
        child: const Text('保存'),
      ),
    ],
  );
}

Future<void> showLedgerAccounts(
  BuildContext context,
  LedgerController ledger,
) => showDialog<void>(
  context: context,
  builder: (_) => _AccountsDialog(ledger: ledger),
);

class _AccountsDialog extends StatefulWidget {
  const _AccountsDialog({required this.ledger});
  final LedgerController ledger;
  @override
  State<_AccountsDialog> createState() => _AccountsDialogState();
}

class _AccountsDialogState extends State<_AccountsDialog> {
  String? _error;
  Future<void> _delete(String id) async {
    try {
      await widget.ledger.deleteAccount(id);
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = errorText(error));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.ledger,
    builder: (context, _) => AlertDialog(
      title: const Text('资金账户'),
      content: SizedBox(
        width: 540,
        height: 340,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  for (final account in widget.ledger.state.accounts.values)
                    ListTile(
                      title: Text(
                        '${account.name}${account.id == widget.ledger.state.defaultCashId ? '（日常收支）' : ''}',
                      ),
                      subtitle: Text('¥ ${moneyText(account.balanceCents)}'),
                      trailing: PopupMenuButton<String>(
                        enabled: !widget.ledger.busy,
                        onSelected: (value) {
                          switch (value) {
                            case 'rename':
                              unawaited(
                                showDialog<void>(
                                  context: context,
                                  builder: (_) => _NameDialog(
                                    ledger: widget.ledger,
                                    account: account,
                                  ),
                                ),
                              );
                            case 'calibrate':
                              unawaited(
                                showMoneyMovement(
                                  context,
                                  widget.ledger,
                                  MoneyKind.adjustment,
                                  accountId: account.id,
                                ),
                              );
                            case 'delete':
                              unawaited(_delete(account.id));
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'calibrate',
                            child: Text('余额校准'),
                          ),
                          PopupMenuItem(value: 'rename', child: Text('重命名')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: widget.ledger.busy
              ? null
              : () => unawaited(
                  showDialog<void>(
                    context: context,
                    builder: (_) => _NameDialog(ledger: widget.ledger),
                  ),
                ),
          icon: const Icon(Icons.add),
          label: const Text('新增账户'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    ),
  );
}
