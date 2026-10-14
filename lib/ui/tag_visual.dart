import 'package:flutter/material.dart';
import 'theme_tokens.dart';
import 'workspace_style.dart';

/// A single contrast rule for badges, event fills and category highlights.
(Color, Color) tagSurfaceColors(
  MaterialColor family,
  Color accent, {
  double opacity = .24,
  Color surface = Colors.white,
  Color? fallbackInk,
}) {
  final fill = Color.alphaBlend(accent.withValues(alpha: opacity), surface);
  final ink = family[900]!;
  final lightness = fill.computeLuminance() + .05;
  final inkLightness = ink.computeLuminance() + .05;
  final contrast = lightness > inkLightness
      ? lightness / inkLightness
      : inkLightness / lightness;
  return (fill, contrast >= 4.5 ? ink : fallbackInk ?? Colors.grey[800]!);
}

class AppTagBadge extends StatelessWidget {
  const AppTagBadge({
    super.key,
    required this.family,
    required this.accent,
    this.icon = Icons.label_outline,
    this.size = WorkspaceStyle.tagSize,
  });
  final MaterialColor family;
  final Color accent;
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) {
    final colors = DaymarkColors.of(context);
    final (fill, ink) = tagSurfaceColors(
      family,
      colors.categoryAccent(accent),
      surface: colors.badgeSurface,
      fallbackInk: colors.badgeFallbackInk,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(icon, size: size * .58, color: ink),
    );
  }
}
