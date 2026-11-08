import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../domain/item.dart';
import '../domain/obsidian.dart';

/// The official URI accepts an absolute path, including an optional heading.
Uri obsidianOpenUri(String path) => Uri(
  scheme: 'obsidian',
  host: 'open',
  query: 'path=${Uri.encodeComponent(path)}',
);

String obsidianItemTarget(Item item) {
  final source = item.source!;
  final block = source.kind == 'task' ? obsidianBlockId(source.raw) : null;
  return block == null ? source.path : '${source.path}#^$block';
}

Future<void> openObsidianNote(String directory, String target) async {
  final destination = target.split('|').first.trim();
  final separator = destination.indexOf('#');
  var path = separator < 0 ? destination : destination.substring(0, separator);
  final fragment = separator < 0 ? '' : destination.substring(separator);
  path = path.replaceAll('\\', '/');
  if (path.isEmpty) throw const FormatException('双链缺少文件名。');
  if (!path.toLowerCase().endsWith('.md')) path = '$path.md';
  var root = Directory(directory).absolute;
  var vault = root;
  while (!await Directory('${vault.path}/.obsidian').exists()) {
    if (vault.parent.path == vault.path) {
      vault = root;
      break;
    }
    vault = vault.parent;
  }
  final local = File('${root.path}/$path');
  final file = await local.exists() ? local : File('${vault.path}/$path');
  if (!await file.exists()) throw FormatException('Obsidian 文件不存在：$path');
  if (!await launchUrl(
    obsidianOpenUri('${file.absolute.path}$fragment'),
    mode: LaunchMode.externalApplication,
  )) {
    throw const FormatException('无法打开 Obsidian，请确认已安装并启动过 Obsidian。');
  }
}
