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
import 'ledger_statistics.dart';
import 'workspace_style.dart';

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
  LedgerPeriod _period = LedgerPeriod.month;
  MoneyKind _statsKind = MoneyKind.expense;
  LedgerPeriod get _displayPeriod => _statistics ? _period : LedgerPeriod.month;
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
    if (_saving || widget.ledger.busy) return;
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
      _updatePeriodText();
      _limit = 40;
      _statsParent = null;
    });
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _parseMonth() {
    try {
      final text = _monthText.text.trim();
      if (_displayPeriod == LedgerPeriod.year &&
          !RegExp(r'^\d{4}$').hasMatch(text)) {
        throw const FormatException('请输入四位年份。');
      }
      _setMonth(
        parseDate(
          _displayPeriod == LedgerPeriod.year ? '$text-01-01' : '$text-01',
        ),
      );
    } catch (error) {
      _showError(error);
    }
  }

  void _updatePeriodText() => _monthText.text = dateText(
    _month,
  ).substring(0, _displayPeriod == LedgerPeriod.year ? 4 : 7);

  void _stepPeriod(int delta) => _setMonth(
    _displayPeriod == LedgerPeriod.year
        ? DateTime.utc(_month.year + delta, _month.month)
        : DateTime.utc(_month.year, _month.month + delta),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.ledger,
    builder: (context, _) => Actions(
      actions: {
        // Text fields expose overridable undo actions; these must use ledger history.
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (_) {
            unawaited(
              _action(() async {
                await widget.ledger.undo();
              }),
            );
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (_) {
            unawaited(
              _action(() async {
                await widget.ledger.redo();
              }),
            );
            return null;
          },
        ),
      },
      child: CallbackShortcuts(
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
          const SingleActivator(
            LogicalKeyboardKey.numpadEnter,
            control: true,
          ): () =>
              unawaited(_sidebar.currentState?.saveAll() ?? Future.value()),
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: WorkspaceLayout(
            sidebar: LedgerSidebar(
              key: _sidebar,
              ledger: widget.ledger,
              onError: _showError,
            ),
            content: Column(
              children: [
                _balances(context),
                const SizedBox(height: 16),
                Expanded(child: _browse(context)),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _balances(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget balance(
      String title,
      int amount, {
      String? id,
      double width = 180,
    }) => Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
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
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final count = _state.accounts.length + 1;
                final width =
                    ((constraints.maxWidth - (count - 1) * 10) / count).clamp(
                      136.0,
                      240.0,
                    );
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      balance('资金总额', _state.totalCents, width: width),
                      const SizedBox(width: 10),
                      balance(
                        cash.name,
                        cash.balanceCents,
                        id: cash.id,
                        width: width,
                      ),
                      for (final account in _state.accounts.values.where(
                        (item) => item.id != cash.id,
                      )) ...[
                        const SizedBox(width: 10),
                        balance(
                          account.name,
                          account.balanceCents,
                          id: account.id,
                          width: width,
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            key: const ValueKey('account-actions'),
            tooltip: '账户操作',
            enabled: !_saving && !widget.ledger.busy,
            onSelected: (value) => unawaited(switch (value) {
              'transfer' => showMoneyMovement(
                context,
                widget.ledger,
                MoneyKind.transfer,
              ),
              'adjustment' => showMoneyMovement(
                context,
                widget.ledger,
                MoneyKind.adjustment,
              ),
              _ => showLedgerAccounts(context, widget.ledger),
            }),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'transfer', child: Text('转账')),
              PopupMenuItem(value: 'adjustment', child: Text('余额校准')),
              PopupMenuItem(value: 'manage', child: Text('管理账户')),
            ],
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ],
      ),
    );
  }

  Widget _browse(BuildContext context) => WorkspacePanel(
    key: const ValueKey('ledger-browse-panel'),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('money-previous-month'),
                tooltip: _displayPeriod == LedgerPeriod.year ? '上一年' : '上个月',
                onPressed: () => _stepPeriod(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              SizedBox(
                width: 108,
                child: TextField(
                  key: const ValueKey('money-month'),
                  controller: _monthText,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: _displayPeriod == LedgerPeriod.year
                        ? 'YYYY'
                        : 'YYYY-MM',
                  ),
                  onSubmitted: (_) => _parseMonth(),
                ),
              ),
              IconButton(
                key: const ValueKey('money-next-month'),
                tooltip: _displayPeriod == LedgerPeriod.year ? '下一年' : '下个月',
                onPressed: () => _stepPeriod(1),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                onPressed: () => _setMonth(widget.ledger.clock()),
                child: Text(_displayPeriod == LedgerPeriod.year ? '本年' : '本月'),
              ),
              const Spacer(),
              AppSegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('流水')),
                  ButtonSegment(value: true, label: Text('分类统计')),
                ],
                selected: {_statistics},
                onSelectionChanged: (values) => setState(() {
                  _statistics = values.single;
                  _updatePeriodText();
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_statistics) ...[
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                AppSegmentedButton<LedgerPeriod>(
                  key: const ValueKey('stats-period'),
                  segments: const [
                    ButtonSegment(value: LedgerPeriod.month, label: Text('按月')),
                    ButtonSegment(value: LedgerPeriod.year, label: Text('按年')),
                  ],
                  selected: {_period},
                  onSelectionChanged: (values) => setState(() {
                    _period = values.single;
                    _statsParent = null;
                    _updatePeriodText();
                  }),
                ),
                AppSegmentedButton<MoneyKind>(
                  key: const ValueKey('stats-kind'),
                  segments: const [
                    ButtonSegment(value: MoneyKind.expense, label: Text('支出')),
                    ButtonSegment(value: MoneyKind.income, label: Text('收入')),
                  ],
                  selected: {_statsKind},
                  onSelectionChanged: (values) => setState(() {
                    _statsKind = values.single;
                    _statsParent = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Text(
                '支出  ¥ ${moneyText(_state.periodTotal(_month, _displayPeriod, MoneyKind.expense))}',
                key: const ValueKey('month-expense'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 28),
              Text(
                '收入  ¥ ${moneyText(_state.periodTotal(_month, _displayPeriod, MoneyKind.income))}',
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
    final dailyTotals = _state.dailyTotals;
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
          final totals = dailyTotals[record.date]!;
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
                  key: ValueKey('money-day-${dateText(record.date)}'),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Text(
                        dateText(record.date),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          Text(
                            '支出  ¥ ${moneyText(totals.expenseCents)}',
                            key: ValueKey(
                              'day-expense-${dateText(record.date)}',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            '收入  ¥ ${moneyText(totals.incomeCents)}',
                            key: ValueKey(
                              'day-income-${dateText(record.date)}',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
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
                        } else if (value == 'notes') {
                          unawaited(
                            showMoneyNotes(context, widget.ledger, record),
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
                        const PopupMenuItem(
                          value: 'notes',
                          child: Text('修改备注'),
                        ),
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
                onTap: _saving || widget.ledger.busy
                    ? null
                    : () => unawaited(
                        [
                              MoneyKind.expense,
                              MoneyKind.income,
                            ].contains(record.kind)
                            ? showMoneyEditor(
                                context,
                                widget.ledger,
                                record: record,
                              )
                            : showMoneyNotes(context, widget.ledger, record),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stats(BuildContext context) => LedgerStatistics(
    state: _state,
    anchor: _month,
    period: _period,
    kind: _statsKind,
    parentId: _statsParent,
    onParentChanged: (id) => setState(() => _statsParent = id),
  );
}
