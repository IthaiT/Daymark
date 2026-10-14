import 'dart:convert';
import 'dart:io';

import '../domain/appearance.dart';
import 'atomic_file.dart';
import 'store.dart' show FileWriter;

class AppearanceStore {
  AppearanceStore._(this.directory, this._writer);

  final Directory directory;
  final FileWriter _writer;
  AppAppearance _state = const AppAppearance();
  AppAppearance get state => _state;
  File get file => File('${directory.path}/appearance.json');
  Object? _readError;
  Object? get readError => _readError;

  static Future<AppearanceStore> open(
    Directory directory, {
    FileWriter writer = AtomicFile.write,
  }) async {
    final store = AppearanceStore._(directory.absolute, writer);
    try {
      if (await store.file.exists()) {
        store._state = AppAppearance.fromJson(
          jsonDecode(
            (await store.file.readAsString()).replaceFirst(
              RegExp(r'^\uFEFF'),
              '',
            ),
          ),
        );
      }
    } on FormatException catch (error) {
      // Preferences must not prevent access to journal or ledger records.
      // Keep the file untouched until the user explicitly chooses a theme.
      store._readError = error;
    } on FileSystemException catch (error) {
      store._readError = error;
    }
    return store;
  }

  Future<void> replace(AppAppearance desired) async {
    await directory.create(recursive: true);
    await _writer(
      file,
      utf8.encode(
        '${const JsonEncoder.withIndent('  ').convert(desired.toJson())}\n',
      ),
    );
    _state = desired;
    _readError = null;
  }
}
