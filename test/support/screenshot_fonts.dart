import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadScreenshotFonts(WidgetTester tester) async {
  for (final entry in [
    (
      'Noto Sans SC',
      const String.fromEnvironment(
        'DAYMARK_TEXT_FONT',
        defaultValue: 'assets/fonts/NotoSansSC.ttf',
      ),
    ),
    (
      'MaterialIcons',
      const String.fromEnvironment(
        'DAYMARK_ICON_FONT',
        defaultValue:
            '.tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ),
  ]) {
    expect(File(entry.$2).existsSync(), isTrue, reason: '截图字体必须存在：${entry.$2}');
    final data = (await tester.runAsync(() => File(entry.$2).readAsBytes()))!;
    final loader = FontLoader(entry.$1)
      ..addFont(Future.value(ByteData.sublistView(data)));
    await tester.runAsync(loader.load);
  }
}
