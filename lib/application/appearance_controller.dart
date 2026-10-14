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

  Future<void> setPalette(AppPalette palette) {
    final result = _tail.then((_) async {
      if (_disposed || state.palette == palette) return;
      _busy = true;
      notifyListeners();
      try {
        final desired = state.withPalette(palette);
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
