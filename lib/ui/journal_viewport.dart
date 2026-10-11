import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Keeps existing panels usable when DPI scaling leaves a very small screen.
class JournalViewport extends StatelessWidget {
  const JournalViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        primary: false,
        child: SingleChildScrollView(
          primary: false,
          child: SizedBox(
            width: math.max(760, constraints.maxWidth),
            height: math.max(440, constraints.maxHeight),
            child: child,
          ),
        ),
      );
    },
  );
}
