import 'dart:io';

import 'package:daymark/main.dart';
import 'package:daymark/ui/startup_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large work areas retain the preferred window and minimum sizes', () {
    const workArea = Rect.fromLTWH(0, 0, 1920, 1040);
    final geometry = startupWindowGeometry(workArea);
    expect(geometry.bounds.size, const Size(1360, 900));
    expect(geometry.minimumSize, const Size(1100, 740));
    expect(geometry.bounds.center, workArea.center);
  });

  test('small and DPI-scaled work areas contain the complete window', () {
    for (final physicalSize in [
      const Size(1920, 1040),
      const Size(1366, 728),
    ]) {
      for (final scale in [1.0, 1.25, 1.5, 2.0, 2.5, 3.0]) {
        final workArea = Offset.zero & (physicalSize / scale);
        final geometry = startupWindowGeometry(workArea);
        expect(geometry.bounds.left, greaterThanOrEqualTo(workArea.left));
        expect(geometry.bounds.top, greaterThanOrEqualTo(workArea.top));
        expect(geometry.bounds.right, lessThanOrEqualTo(workArea.right));
        expect(geometry.bounds.bottom, lessThanOrEqualTo(workArea.bottom));
        expect(
          geometry.minimumSize.width,
          lessThanOrEqualTo(geometry.bounds.width),
        );
        expect(
          geometry.minimumSize.height,
          lessThanOrEqualTo(geometry.bounds.height),
        );
        expect(
          (geometry.bounds.center - workArea.center).distance,
          closeTo(0, 1e-6),
        );
      }
    }
  });

  test('centering respects work area offsets and taskbars on any edge', () {
    for (final workArea in [
      const Rect.fromLTWH(60, 40, 1306, 728),
      const Rect.fromLTWH(-1280, -40, 1280, 680),
    ]) {
      final bounds = startupWindowGeometry(workArea).bounds;
      expect((bounds.center - workArea.center).distance, closeTo(0, 1e-6));
      expect(bounds.intersect(workArea), bounds);
    }
  });

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
