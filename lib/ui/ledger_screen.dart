import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/ledger_controller.dart';
import '../domain/ledger.dart';
import '../domain/model.dart';
import 'dialogs.dart';
import 'ledger_dialogs.dart';
import 'ledger_category_style.dart';
import 'ledger_sidebar.dart';

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key, required this.ledger, this.focusNode});
  final LedgerController ledger;
  final FocusNode? focusNode;
  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  late DateTime _month = DateTime.utc(
    widget.ledger.clock().year,
    widget.ledger.clock().month,
  );
  late final _monthText = TextEditingController(
    text: dateText(_month).substring(0, 7),
  );
  final _sidebar = GlobalKey<LedgerSidebarState>();
  final _scroll = ScrollController();
  late final _focus = widget.focusNode ?? FocusNode();
  int _limit = 40;
  bool _statistics = false;
  String? _statsParent;
  bool _saving = false;
  LedgerState get _state => widget.ledger.state;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadMore);
  }

  @override
  void dispose() {
    _monthText.dispose();
    _scroll.dispose();
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  void _loadMore() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 240 &&
        _limit < _state.recordsThrough(_month).length) {
      setState(() => _limit += 40);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_saving) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    setState(() => _saving = true);
    try {
      await action();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const ValueKey('ledger-error-toast'),
          content: Text(errorText(error)),
          behavior: SnackBarBehavior.floating,
          width: 480,
          showCloseIcon: true,
        ),
      );
  }

  void _setMonth(DateTime value) {
    if (value.year < 1 || value.year > 9999) return;
    setState(() {
      _month = DateTime.utc(value.year, value.month);
      _monthText.text = dateText(_month).substring(0, 7);
      _limit = 40;
      _statsParent = null;
    });
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _parseMonth() {
    try {
      _setMonth(parseDate('${_monthText.text.trim()}-01'));
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.ledger,
    builder: (context, _) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            unawaited(
              _action(() async {
                await widget.ledger.undo();
              }),
            ),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
            unawaited(
              _action(() async {
                await widget.ledger.redo();
              }),
            ),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () => unawaited(
          _action(() async {
            await widget.ledger.redo();
          }),
        ),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            unawaited(_sidebar.currentState?.saveAll() ?? Future.value()),
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 320,
              child: LedgerSidebar(
                key: _sidebar,
                ledger: widget.ledger,
                onError: _showError,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _balances(context),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          key: const ValueKey('add-income'),
                          onPressed: _saving || widget.ledger.busy
                              ? null
                              : () => unawaited(
                                  showMoneyEditor(
                                    context,
                                    widget.ledger,
                                    kind: MoneyKind.income,
                                  ),
                                ),
                          icon: const Icon(Icons.add),
                          label: const Text('记收入'),
                        ),
                        TextButton.icon(
                          onPressed: _saving || widget.ledger.busy
                              ? null
                              : () => unawaited(
                                  showMoneyMovement(
                                    context,
                                    widget.ledger,
                                    MoneyKind.transfer,
                                  ),
                                ),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('转账'),
                        ),
                        TextButton.icon(
                          onPressed: _saving || widget.ledger.busy
                              ? null
                              : () => unawaited(
                                  showMoneyMovement(
                                    context,
                                    widget.ledger,
                                    MoneyKind.adjustment,
                                  ),
                                ),
                          icon: const Icon(Icons.balance),
                          label: const Text('余额校准'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(child: _browse(context)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _balances(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget balance(String title, int amount, {String? id}) => Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '¥ ${moneyText(amount)}',
              key: id == null
                  ? const ValueKey('balance-total')
                  : ValueKey('balance-$id'),
              maxLines: 1,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
    final cash = _state.accounts[_state.defaultCashId]!;
    return SizedBox(
      height: 76,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  balance('资金总额', _state.totalCents),
                  const SizedBox(width: 10),
                  balance('${cash.name} · 可支配', cash.balanceCents, id: cash.id),
                  for (final account in _state.accounts.values.where(
                    (item) => item.id != cash.id,
                  )) ...[
                    const SizedBox(width: 10),
                    balance(account.name, account.balanceCents, id: account.id),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '管理账户',
            onPressed: _saving
                ? null
                : () => unawaited(showLedgerAccounts(context, widget.ledger)),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ],
      ),
    );
  }

  Widget _browse(BuildContext context) => Card.outlined(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('money-previous-month'),
                tooltip: '上个月',
                onPressed: () =>
                    _setMonth(DateTime.utc(_month.year, _month.month - 1)),
                icon: const Icon(Icons.chevron_left),
              ),
              SizedBox(
                width: 108,
                child: TextField(
                  key: const ValueKey('money-month'),
                  controller: _monthText,
                  decoration: const InputDecoration(hintText: 'YYYY-MM'),
                  onSubmitted: (_) => _parseMonth(),
                ),
              ),
              IconButton(
                key: const ValueKey('money-next-month'),
                tooltip: '下个月',
                onPressed: () =>
                    _setMonth(DateTime.utc(_month.year, _month.month + 1)),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () => _setMonth(widget.ledger.clock()),
                child: const Text('本月'),
              ),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('流水')),
                  ButtonSegment(value: true, label: Text('分类统计')),
                ],
                selected: {_statistics},
                onSelectionChanged: (values) =>
                    setState(() => _statistics = values.single),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                '支出  ¥ ${moneyText(_state.monthlyTotal(_month, MoneyKind.expense))}',
                key: const ValueKey('month-expense'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 28),
              Text(
                '收入  ¥ ${moneyText(_state.monthlyTotal(_month, MoneyKind.income))}',
                key: const ValueKey('month-income'),
              ),
            ],
          ),
          const Divider(height: 28),
          Expanded(child: _statistics ? _stats(context) : _records(context)),
        ],
      ),
    ),
  );

  Widget _records(BuildContext context) {
    final records = _state.recordsThrough(_month);
    if (records.isEmpty) return const Center(child: Text('暂无流水'));
    final count = math.min(_limit, records.length);
    return Scrollbar(
      controller: _scroll,
      child: ListView.builder(
        key: const ValueKey('money-records'),
        controller: _scroll,
        itemCount: count,
        itemBuilder: (context, index) {
          final record = records[index];
          final newDay = index == 0 || records[index - 1].date != record.date;
          final title = switch (record.kind) {
            MoneyKind.expense ||
            MoneyKind.income => _state.categoryPath(record.categoryId),
            MoneyKind.transfer =>
              '${_state.accounts[record.accountId]!.name} → ${_state.accounts[record.toAccountId]!.name}',
            MoneyKind.adjustment =>
              '${_state.accounts[record.accountId]!.name} · 余额校准',
          };
          final sign = switch (record.kind) {
            MoneyKind.expense => '−',
            MoneyKind.income => '+',
            MoneyKind.transfer => '',
            MoneyKind.adjustment => record.amountCents > 0 ? '+' : '−',
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (newDay)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6, left: 12),
                  child: Text(
                    dateText(record.date),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ListTile(
                key: ValueKey('money-record-${record.id}'),
                title: Text(title),
                subtitle: record.notes.isEmpty ? null : Text(record.notes),
                leading: record.categoryId != null
                    ? LedgerCategoryBadge(state: _state, id: record.categoryId)
                    : Icon(
                        switch (record.kind) {
                          MoneyKind.expense => Icons.remove_circle_outline,
                          MoneyKind.income => Icons.add_circle_outline,
                          MoneyKind.transfer => Icons.swap_horiz,
                          MoneyKind.adjustment => Icons.balance,
                        },
                        color: record.kind == MoneyKind.income
                            ? Colors.green[700]
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$sign¥ ${moneyText(record.amountCents.abs())}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    PopupMenuButton<String>(
                      enabled: !_saving,
                      tooltip: '流水操作',
                      onSelected: (value) {
                        if (value == 'delete') {
                          unawaited(
                            _action(
                              () => widget.ledger.deleteRecord(record.id),
                            ),
                          );
                        } else {
                          unawaited(
                            showMoneyEditor(
                              context,
                              widget.ledger,
                              record: record,
                            ),
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        if ([
                          MoneyKind.expense,
                          MoneyKind.income,
                        ].contains(record.kind))
                          const PopupMenuItem(value: 'edit', child: Text('修改')),
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ],
                ),
                onTap:
                    _saving ||
                        ![
                          MoneyKind.expense,
                          MoneyKind.income,
                        ].contains(record.kind)
                    ? null
                    : () => unawaited(
                        showMoneyEditor(context, widget.ledger, record: record),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stats(BuildContext context) {
    final parent = _state.categories[_statsParent];
    final rows = _state.expenseBreakdown(_month, parentId: parent?.id);
    final total = rows.fold<int>(0, (sum, row) => sum + row.amountCents);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (parent != null)
              IconButton(
                key: const ValueKey('stats-back'),
                tooltip: '返回上一级',
                onPressed: () => setState(() => _statsParent = parent.parentId),
                icon: const Icon(Icons.arrow_back),
              ),
            Expanded(
              child: Text(
                parent == null ? '全部支出' : _state.categoryPath(parent.id),
                key: const ValueKey('stats-path'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text('¥ ${moneyText(total)}'),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('本月暂无支出'))
              : ListView(
                  children: [
                    for (final row in rows)
                      ListTile(
                        key: ValueKey(
                          'stats-${row.categoryId ?? 'unclassified'}-${row.direct}',
                        ),
                        title: Text(
                          row.direct
                              ? (parent == null
                                    ? '未分类'
                                    : '${parent.name}（直接记录）')
                              : _state.categories[row.categoryId]!.name,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: LinearProgressIndicator(
                            value: row.amountCents / total,
                            minHeight: 4,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '¥ ${moneyText(row.amountCents)}  ${(row.amountCents * 100 / total).toStringAsFixed(1)}%',
                            ),
                            if (!row.direct) const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: row.direct
                            ? null
                            : () =>
                                  setState(() => _statsParent = row.categoryId),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
