import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../application/journal_controller.dart';
import '../application/ledger_controller.dart';
import '../domain/appearance.dart';
import 'palette_picker.dart';
import 'journal_screen.dart';
import 'ledger_screen.dart';
import 'title_bar.dart';

class AppScreen extends StatefulWidget {
  const AppScreen({
    super.key,
    required this.journal,
    required this.ledger,
    this.palette = AppPalette.slate,
    this.onPaletteChanged,
  });
  final JournalController journal;
  final LedgerController ledger;
  final AppPalette palette;
  final ValueChanged<AppPalette>? onPaletteChanged;
  @override
  State<AppScreen> createState() => _AppScreenState();
}

class _AppScreenState extends State<AppScreen> {
  final _journal = GlobalKey<JournalScreenState>();
  final _ledgerFocus = FocusNode();
  final _journalScope = FocusScopeNode(debugLabel: 'journal-workspace');
  int _page = 0;
  bool _visitedLedger = false;
  @override
  void dispose() {
    _ledgerFocus.dispose();
    _journalScope.dispose();
    super.dispose();
  }

  void _focusPage() {
    if (_page == 1) {
      _ledgerFocus.requestFocus();
    } else {
      _journalScope.requestFocus();
    }
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
          height: 48,
          leadingWidth: 160,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          leading: DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'D',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      'Daymark',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PalettePicker(
              selected: widget.palette,
              onChanged: widget.onPaletteChanged == null
                  ? null
                  : (palette) {
                      widget.onPaletteChanged!(palette);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _focusPage();
                      });
                    },
            ),
          ),
        ),
        Expanded(
          child: Row(
            children: [
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: SizedBox(
                  width: 64,
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      _mode(context, 0, '时间记录', Icons.schedule),
                      const SizedBox(height: 8),
                      _mode(
                        context,
                        1,
                        '记账',
                        Icons.account_balance_wallet_outlined,
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _page,
                  children: [
                    FocusScope(
                      node: _journalScope,
                      canRequestFocus: _page == 0,
                      // Re-enable descendants explicitly on this retained node.
                      descendantsAreFocusable: _page == 0,
                      descendantsAreTraversable: _page == 0,
                      child: JournalScreen(
                        key: _journal,
                        journal: widget.journal,
                        showTitleBar: false,
                      ),
                    ),
                    FocusScope(
                      canRequestFocus: _page == 1,
                      descendantsAreFocusable: _page == 1,
                      descendantsAreTraversable: _page == 1,
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
        ),
      ],
    ),
  );
  Widget _mode(BuildContext context, int index, String label, IconData icon) =>
      IconButton(
        key: ValueKey('mode-$index'),
        onPressed: () => unawaited(_switch(index)),
        tooltip: label,
        isSelected: _page == index,
        style: IconButton.styleFrom(
          foregroundColor: _page == index
              ? Theme.of(context).colorScheme.onSecondaryContainer
              : Theme.of(context).colorScheme.onSurfaceVariant,
          backgroundColor: _page == index
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
          fixedSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: Icon(icon, size: 22),
      );
}
