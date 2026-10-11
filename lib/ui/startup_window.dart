import 'dart:math' as math;
import 'dart:ui';

/// Fits the whole window, including its title bar, inside logical work bounds.
({Rect bounds, Size minimumSize}) startupWindowGeometry(Rect workArea) {
  final size = Size(
    math.min(1360, workArea.width * 0.95),
    math.min(900, workArea.height * 0.95),
  );
  final bounds = Rect.fromCenter(
    center: workArea.center,
    width: size.width,
    height: size.height,
  );
  return (
    bounds: bounds,
    minimumSize: Size(
      math.min(1100, bounds.width),
      math.min(740, bounds.height),
    ),
  );
}
