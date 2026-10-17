import 'package:flutter/foundation.dart';

import '../data/settings_store.dart';
import '../domain/settings.dart';

class SettingsController extends ChangeNotifier {
  SettingsController([this.store]);

  final SettingsStore? store;
  AppSettings _state = const AppSettings();
  AppSettings get state => store?.state ?? _state;
  bool _disposed = false;
  Future<void> _tail = Future.value();

  /// Persists [desired]; the visible state only advances after a real write.
  Future<void> update(AppSettings desired) {
    final result = _tail.then((_) async {
      if (_disposed || desired == state) return;
      if (store != null) await store!.replace(desired);
      _state = desired;
      if (!_disposed) notifyListeners();
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
