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
  return block == null ? source.path : '${source.path}#$block';
}

/// Existing source paths open precisely; other links use Obsidian's vault index.
/// The URI's absolute path selects the vault and its remainder is a link path,
/// so a short wikilink need not exist directly under the vault root.
Future<Uri> resolveObsidianNoteUri(String directory, String target) async {
  final destination = target.split('|').first.trim();
  final separator = destination.indexOf('#');
  var path = separator < 0 ? destination : destination.substring(0, separator);
  final fragment = separator < 0 ? '' : destination.substring(separator);
  path = path.replaceAll('\\', '/');
  if (path.isEmpty) throw const FormatException('双链缺少文件名。');
  if (!path.toLowerCase().endsWith('.md')) path = '$path.md';
  final root = Directory(directory).absolute;
  Directory? vault;
  for (var candidate = root; ; candidate = candidate.parent) {
    if (await Directory('${candidate.path}/.obsidian').exists()) {
      vault = candidate;
      break;
    }
    if (candidate.parent.path == candidate.path) break;
  }
  final local = File('${root.path}/$path');
  final file = await local.exists()
      ? local
      : File('${(vault ?? root).path}/$path');
  if (vault == null && !await file.exists()) {
    throw FormatException('Obsidian 文件不存在：$path');
  }
  return obsidianOpenUri('${file.absolute.path}$fragment');
}

Future<void> openObsidianNote(String directory, String target) async {
  if (!await launchUrl(
    await resolveObsidianNoteUri(directory, target),
    mode: LaunchMode.externalApplication,
  )) {
    throw const FormatException('无法打开 Obsidian，请确认已安装并启动过 Obsidian。');
  }
}
