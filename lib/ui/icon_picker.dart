import 'package:flutter/material.dart';

import '../domain/ledger.dart';
import 'ledger_icons.dart';

/// Returns the chosen icon name, an empty string for "automatic/inherit", or
/// null when the dialog is dismissed.
///
/// [kind] limits the groups to income or expense so the two lists stay apart.
Future<String?> showLedgerIconPicker(
  BuildContext context, {
  String? selected,
  MoneyKind? kind,
}) => showDialog<String>(
  context: context,
  builder: (_) => _LedgerIconPicker(selected: selected, kind: kind),
);

class _LedgerIconPicker extends StatefulWidget {
  const _LedgerIconPicker({this.selected, this.kind});
  final String? selected;
  final MoneyKind? kind;
  @override
  State<_LedgerIconPicker> createState() => _LedgerIconPickerState();
}

class _LedgerIconPickerState extends State<_LedgerIconPicker> {
  late final List<String> _groups = ledgerIconGroupsFor(
    widget.kind ?? MoneyKind.expense,
  );
  late String _group = _initialGroup();
  final _query = TextEditingController();

  /// Opens on the selected icon's group so the current choice stays visible.
  String _initialGroup() {
    final option = ledgerIconByName[widget.selected];
    return option != null && _groups.contains(option.group)
        ? option.group
        : _groups.first;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Group browsing by default; typing searches every group of this kind.
  List<LedgerIconOption> _options() {
    final query = _query.text.trim();
    return query.isEmpty
        ? searchLedgerIcons('', groups: {_group})
        : searchLedgerIcons(query, groups: _groups.toSet());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final options = _options();
    return AlertDialog(
      title: const Text('选择图标'),
      content: SizedBox(
        width: 560,
        height: 436,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('ledger-icon-search'),
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索图标，例如 咖啡、地铁、公积金',
                prefixIcon: Icon(Icons.search, size: 20),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                final matches = _options();
                if (matches.isNotEmpty) {
                  Navigator.pop(context, matches.first.name);
                }
              },
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final group in _groups)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          key: ValueKey('ledger-icon-group-$group'),
                          label: Text(group),
                          selected: _group == group,
                          onSelected: (_) => setState(() {
                            _group = group;
                            _query.clear();
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: options.isEmpty
                  ? Center(
                      child: Text(
                        '没有匹配的图标',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : GridView.builder(
                      itemCount: options.length,
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 66,
                            mainAxisExtent: 66,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                      itemBuilder: (context, index) {
                        final option = options[index];
                        final selected = option.name == widget.selected;
                        return InkWell(
                          key: ValueKey('ledger-icon-${option.name}'),
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => Navigator.pop(context, option.name),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? scheme.secondaryContainer
                                  : null,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  ledgerIconData(option.name),
                                  size: 22,
                                  color: selected
                                      ? scheme.onSecondaryContainer
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  option.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        fontSize: 10,
                                        color: selected
                                            ? scheme.onSecondaryContainer
                                            : scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('ledger-icon-inherit'),
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('使用自动／继承'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
