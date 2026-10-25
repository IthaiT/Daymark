import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'application/journal_controller.dart';
import 'application/ledger_controller.dart';
import 'application/appearance_controller.dart';
import 'application/settings_controller.dart';
import 'data/appearance_store.dart';
import 'data/archive_store.dart';
import 'domain/appearance.dart';
import 'domain/journal_view_preferences.dart';
import 'data/instance_lock.dart';
import 'data/ledger_store.dart';
import 'data/settings_store.dart';
import 'data/store.dart';
import 'ui/app_screen.dart';
import 'ui/journal_screen.dart';
import 'ui/startup_window.dart';
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
    await windowManager.ensureInitialized();
    final display = await screenRetriever.getPrimaryDisplay();
    // ScreenRetriever already accounts for DPI and the taskbar.
    final geometry = startupWindowGeometry(
      (display.visiblePosition ?? Offset.zero) &
          (display.visibleSize ?? display.size),
    );
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        title: 'Daymark',
        minimumSize: geometry.minimumSize,
        titleBarStyle: TitleBarStyle.hidden,
      ),
    );
    await windowManager.setBounds(geometry.bounds);
    final directory = dataDirectory(arguments);
    lock = InstanceLock.acquire(directory);
    final ledgerStore = await LedgerStore.open(directory);
    final store = await Store.open(directory);
    final settingsStore = await SettingsStore.open(directory);
    final archive = await ArchiveStore.open(directory);
    final journal = JournalController(
      store,
      archive: archive,
      settings: settingsStore.state,
    );
    await journal.initialize();
    final appearanceStore = await AppearanceStore.open(directory);
    await windowManager.setPreventClose(true);
    runApp(
      DaymarkApp(
        journal: journal,
        ledger: LedgerController(ledgerStore),
        instanceLock: lock,
        appearance: AppearanceController(appearanceStore),
        settings: SettingsController(settingsStore),
      ),
    );
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
  await windowManager.show();
  await windowManager.focus();
}

class DaymarkApp extends StatefulWidget {
  const DaymarkApp({
    super.key,
    required this.journal,
    this.ledger,
    this.instanceLock,
    this.appearance,
    this.settings,
  });
  final JournalController journal;
  final LedgerController? ledger;
  // Keep the native handle reachable for the entire application's lifetime.
  final InstanceLock? instanceLock;
  final AppearanceController? appearance;
  final SettingsController? settings;

  @override
  State<DaymarkApp> createState() => _DaymarkAppState();
}

