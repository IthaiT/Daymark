import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'item.dart';
import 'unicode.dart';

/// A fully validated import, before any source file is changed.
class ObsidianImport {
  const ObsidianImport(this.items, this.tagNames, this.documents);
  final Map<String, Item> items;
  final Map<String, List<String>> tagNames;
  final Map<String, String> documents;
}

final _fileId = RegExp(r'^<!-- daymark-file:([a-zA-Z0-9_-]+) -->\s*$');
final _fileBlockId = RegExp(r'^\^daymark-file-([a-zA-Z0-9-]+)\s*$');
final _blockId = RegExp(r'(?:^|\s)\^([a-zA-Z0-9-]+)\s*$');
final _taskId = RegExp(r'<!-- daymark:([a-zA-Z0-9_-]+) -->');
final _checkbox = RegExp(r'^(\s*)(?:[-+*]|\d+[.)])\s+\[(.)\]\s*(.*)$');

/// Parses only immediate Markdown children of the selected Daymark folder.
/// Native block references carry identity, independently of title and location.
ObsidianImport parseObsidian(
  Map<String, String> documents, {
  required String directory,
  String Function()? newId,
  Map<String, String> knownBlockIds = const {},
}) {
  newId ??= () => 'obsidian-${const Uuid().v4()}';
  final items = <String, Item>{};
  final tags = <String, List<String>>{};
  final updated = <String, String>{};
  final roots = <String, String>{};
  final parents = <String, String>{};
  final usedBlocks = <String>{};
  void add(Item item) {
    if (items.containsKey(item.id)) {
      throw FormatException(
        'Markdown 中存在重复事项 ID：${item.id}。请为复制的事项移除 ID 注释后重试。',
      );
    }
    items[item.id] = item;
  }

  for (final entry in documents.entries) {
    final path = entry.key;
    final text = entry.value;
    final eol = text.contains('\r\n') ? '\r\n' : '\n';
    final bom = text.startsWith('\uFEFF') ? '\uFEFF' : '';
    final lines = text.substring(bom.length).split(eol);
    var body = 0;
    Map<Object?, Object?> properties = const {};
    if (lines.first.trim() == '---') {
      final end = lines.indexWhere((line) => line.trim() == '---', 1);
      if (end < 0) throw FormatException('$path 的 YAML 属性未结束。');
      final value = loadYaml(lines.sublist(1, end).join('\n'));
      if (value != null && value is! YamlMap) {
        throw FormatException('$path 的 YAML 属性必须是映射。');
      }
      if (value is YamlMap) properties = value;
      body = end + 1;
    }
    String? rootId;
    int? legacyRootLine;
    String? rootFence;
    var rootComment = false;
    for (var index = body; index < lines.length; index++) {
      final code = RegExp(
        r'^(`{3,}|~{3,})',
      ).firstMatch(lines[index].trimLeft());
      if (code != null) {
        final marker = code[1]!;
        if (rootFence == null) {
          rootFence = marker;
        } else if (marker.startsWith(rootFence[0]) &&
            marker.length >= rootFence.length) {
          rootFence = null;
        }
        continue;
      }
      if (rootFence != null) continue;
      final trimmedRoot = lines[index].trimLeft();
      if (rootComment) {
        if (trimmedRoot.contains('-->') || trimmedRoot.contains('%%')) {
          rootComment = false;
        }
        continue;
      }
      if ((trimmedRoot.startsWith('<!--') && !trimmedRoot.contains('-->')) ||
          (trimmedRoot.startsWith('%%') &&
              !trimmedRoot.substring(2).contains('%%'))) {
        rootComment = true;
        continue;
      }
      final legacy = _fileId.firstMatch(lines[index]);
      final native = _fileBlockId.firstMatch(lines[index]);
      if (legacy == null && native == null) continue;
      if (rootId != null) throw FormatException('$path 包含多个文件 ID。');
      rootId = legacy?[1] ?? _decodeId(native![1]!);
      if (legacy != null) legacyRootLine = index;
    }
    if (rootFence != null || rootComment) {
      throw FormatException('$path 的代码块或注释未结束，请补全后同步。');
    }
    final needsRootBlock = rootId == null || legacyRootLine != null;
    rootId ??= newId();
    if (legacyRootLine != null) lines.removeAt(legacyRootLine);
    final name = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.md$', caseSensitive: false), '');
    final key = caseFold(name);
    if (roots.containsKey(key)) throw FormatException('文件名重复：$name。');
    roots[key] = rootId;
    final parent = _parent(properties['parent'], path);
    if (parent != null) parents[rootId] = parent;
    tags[rootId] = _tags(properties['tags'], path);
    final stack = <(int, String)>[];
    String? fence;
    var comment = false;
    var order = 0;
    for (var index = body; index < lines.length; index++) {
      final line = lines[index];
      final trimmed = line.trimLeft();
      final code = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed);
      if (code != null) {
        final marker = code[1]!;
        if (fence == null) {
          fence = marker;
        } else if (marker.startsWith(fence[0]) &&
            marker.length >= fence.length) {
          fence = null;
        }
        continue;
      }
      if (fence != null) continue;
      if (comment) {
        if (trimmed.contains('-->') || trimmed.contains('%%')) comment = false;
        continue;
      }
      if ((trimmed.startsWith('<!--') && !trimmed.contains('-->')) ||
          (trimmed.startsWith('%%') && !trimmed.substring(2).contains('%%'))) {
        comment = true;
        continue;
      }
      final match = _checkbox.firstMatch(line);
      if (match == null) continue;
      final status = switch (match[2]) {
        ' ' => ItemStatus.active,
        '/' => ItemStatus.paused,
        '-' => ItemStatus.dropped,
        'x' || 'X' => ItemStatus.done,
        _ => throw FormatException('$path 第 ${index + 1} 行的复选框状态不支持。'),
      };
      var indent = 0;
      for (final unit in match[1]!.codeUnits) {
        indent += unit == 9 ? 4 - indent % 4 : 1;
      }
      while (stack.isNotEmpty && stack.last.$1 >= indent) {
        stack.removeLast();
      }
      final ids = _taskId.allMatches(line).toList();
      if (ids.length > 1) {
        throw FormatException('$path 第 ${index + 1} 行包含多个 ID。');
      }
      final block = obsidianBlockId(line);
      if (block != null && !usedBlocks.add(block)) {
        throw FormatException('Markdown 中存在重复块 ID：$block。');
      }
      final legacyId = ids.isEmpty ? null : ids.single[1]!;
      final nativeId = block?.startsWith('daymark-') == true
          ? _decodeId(block!.substring('daymark-'.length))
          : null;
      if (legacyId != null && nativeId != null && legacyId != nativeId) {
        throw FormatException('$path 第 ${index + 1} 行的旧 ID 与块 ID 冲突。');
      }
      final id =
          legacyId ??
          nativeId ??
          knownBlockIds[block] ??
          (block == null ? newId() : 'obsidian-block-$block');
      var annotatedLine = line.replaceAll(_taskId, '').trimRight();
      if (block == null) annotatedLine += ' ^daymark-${_encodeId(id)}';
      lines[index] = annotatedLine;
      final (content, ownTags) = _inlineTags(match[3]!);
      tags[id] = ownTags;
      final fields = _fields(_cleanTask(content));
      if (fields.first.trim().isEmpty || fields.length > 3) {
        throw FormatException(
          '$path 第 ${index + 1} 行请使用「名称 | 描述 | 结果」，正文中的竖线请写为 \\|。',
        );
      }
      add(
        Item(
          id: id,
          name: fields[0].trim(),
          objective: fields.length > 1 ? fields[1].trim() : '',
          outcome: fields.length > 2 ? fields[2].trim() : '',
          status: status,
          parentId: stack.isEmpty ? rootId : stack.last.$2,
          source: ItemSource(
            directory: directory,
            path: path,
            kind: 'task',
            order: order++,
            raw: lines[index],
          ),
        ),
      );
      stack.add((indent, id));
    }
    if (needsRootBlock) {
      if (lines.last.isNotEmpty) lines.add('');
      lines.addAll(['^daymark-file-${_encodeId(rootId)}', '']);
    }
    final annotated = '$bom${lines.join(eol)}';
    updated[path] = annotated;
    add(
      Item(
        id: rootId,
        name: name,
        source: ItemSource(
          directory: directory,
          path: path,
          kind: 'file',
          order: 0,
          raw: annotated,
        ),
      ),
    );
  }
  for (final entry in parents.entries) {
    final parentId = roots[caseFold(entry.value)];
    if (parentId == null) throw FormatException('父事项文件不存在：${entry.value}。');
    items[entry.key] = items[entry.key]!.copyWith(parentId: parentId);
  }
  validateItems(items);
  return ObsidianImport(
    Map.unmodifiable(items),
    Map.unmodifiable(tags),
    Map.unmodifiable(updated),
  );
}

