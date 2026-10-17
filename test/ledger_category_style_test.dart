import 'package:daymark/domain/ledger.dart';
import 'package:daymark/ui/ledger_category_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final state = LedgerState.empty();
  test('inherited siblings and repeated root hues remain distinguishable', () {
    final children = ['breakfast', 'lunch', 'dinner', 'other-food', 'coffee'];
    final withCoffee = state.copyWith(
      categories: {
        ...state.categories,
        'coffee': const MoneyCategory(
          'coffee',
          '咖啡',
          MoneyKind.expense,
          'food',
        ),
      },
    );
    expect(
      children.map((id) => ledgerCategoryColor(withCoffee, id)).toSet().length,
      5,
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
    'soft badges keep readable colored icons across every Material family',
    () {
      for (final family in CategoryColor.values) {
        final colored = state.copyWith(
          categories: {
            ...state.categories,
            'food': MoneyCategory(
              'food',
              '餐饮',
              MoneyKind.expense,
              null,
              family,
            ),
          },
        );
        for (final id in [
          'food',
          'breakfast',
          'lunch',
          'dinner',
          'other-food',
        ]) {
          final (fill, ink) = ledgerCategoryBadgeColors(colored, id);
          final ratio =
              (fill.computeLuminance() + .05) / (ink.computeLuminance() + .05);
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

  test('explicit icons win, children inherit and unknown names fall back', () {
    const coffee = MoneyCategory(
      'food',
      '餐饮',
      MoneyKind.expense,
      null,
      null,
      'local_cafe',
    );
    final withIcon = state.copyWith(
      categories: {...state.categories, 'food': coffee},
    );
    expect(ledgerCategoryIcon(withIcon, 'food'), Icons.local_cafe_outlined);
    expect(ledgerCategoryIcon(withIcon, 'lunch'), Icons.local_cafe_outlined);

    // A child's own icon overrides the inherited one.
    final childIcon = withIcon.copyWith(
      categories: {
        ...withIcon.categories,
        'lunch': const MoneyCategory(
          'lunch',
          '午餐',
          MoneyKind.expense,
          'food',
          null,
          'ramen_dining',
        ),
      },
    );
    expect(ledgerCategoryIcon(childIcon, 'lunch'), Icons.ramen_dining_outlined);
    expect(ledgerCategoryIcon(childIcon, 'dinner'), Icons.local_cafe_outlined);

    final unknown = state.copyWith(
      categories: {
        ...state.categories,
        'food': const MoneyCategory(
          'food',
          '餐饮',
          MoneyKind.expense,
          null,
          null,
          'not_a_real_icon',
        ),
      },
    );
    expect(ledgerCategoryIcon(unknown, 'lunch'), Icons.restaurant_outlined);

    final cleared = state.copyWith(
      categories: {
        ...state.categories,
        'food': const MoneyCategory('food', '餐饮', MoneyKind.expense),
      },
    );
    expect(ledgerCategoryIcon(cleared, 'lunch'), Icons.restaurant_outlined);
  });
}
