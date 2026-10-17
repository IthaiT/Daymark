import 'package:flutter/foundation.dart';

import '../data/appearance_store.dart';
import '../domain/appearance.dart';

class AppearanceController extends ChangeNotifier {
  AppearanceController([this.store]);

  final AppearanceStore? store;
  AppAppearance _state = const AppAppearance();
  AppAppearance get state => store?.state ?? _state;
  bool _busy = false;
  bool get busy => _busy;
  bool _disposed = false;
  Future<void> _tail = Future.value();

  Future<void> setPalette(AppPalette palette) => _change(() {
    if (state.palette == palette) return null;
    return state.withPalette(palette);
  });

  Future<void> setTagColor(String tagId, TagColor? color) => _change(() {
    if (state.tagColors[tagId] == color) return null;
    return state.withTagColor(tagId, color);
  });

  /// Serializes appearance writes; a null result means nothing changed.
  Future<void> _change(AppAppearance? Function() build) {
    final result = _tail.then((_) async {
      if (_disposed) return;
      final desired = build();
      if (desired == null) return;
      _busy = true;
      notifyListeners();
      try {
        if (store != null) await store!.replace(desired);
        _state = desired;
      } finally {
        _busy = false;
        if (!_disposed) notifyListeners();
      }
    });
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
