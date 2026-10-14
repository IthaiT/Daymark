import 'package:flutter/material.dart';

/// Colors for Daymark visuals that are outside the standard Material roles.
class DaymarkColors extends ThemeExtension<DaymarkColors> {
  const DaymarkColors({
    required this.primary,
    required this.badgeSurface,
    required this.badgeFallbackInk,
    required this.income,
    required this.expense,
  });

  factory DaymarkColors.fromScheme(ColorScheme scheme) => DaymarkColors(
    primary: scheme.primary,
    badgeSurface: scheme.surfaceContainerLowest,
    badgeFallbackInk: scheme.onSurface,
    income: Colors.green.shade800,
    expense: scheme.error,
  );

  static DaymarkColors of(BuildContext context) =>
      Theme.of(context).extension<DaymarkColors>() ??
      DaymarkColors.fromScheme(Theme.of(context).colorScheme);

  final Color primary;
  final Color badgeSurface;
  final Color badgeFallbackInk;
  final Color income;
  final Color expense;

  Color categoryAccent(Color color) => Color.lerp(color, primary, .12)!;

  @override
  DaymarkColors copyWith({
    Color? primary,
    Color? badgeSurface,
    Color? badgeFallbackInk,
    Color? income,
    Color? expense,
  }) => DaymarkColors(
    primary: primary ?? this.primary,
    badgeSurface: badgeSurface ?? this.badgeSurface,
    badgeFallbackInk: badgeFallbackInk ?? this.badgeFallbackInk,
    income: income ?? this.income,
    expense: expense ?? this.expense,
  );

  @override
  DaymarkColors lerp(covariant DaymarkColors? other, double t) {
    if (other == null) return this;
    return DaymarkColors(
      primary: Color.lerp(primary, other.primary, t)!,
      badgeSurface: Color.lerp(badgeSurface, other.badgeSurface, t)!,
      badgeFallbackInk: Color.lerp(
        badgeFallbackInk,
        other.badgeFallbackInk,
        t,
      )!,
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
    );
  }
}
