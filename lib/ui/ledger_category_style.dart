import 'package:flutter/material.dart';

import '../domain/ledger.dart';

MaterialColor categorySwatch(CategoryColor color) => switch (color) {
  CategoryColor.green => Colors.green,
  CategoryColor.teal => Colors.teal,
  CategoryColor.cyan => Colors.cyan,
  CategoryColor.blue => Colors.blue,
  CategoryColor.indigo => Colors.indigo,
  CategoryColor.purple => Colors.purple,
  CategoryColor.pink => Colors.pink,
  CategoryColor.red => Colors.red,
  CategoryColor.orange => Colors.orange,
  CategoryColor.amber => Colors.amber,
  CategoryColor.lightGreen => Colors.lightGreen,
  CategoryColor.blueGrey => Colors.blueGrey,
};

String categoryColorText(CategoryColor color) => switch (color) {
  CategoryColor.green => '绿色',
  CategoryColor.teal => '青绿',
  CategoryColor.cyan => '青色',
  CategoryColor.blue => '蓝色',
  CategoryColor.indigo => '靛蓝',
  CategoryColor.purple => '紫色',
  CategoryColor.pink => '粉色',
  CategoryColor.red => '红色',
  CategoryColor.orange => '橙色',
  CategoryColor.amber => '金色',
  CategoryColor.lightGreen => '浅绿',
  CategoryColor.blueGrey => '蓝灰',
};

MaterialColor ledgerCategorySwatch(LedgerState state, String? id) {
  if (id == null || !state.categories.containsKey(id)) return Colors.blueGrey;
  final path = state.ancestors(id);
  for (final category in path.reversed) {
    if (category.color != null) return categorySwatch(category.color!);
  }
  final hash = path.first.id.codeUnits.fold<int>(
    0,
    (sum, unit) => (sum * 31 + unit) & 0x7fffffff,
  );
  return categorySwatch(
    CategoryColor.values[hash.abs() % CategoryColor.values.length],
  );
}

Color ledgerCategoryColor(LedgerState state, String? id) {
  final family = ledgerCategorySwatch(state, id);
  if (id == null || !state.categories.containsKey(id)) return family[500]!;
  final category = state.categories[id]!;
  final ordered = state.orderedCategories(category.kind);
  int shade;
  if (category.parentId == null) {
    final peers = ordered
        .where(
          (item) =>
              item.parentId == null &&
              ledgerCategorySwatch(state, item.id) == family,
        )
        .toList();
    // Repeated root hues still differ visibly, as do inherited sibling tags.
    const steps = [500, 700, 300, 800, 400, 600];
    shade = steps[peers.indexWhere((item) => item.id == id) % steps.length];
  } else if (category.color != null) {
    shade = 500;
  } else {
    final path = state.ancestors(id);
    final anchor = path.reversed.firstWhere(
      (item) => item.color != null,
      orElse: () => path.first,
    );
    final members = ordered
        .where(
          (item) =>
              item.id != anchor.id &&
              state
                  .ancestors(item.id)
                  .any((parent) => parent.id == anchor.id) &&
              ledgerCategorySwatch(state, item.id) == family,
        )
        .toList();
    const steps = [400, 600, 300, 700, 800, 500];
    shade = steps[members.indexWhere((item) => item.id == id) % steps.length];
  }
  return family[shade]!;
}

Color ledgerCategoryInk(Color fill) =>
    fill.computeLuminance() > .179 ? Colors.black : Colors.white;

IconData ledgerCategoryIcon(LedgerState state, String? id) {
  if (id == null || !state.categories.containsKey(id)) {
    return Icons.label_outline;
  }
  return switch (state.ancestors(id).first.id) {
    'food' => Icons.restaurant_outlined,
    'housing' => Icons.home_outlined,
    'daily' => Icons.cleaning_services_outlined,
    'transport' => Icons.directions_bus_outlined,
    'clothing' => Icons.checkroom_outlined,
    'hobby' => Icons.favorite_border,
    'health' => Icons.medical_services_outlined,
    'topup' => Icons.account_balance_wallet_outlined,
    'spending' => Icons.payments_outlined,
    'shopping' => Icons.shopping_bag_outlined,
    'entertainment' => Icons.sports_esports_outlined,
    'bills' => Icons.receipt_long_outlined,
    'salary' || 'bonus' => Icons.savings_outlined,
    _ => Icons.label_outline,
  };
}

class LedgerCategoryBadge extends StatelessWidget {
  const LedgerCategoryBadge({
    super.key,
    required this.state,
    required this.id,
    this.size = 32,
  });
  final LedgerState state;
  final String? id;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fill = ledgerCategoryColor(state, id);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Icon(
        ledgerCategoryIcon(state, id),
        size: size * .58,
        color: ledgerCategoryInk(fill),
      ),
    );
  }
}
