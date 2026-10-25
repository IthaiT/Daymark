import 'package:flutter/foundation.dart';

import '../data/appearance_store.dart';
import '../domain/appearance.dart';
import '../domain/journal_view_preferences.dart';
import '../domain/model.dart';
import '../domain/tag_colors.dart';

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

  Future<void> setTagStyle(
    String tagId,
    TagColor? color,
    TagDisplay? display,
  ) => _change(() {
    if (state.tagColors[tagId] == color &&
        state.tagDisplays[tagId] == display) {
      return null;
    }
    return state.withTagStyle(tagId, color, display);
  });

  Future<void> setJournalView(JournalViewPreferences value) => _change(() {
    if (state.journalView == value) return null;
    return state.copyWith(journalView: value);
  });

  Future<void> ensureRootColors(Iterable<Tag> tags) {
    final snapshot = tags.toList();
    return _change(() {
      // Automatic migration must not replace an unreadable preferences file.
      if (store?.readError != null) return null;
      final colors = assignRootColors(snapshot, state.tagColors);
      if (mapEquals(colors, state.tagColors)) return null;
      return state.copyWith(tagColors: colors);
    });
  }

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
