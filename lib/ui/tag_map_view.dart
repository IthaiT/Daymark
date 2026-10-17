import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../domain/tag_tree.dart';

/// What the web view currently has selected. The root is virtual, so it is
/// reported too but never becomes a persisted tag.
class TagMapSelection {
  const TagMapSelection({
    required this.id,
    required this.name,
    required this.isRoot,
    required this.childCount,
  });
  const TagMapSelection.none()
    : id = '',
      name = '',
      isRoot = false,
      childCount = 0;
  final String id;
  final String name;
  final bool isRoot;
  final int childCount;
  static TagMapSelection fromJson(Object? value) {
    if (value is! Map<String, Object?>) return const TagMapSelection.none();
    final id = value['id'];
    final name = value['name'];
    if (id is! String || name is! String || id.isEmpty) {
      return const TagMapSelection.none();
    }
    final childCount = value['childCount'];
    return TagMapSelection(
      id: id,
      name: name,
      isRoot: value['isRoot'] == true,
      childCount: childCount is int ? childCount : 0,
    );
  }
}

/// Hosts the bundled SimpleMindMap page inside WebView2 and exposes only the
/// small command surface the tag map needs. The page never touches files.
class TagMapView extends StatefulWidget {
  const TagMapView({
    super.key,
    required this.onReady,
    required this.onChange,
    required this.onSave,
    required this.onDelete,
    required this.onEnter,
    required this.onError,
  });
  final VoidCallback onReady;
  final void Function(
    TagTree tree,
    TagMapSelection selection,
    bool canUndo,
    bool canRedo,
  )
  onChange;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  /// Null enters the all-tags view.
  final ValueChanged<String?> onEnter;
  final ValueChanged<Object> onError;
  @override
  State<TagMapView> createState() => TagMapViewState();
}

class TagMapViewState extends State<TagMapView> {
  WebviewController? _controller;
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _pageReady = false;
  bool _loading = true;
  String? _error;
  bool _disposed = false;
  String? _rootId;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  Future<void> _start() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final version = await WebviewController.getWebViewVersion();
      if (version == null) {
        throw const FormatException(
          '未检测到 Microsoft Edge WebView2 运行时，请安装后重新打开导图。',
        );
      }
      final directory = await _assetDirectory();
      if (directory == null) {
        throw const FormatException('找不到随应用打包的导图资源。');
      }
      final controller = WebviewController();
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      _subscriptions.add(
        controller.webMessage.listen(_onMessage, onError: widget.onError),
      );
      _subscriptions.add(
        controller.onLoadError.listen(
          (status) => _fail('导图页面加载失败：${status.name}'),
        ),
      );
      await controller.addVirtualHostNameMapping(
        'daymark.assets',
        directory.path,
        WebviewHostResourceAccessKind.allow,
      );
      await controller.loadUrl('https://daymark.assets/index.html');
      if (_disposed) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      _fail(_errorText(error));
    }
  }

  Future<Directory?> _assetDirectory() async {
    final executable = File(Platform.resolvedExecutable).parent.path;
    for (final path in [
      '$executable/data/flutter_assets/assets/mindmap',
      '${Directory.current.path}/assets/mindmap',
    ]) {
      final directory = Directory(path);
      if (await File('${directory.path}/index.html').exists()) {
        return directory;
      }
    }
    return null;
  }

  String _errorText(Object error) {
    if (error is FormatException) return error.message;
    if (error is MissingPluginException) return '当前平台不支持内嵌导图。';
    return '无法打开导图：$error';
  }

  void _fail(String message) {
    if (_disposed || !mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  void _onMessage(Object? value) {
    if (value is! Map<String, Object?>) return;
    final type = value['type'];
    switch (type) {
      case 'ready':
        _pageReady = true;
        widget.onReady();
      case 'change':
        final tree = value['tree'];
        if (tree == null) return;
        try {
          final rootId = tree is Map<String, Object?> ? tree['id'] : null;
          widget.onChange(
            TagTree.fromJson(
              tree,
              expectedRootId: rootId is String ? rootId : _rootId,
            ),
            TagMapSelection.fromJson(value['selection']),
            value['canUndo'] == true,
            value['canRedo'] == true,
          );
        } catch (error) {
          widget.onError(error);
        }
      case 'save':
        widget.onSave();
      case 'delete':
        widget.onDelete();
      case 'enter':
        final id = value['id'];
        if (id is String) widget.onEnter(id.isEmpty ? null : id);
      case 'error':
        final message = value['message'];
        widget.onError(
          FormatException(message is String ? message : '导图脚本发生错误。'),
        );
    }
  }

  Future<void> _run(String script) async {
    final controller = _controller;
    if (controller == null || !_pageReady) return;
    try {
      await controller.executeScript(script);
    } catch (error) {
      widget.onError(error);
    }
  }

  Future<void> load(
    TagTree tree,
    Map<String, Object?> colors, {
    bool fit = false,
  }) {
    _rootId = tree.root.id;
    return _run(
      'window.Daymark.load(${jsonEncode({'tree': tree.toJson(), 'colors': colors, 'fit': fit})})',
    );
  }

  Future<void> applyColors(Map<String, Object?> colors) =>
      _run('window.Daymark.setColors(${jsonEncode(colors)})');

  Future<void> applyAssignedIds(Map<String, String> ids) =>
      _run('window.Daymark.setAssignedIds(${jsonEncode(ids)})');

  Future<void> addChild(String parentId, String name) => _run(
    'window.Daymark.addChild(${jsonEncode(parentId)}, ${jsonEncode(name)})',
  );

  Future<void> beginEdit(String id) =>
      _run('window.Daymark.beginEdit(${jsonEncode(id)})');

  Future<void> endEdit() => _run('window.Daymark.endEdit()');

  Future<void> remove(String id) =>
      _run('window.Daymark.remove(${jsonEncode(id)})');

  Future<void> undo() => _run('window.Daymark.undo()');
  Future<void> redo() => _run('window.Daymark.redo()');
  Future<void> zoomIn() => _run('window.Daymark.zoomIn()');
  Future<void> zoomOut() => _run('window.Daymark.zoomOut()');
  Future<void> fit() => _run('window.Daymark.fit()');

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final error = _error;
    if (error != null) {
      return _status(
        icon: Icons.error_outline,
        title: '导图无法显示',
        detail: error,
        action: TextButton.icon(
          onPressed: _restart,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      );
    }
    if (controller == null) {
      return _status(
        icon: Icons.account_tree_outlined,
        title: '正在加载导图…',
        detail: '首次打开需要启动本地 WebView。',
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => controller.value.isInitialized
          ? Webview(controller)
          : _status(
              icon: Icons.account_tree_outlined,
              title: '正在加载导图…',
              detail: null,
            ),
    );
  }

  void _restart() {
    final controller = _controller;
    _controller = null;
    _pageReady = false;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    if (controller != null) unawaited(controller.dispose());
    unawaited(_start());
  }

  Widget _status({
    required IconData icon,
    required String title,
    required String? detail,
    Widget? action,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading && detail != null)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Icon(
                icon,
                size: 30,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (detail != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    ),
  );
}
