import 'dart:async';

import 'package:flutter/material.dart';

import '../application/journal_controller.dart';
import '../application/ledger_controller.dart';
import 'journal_screen.dart';
import 'ledger_screen.dart';
import 'title_bar.dart';

class AppScreen extends StatefulWidget {
  const AppScreen({super.key, required this.journal, required this.ledger});
  final JournalController journal;
  final LedgerController ledger;
  @override
  State<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends State<AppScreen> {
  final _journal = GlobalKey<JournalScreenState>();
  final _ledgerFocus = FocusNode();
  int _page = 0;
  bool _visitedLedger = false;
  @override
  void dispose() {
    _ledgerFocus.dispose();
    super.dispose();
  }

  void _focusPage() {
    if (_page == 1) _ledgerFocus.requestFocus();
  }

  Future<void> _switch(int page) async {
    if (page == _page) {
      _focusPage();
      return;
    }
    if (_page == 0 &&
        !await (_journal.currentState?.commit() ?? Future.value(true))) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _page = page;
      if (page == 1) _visitedLedger = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusPage();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        WindowTitleBar(
          leading: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _mode(0, '时间记录', Icons.schedule),
              _mode(1, '记账', Icons.account_balance_wallet_outlined),
            ],
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _page,
            children: [
              FocusScope(
                canRequestFocus: _page == 0,
                child: JournalScreen(
                  key: _journal,
                  journal: widget.journal,
                  showTitleBar: false,
                ),
              ),
              FocusScope(
                canRequestFocus: _page == 1,
                child: _visitedLedger
                    ? LedgerScreen(
                        ledger: widget.ledger,
                        focusNode: _ledgerFocus,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _mode(int index, String label, IconData icon) => TextButton.icon(
    key: ValueKey('mode-$index'),
    onPressed: () => unawaited(_switch(index)),
    style: TextButton.styleFrom(
      foregroundColor: _page == index
          ? Theme.of(context).colorScheme.onSecondaryContainer
          : Theme.of(context).colorScheme.onSurfaceVariant,
      backgroundColor: _page == index
          ? Theme.of(context).colorScheme.secondaryContainer
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 10),
    ),
    icon: Icon(icon, size: 16),
    label: Text(label),
  );
}