/// Existing user block IDs are preserved; the stored tree remembers their alias.
String? obsidianBlockId(String line) =>
    _blockId.firstMatch(line.replaceAll(_taskId, '').trimRight())?[1];

String _encodeId(String id) => RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)
    ? id
    : 'encoded-${utf8.encode(id).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
String _decodeId(String id) {
  if (!id.startsWith('encoded-')) return id;
  final hex = id.substring(8);
  if (hex.length.isOdd || !RegExp(r'^[0-9a-f]+$').hasMatch(hex)) {
    throw const FormatException('事项块 ID 编码不正确。');
  }
  return utf8.decode([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

String? _parent(Object? value, String path) {
  // YAML interprets unquoted [[Name]] as nested flow lists.
  if (value is List &&
      value.length == 1 &&
      value.single is List &&
      (value.single as List).length == 1) {
    value = '[[${(value.single as List).single}]]';
  }
  if (value == null || value == '') return null;
  if (value is! String) throw FormatException('$path 的 parent 必须为一个双链。');
  if (const ['最顶层事项', '最顶层', '最顶层的事项', 'root'].contains(value.trim())) {
    return null;
  }
  final match = RegExp(r'^\[\[([^\]]+)\]\]$').firstMatch(value.trim());
  if (match == null) throw FormatException('$path 的 parent 请使用 [[文件名]]。');
  return match[1]!
      .split('|')
      .first
      .split('#')
      .first
      .replaceAll('\\', '/')
      .split('/')
      .last
      .replaceFirst(RegExp(r'\.md$', caseSensitive: false), '');
}

List<String> _tags(Object? value, String path) {
  if (value == null) return const [];
  final values = value is String ? value.split(RegExp(r'[,，]')) : value;
  if (values is! List || values.any((tag) => tag is! String)) {
    throw FormatException('$path 的 tags 必须为标签名称列表。');
  }
  return [
    for (final tag in values.cast<String>())
      if (tag.trim().isNotEmpty) tag.trim().replaceFirst(RegExp(r'^#'), ''),
  ];
}

/// Obsidian tags may appear in any field; links and code are literal text.
(String, List<String>) _inlineTags(String value) {
  value = value.replaceAll(RegExp(r'<!--.*?-->|%%.*?%%'), '');
  final tag = RegExp(r'^#[\p{L}\p{M}\p{N}_/-]+', unicode: true);
  final letter = RegExp(r'[\p{L}\p{M}_-]', unicode: true);
  final names = <String>[];
  final text = StringBuffer();
  var wiki = false;
  var ticks = 0;
  for (var index = 0; index < value.length;) {
    if (value[index] == '\\' && index + 1 < value.length) {
      text.write(value.substring(index, index + 2));
      index += 2;
      continue;
    }
    if (value[index] == '`') {
      var end = index;
      while (end < value.length && value[end] == '`') {
        end++;
      }
      final count = end - index;
      if (ticks == 0) {
        ticks = count;
      } else if (ticks == count) {
        ticks = 0;
      }
      text.write(value.substring(index, end));
      index = end;
      continue;
    }
    if (ticks == 0 && value.startsWith('[[', index)) wiki = true;
    if (ticks == 0 && value.startsWith(']]', index)) wiki = false;
    if (!wiki &&
        ticks == 0 &&
        value[index] == '#' &&
        (index == 0 || RegExp(r'[\s|]').hasMatch(value[index - 1]))) {
      final match = tag.firstMatch(value.substring(index));
      if (match != null && letter.hasMatch(match[0]!)) {
        final name = match[0]!.substring(1);
        if (!names.contains(name)) names.add(name);
        text.write(' ');
        index += match[0]!.length;
        continue;
      }
    }
    text.write(value[index++]);
  }
  return (text.toString(), names);
}

String _cleanTask(String value) => value
    .replaceAll(RegExp(r'<!--.*?-->|%%.*?%%'), '')
    .replaceAll(
      RegExp(
        r'[\[(](?:due|scheduled|start|created|completion|cancelled|priority|repeat|id|dependsOn|onCompletion)::[^\])]*[\])]',
        caseSensitive: false,
      ),
      '',
    )
    .replaceAll(RegExp(r'[📅🛫⏳➕✅❌]\s*\d{4}-\d{2}-\d{2}', unicode: true), '')
    .replaceAll(RegExp(r'[🔺⏫🔼🔽⏬]\uFE0F?', unicode: true), '')
    .replaceAll(RegExp(r'🏁\s*(?:keep|delete)', unicode: true), '')
    .replaceAll(RegExp(r'[🆔⛔]\s*[\w-]+(?:\s*,\s*[\w-]+)*', unicode: true), '')
    .replaceAll(RegExp(r'🔁\s*.*$', unicode: true), '')
    .replaceAll(RegExp(r'\s+\^[\w-]+\s*$'), '')
    .trim();

/// Keep escaped pipes, wiki-link aliases and inline code inside a field.
List<String> _fields(String text) {
  final fields = <String>[];
  final field = StringBuffer();
  var wiki = 0;
  var code = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '\\' && i + 1 < text.length && text[i + 1] == '|') {
      field.write('|');
      i++;
      continue;
    }
    if (c == '`') code = !code;
    if (!code && text.startsWith('[[', i)) wiki++;
    if (!code && text.startsWith(']]', i)) wiki--;
    if (c == '|' && wiki == 0 && !code) {
      fields.add(field.toString());
      field.clear();
    } else {
      field.write(c);
    }
  }
  fields.add(field.toString());
  return fields;
}
