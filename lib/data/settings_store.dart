import 'dart:convert';
import 'dart:io';

import '../domain/settings.dart';
import 'atomic_file.dart';
import 'store.dart' show FileWriter;

class SettingsStore {
  SettingsStore._(this.directory, this._writer);

  final Directory directory;
  final FileWriter _writer;
  AppSettings _state = const AppSettings();
  AppSettings get state => _state;
  File get file => File('${directory.path}/settings.json');
  Object? _readError;
  Object? get readError => _readError;

  static Future<SettingsStore> open(
    Directory directory, {
    FileWriter writer = AtomicFile.write,
  }) async {
    final store = SettingsStore._(directory.absolute, writer);
    try {
      await store.directory.create(recursive: true);
      if (await store.file.exists()) {
        store._state = AppSettings.fromJson(
          jsonDecode(
            (await store.file.readAsString()).replaceFirst(
              RegExp(r'^\uFEFF'),
              '',
            ),
          ),
        );
      }
    } on FormatException catch (error) {
      // Preferences must not prevent access to journal records.
      // Keep the file untouched until the user explicitly saves settings.
      store._readError = error;
    } on FileSystemException catch (error) {
      store._readError = error;
    }
    return store;
  }

  Future<void> replace(AppSettings desired) async {
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
