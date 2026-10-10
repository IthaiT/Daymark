import 'dart:io';

import 'package:daymark/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'CLI preserves explicit data directory and rejects invalid arguments',
    () {
      final path = Directory('.test-artifacts/custom-journal').absolute.path;
      expect(dataDirectory(['--data-dir', path]).path, path);
      expect(dataDirectory(['--data-dir=$path']).path, path);
      for (final args in [
        ['--data-dir'],
        ['--data-dir='],
        ['--data-dir=   '],
        ['--data-dir', ''],
        ['unexpected'],
      ]) {
        expect(() => dataDirectory(args), throwsFormatException);
      }
    },
  );

  test(
    'default is repository data or adjacent journal, never Flutter assets',
    () async {
      final directory = await (await Directory(
        '.test-artifacts',
      ).create()).createTemp('startup-');
      try {
        final root = Directory('${directory.path}/repo')..createSync();
        Directory('${root.path}/lib').createSync();
        final manifest = File('${root.path}/pubspec.yaml')
          ..writeAsStringSync('name: daymark\n');
        final executable =
            '${root.path}/build/windows/x64/runner/Release/daymark.exe';
        expect(
          dataDirectory([], executable: executable).path,
          Directory('${root.path}/data').absolute.path,
        );
        manifest.writeAsStringSync('name: other_flutter_app\n');
        expect(
          dataDirectory([], executable: executable).path,
          Directory('${File(executable).parent.path}/journal').absolute.path,
        );
        expect(Directory('${root.path}/data').existsSync(), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
