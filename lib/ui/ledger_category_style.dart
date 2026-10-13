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
    final presetOrder = {
      for (final (index, item) in defaultMoneyCategories.indexed)
        item.id: index,
    };
    peers.sort(
      (a, b) => (presetOrder[a.id] ?? 1000 + ordered.indexOf(a)).compareTo(
        presetOrder[b.id] ?? 1000 + ordered.indexOf(b),
      ),
    );
    const steps = [300, 400, 500, 200, 600, 100];
    shade = steps[peers.indexWhere((item) => item.id == id) % steps.length];
  } else if (category.color != null) {
    shade = 400;
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
    const steps = [300, 400, 200, 500, 600, 100];
    shade = steps[members.indexWhere((item) => item.id == id) % steps.length];
  }
  // These two teal presets separate housing's emerald from transport's aqua.
  if (family == Colors.teal) {
    if (id == 'housing') return Colors.tealAccent[700]!;
    if (id == 'transport') return Colors.teal[300]!;
  }
  return family[shade]!;
}

/// Soft category badges use a dark hue, while charts keep the full accent.
(Color, Color) ledgerCategoryBadgeColors(LedgerState state, String? id) {
  final accent = ledgerCategoryColor(state, id);
  final fill = Color.alphaBlend(accent.withValues(alpha: .24), Colors.white);
  final ink = ledgerCategorySwatch(state, id)[900]!;
  final contrast =
      (fill.computeLuminance() + .05) / (ink.computeLuminance() + .05);
  return (fill, contrast >= 4.5 ? ink : Colors.grey[800]!);
}

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
    final (fill, ink) = ledgerCategoryBadgeColors(state, id);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(ledgerCategoryIcon(state, id), size: size * .58, color: ink),
    );
  }
}
