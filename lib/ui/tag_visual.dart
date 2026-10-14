import 'package:flutter/material.dart';
import 'workspace_style.dart';

/// A single contrast rule for badges, event fills and category highlights.
(Color, Color) tagSurfaceColors(
  MaterialColor family,
  Color accent, {
  double opacity = .24,
}) {
  final fill = Color.alphaBlend(
    accent.withValues(alpha: opacity),
    Colors.white,
  );
  final ink = family[900]!;
  final contrast =
      (fill.computeLuminance() + .05) / (ink.computeLuminance() + .05);
  return (fill, contrast >= 4.5 ? ink : Colors.grey[800]!);
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
    final (fill, ink) = tagSurfaceColors(family, accent);
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