class _DaymarkAppState extends State<DaymarkApp> with WindowListener {
  late AppearanceController _appearance;
  late bool _ownsAppearance;
  late SettingsController _settings;
  late bool _ownsSettings;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  Set<String>? _colorRootIds;
  final _app = GlobalKey<AppScreenState>();
  final _journal = GlobalKey<JournalScreenState>();
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _ownsAppearance = widget.appearance == null;
    _appearance = widget.appearance ?? AppearanceController();
    _ownsSettings = widget.settings == null;
    _settings = widget.settings ?? SettingsController();
    widget.journal.addListener(_syncRootColors);
    _syncRootColors();
    if (_appearance.store?.readError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _messenger.currentState?.showSnackBar(
          const SnackBar(content: Text('配色设置无法读取，已使用默认配色。')),
        );
      });
    }
    if (_settings.store?.readError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _messenger.currentState?.showSnackBar(
          const SnackBar(content: Text('记录设置无法读取，已使用默认设置。')),
        );
      });
    }
  }

  Future<void> _initializeRootColors() async {
    try {
      await _appearance.ensureRootColors(widget.journal.store.tags.values);
    } catch (error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showAppearanceError('无法保存标签配色：$error');
      });
    }
  }

  void _syncRootColors() {
    final roots = widget.journal.store.tags.values
        .where((tag) => tag.parentId == null)
        .map((tag) => tag.id)
        .toSet();
    final previous = _colorRootIds;
    if (previous != null &&
        previous.length == roots.length &&
        previous.containsAll(roots)) {
      return;
    }
    // Selection and event edits must not repeatedly retry a failed migration.
    _colorRootIds = roots;
    unawaited(_initializeRootColors());
  }

  void _showAppearanceError(String message) {
    final messenger = _messenger.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void didUpdateWidget(covariant DaymarkApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.journal != oldWidget.journal) {
      oldWidget.journal.removeListener(_syncRootColors);
      widget.journal.addListener(_syncRootColors);
    }
    if (widget.appearance != oldWidget.appearance) {
      if (_ownsAppearance) _appearance.dispose();
      _ownsAppearance = widget.appearance == null;
      _appearance = widget.appearance ?? AppearanceController();
    }
    if (widget.settings != oldWidget.settings) {
      if (_ownsSettings) _settings.dispose();
      _ownsSettings = widget.settings == null;
      _settings = widget.settings ?? SettingsController();
    }
    if (widget.journal != oldWidget.journal ||
        widget.appearance != oldWidget.appearance) {
      _colorRootIds = null;
      _syncRootColors();
    }
  }

  Future<void> _setPalette(AppPalette palette) async {
    try {
      await _appearance.setPalette(palette);
    } catch (error) {
      if (!mounted) return;
      _showAppearanceError('无法保存配色设置：$error');
    }
  }

  /// Errors surface in the tag editor, which keeps the user's input.
  Future<void> _setTagColor(String id, TagColor? color) =>
      _appearance.setTagColor(id, color);

  Future<void> _setTagStyle(String id, TagColor? color, TagDisplay? display) =>
      _appearance.setTagStyle(id, color, display);

  Future<void> _setJournalView(JournalViewPreferences value) =>
      _appearance.setJournalView(value);

  @override
  void onWindowClose() => unawaited(_close());

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final committed =
          await (_app.currentState?.commit() ??
              _journal.currentState?.commit() ??
              Future.value(true));
      if (!committed) return;
      await widget.ledger?.waitForWrites();
      await widget.journal.archiveForClose();
      await windowManager.destroy();
    } catch (error) {
      _messenger.currentState?.showSnackBar(
        SnackBar(content: Text('无法完成归档，窗口尚未关闭：$error')),
      );
    } finally {
      _closing = false;
    }
  }

  @override
  void dispose() {
    widget.journal.removeListener(_syncRootColors);
    windowManager.removeListener(this);
    if (_ownsAppearance) _appearance.dispose();
    if (_ownsSettings) _settings.dispose();
    widget.instanceLock?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _appearance,
    builder: (context, _) => MaterialApp(
      title: 'Daymark',
      debugShowCheckedModeBanner: false,
      theme: daymarkTheme(
        palette: _appearance.state.palette,
        tagColors: _appearance.state.tagColors,
        tagDisplays: _appearance.state.tagDisplays,
      ),
      scaffoldMessengerKey: _messenger,
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('zh', 'CN')],
      home: widget.ledger == null
          ? JournalScreen(
              key: _journal,
              journal: widget.journal,
              tagColors: _appearance.state.tagColors,
              onTagColorChanged: _appearance.busy ? null : _setTagColor,
              onTagStyleChanged: _appearance.busy ? null : _setTagStyle,
              journalView: _appearance.state.journalView,
              onJournalViewChanged: _setJournalView,
            )
          : AppScreen(
              key: _app,
              journal: widget.journal,
              ledger: widget.ledger!,
              settings: _settings,
              palette: _appearance.state.palette,
              onPaletteChanged: _appearance.busy ? null : _setPalette,
              tagColors: _appearance.state.tagColors,
              onTagColorChanged: _appearance.busy ? null : _setTagColor,
              onTagStyleChanged: _appearance.busy ? null : _setTagStyle,
              journalView: _appearance.state.journalView,
              onJournalViewChanged: _setJournalView,
            ),
    ),
  );
}
