import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'application/journal_controller.dart';
import 'data/instance_lock.dart';
import 'data/store.dart';
import 'ui/journal_screen.dart';
import 'ui/theme.dart';

Directory dataDirectory(List<String> arguments, {String? executable}) {
  if (arguments.length == 2 &&
      arguments.first == '--data-dir' &&
      arguments.last.trim().isNotEmpty) {
    return Directory(arguments.last).absolute;
  }
  if (arguments.length == 1 &&
      arguments.first.startsWith('--data-dir=') &&
      arguments.first.substring(11).trim().isNotEmpty) {
    return Directory(arguments.first.substring(11)).absolute;
  }
  if (arguments.isNotEmpty) {
    throw const FormatException('参数格式不正确，请使用 --data-dir 数据目录。');
  }
  // Development and repository launchers retain the original data location.
  final executableDirectory = File(
    executable ?? Platform.resolvedExecutable,
  ).absolute.parent;
  var directory = executableDirectory;
  while (true) {
    final manifest = File('${directory.path}/pubspec.yaml');
    if (manifest.existsSync()) {
      if (Directory('${directory.path}/lib').existsSync() &&
          RegExp(
            r'^name:\s*daymark\s*$',
            multiLine: true,
          ).hasMatch(manifest.readAsStringSync())) {
        return Directory('${directory.path}/data');
      }
      // An unrelated nested project is a boundary, not a Daymark checkout.
      break;
    }
    if (directory.parent.path == directory.path) break;
    directory = directory.parent;
  }
  return Directory('${executableDirectory.path}/journal');
}

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  InstanceLock? lock;
  try {
    final directory = dataDirectory(arguments);
    lock = InstanceLock.acquire(directory);
    final store = await Store.open(directory);
    final journal = JournalController(store);
    await journal.initialize();
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Daymark',
        size: Size(1360, 900),
        minimumSize: Size(1100, 740),
        center: true,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
    runApp(DaymarkApp(journal: journal, instanceLock: lock));
    // The OS releases the byte lock on exit, including abnormal termination.
  } catch (error) {
    lock?.close();
    stderr.writeln('Daymark：$error');
    runApp(
      MaterialApp(
        theme: daymarkTheme(),
        home: Scaffold(
          body: Center(
            child: AlertDialog(
              title: const Text('Daymark 无法启动'),
              content: Text('$error\n\n原始数据文件已保留。'),
              actions: [
                TextButton(onPressed: () => exit(1), child: const Text('关闭')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DaymarkApp extends StatefulWidget {
  const DaymarkApp({super.key, required this.journal, this.instanceLock});
  final JournalController journal;
  // Keep the native handle reachable for the entire application's lifetime.
  final InstanceLock? instanceLock;

  @override
  State<DaymarkApp> createState() => _DaymarkAppState();
}

class _DaymarkAppState extends State<DaymarkApp> {
  @override
  void dispose() {
    widget.instanceLock?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Daymark',
    debugShowCheckedModeBanner: false,
    theme: daymarkTheme(),
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('zh', 'CN')],
    home: JournalScreen(journal: widget.journal),
  );
}
