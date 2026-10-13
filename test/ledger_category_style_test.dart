import 'package:daymark/domain/ledger.dart';
import 'package:daymark/ui/ledger_category_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final state = LedgerState.empty();
  test('inherited siblings and repeated root hues remain distinguishable', () {
    final children = ['breakfast', 'lunch', 'dinner', 'other-food'];
    expect(
      children.map((id) => ledgerCategoryColor(state, id)).toSet().length,
      4,
    );
    expect(
      ledgerCategoryColor(state, 'housing'),
      isNot(ledgerCategoryColor(state, 'transport')),
    );
    expect(
      ledgerCategoryColor(state, 'daily'),
      isNot(ledgerCategoryColor(state, 'spending')),
    );
    expect(
      ledgerCategorySwatch(state, 'lunch'),
      ledgerCategorySwatch(state, 'food'),
    );
  });

  test(
    'badge foreground stays readable across all Material families and shades',
    () {
      for (final family in CategoryColor.values) {
        for (final shade in [300, 400, 500, 600, 700, 800]) {
          final fill = categorySwatch(family)[shade]!;
          final ink = ledgerCategoryInk(fill);
          final ratio = ink == Colors.black
              ? (fill.computeLuminance() + .05) / .05
              : 1.05 / (fill.computeLuminance() + .05);
          expect(ratio, greaterThanOrEqualTo(4.5));
        }
      }
    },
  );

  test('explicit colors and custom category IDs remain supported', () {
    final custom = state.copyWith(
      categories: {
        ...state.categories,
        'lunch': const MoneyCategory(
          'lunch',
          '午餐',
          MoneyKind.expense,
          'food',
          CategoryColor.pink,
        ),
        'custom': const MoneyCategory('custom', '应用', MoneyKind.expense),
      },
    );
    expect(ledgerCategorySwatch(custom, 'lunch'), Colors.pink);
    final renamed = custom.copyWith(
      categories: {
        ...custom.categories,
        'custom': const MoneyCategory('custom', '自定义应用', MoneyKind.expense),
      },
    );
    expect(
      ledgerCategorySwatch(renamed, 'custom'),
      ledgerCategorySwatch(custom, 'custom'),
    );
    expect(ledgerCategoryIcon(custom, 'custom'), Icons.label_outline);
  });
}
