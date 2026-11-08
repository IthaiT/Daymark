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

final _itemId = RegExp(
  r'^\^daymark-obsidian-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _blockId = RegExp(r'(?:^|\s)(\^[a-zA-Z0-9_.:-]+)\s*$');
final _multipleBlocks = RegExp(r'(?:\s+\^[a-zA-Z0-9_.:-]+){2,}\s*$');
final _unsupportedIdentity = RegExp(
  r'<!--\s*daymark(?:-file)?\s*:|\^daymark-file-',
);
final _checkbox = RegExp(r'^(\s*)(?:[-+*]|\d+[.)])\s+\[(.)\]\s*(.*)$');

/// Parses only immediate Markdown children of the selected Daymark folder.
/// Note properties and task block references keep identity across moves.
ObsidianImport parseObsidian(
  Map<String, String> documents, {
  required String directory,
  String Function()? newId,
}) {
  newId ??= () => '^daymark-obsidian-${const Uuid().v4()}';
  final items = <String, Item>{};
  final tags = <String, List<String>>{};
  final updated = <String, String>{};
  final roots = <String, String>{};
  final parents = <String, String>{};
  void add(Item item) {
    if (items.containsKey(item.id)) {
      throw FormatException(
        'Markdown 中存在重复事项 ID：${item.id}。请检查 daymark-id 属性和事项块 ID。',
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
    YamlMap? properties;
    if (lines.first.trim() == '---') {
      final end = lines.indexWhere((line) => line.trim() == '---', 1);
      if (end < 0) throw FormatException('$path 的 YAML 属性未结束。');
      final value = loadYaml(lines.sublist(1, end).join(eol));
      if (value != null && value is! YamlMap) {
        throw FormatException('$path 的 YAML 属性必须是映射。');
      }
      if (value is YamlMap) properties = value;
      body = end + 1;
    }
    final propertyId = _noteId(properties?['daymark-id'], path);
    final rootId = propertyId ?? _requireId(newId(), path);
    final name = path
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.md$', caseSensitive: false), '');
    final key = caseFold(name);
    if (roots.containsKey(key)) throw FormatException('文件名重复：$name。');
    roots[key] = rootId;
    final parent = _parent(properties?['parent'], path);
    if (parent != null) parents[rootId] = parent;
    tags[rootId] = _tags(properties?['tags'], path);
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
      if (_unsupportedIdentity.hasMatch(line)) {
        throw FormatException(
          '$path 第 ${index + 1} 行的旧身份标识不受支持，请使用完整的 ^daymark-obsidian-UUID。',
        );
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
      if (_multipleBlocks.hasMatch(line)) {
        throw FormatException('$path 第 ${index + 1} 行包含多个块 ID。');
      }
      final block = _blockId.firstMatch(line)?[1];
      final id = _requireId(block ?? newId(), '$path 第 ${index + 1} 行');
      final annotatedLine = block == null ? '${line.trimRight()} $id' : line;
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
    if (fence != null || comment) {
      throw FormatException('$path 的代码块或注释未结束，请补全后同步。');
    }
    if (propertyId == null) {
      if (body == 0) {
        lines.insertAll(0, ['---', 'daymark-id: ${jsonEncode(rootId)}', '---']);
      } else {
        final yaml = lines.sublist(1, body - 1).join(eol);
        final updatedYaml = _withNoteId(yaml, properties, rootId, eol);
        lines.replaceRange(1, body - 1, updatedYaml.split(eol));
      }
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

String? _noteId(Object? value, String path) {
  if (value == null || (value is String && value.trim().isEmpty)) return null;
  if (value is! String) {
    throw FormatException(
      '$path 的 daymark-id 必须是完整的 ^daymark-obsidian-UUID 文本。',
    );
  }
  return _requireId(value, '$path 的 daymark-id');
}

/// Both Markdown locations and persisted imported nodes use this exact value.
bool isObsidianId(String value) => _itemId.hasMatch(value);

String _requireId(String value, String location) {
  if (!isObsidianId(value)) {
    throw FormatException(
      '$location 的事项 ID 必须使用完整的 ^daymark-obsidian-UUID 格式。',
    );
  }
  return value;
}

/// Change only the identity property, preserving unrelated YAML and comments.
String _withNoteId(String yaml, YamlMap? properties, String id, String eol) {
  final encoded = jsonEncode(id);
  final node = properties?.nodes['daymark-id'];
  String updated;
  if (node != null) {
    // An implicit YAML null has a zero-length span at the mapping colon.
    var start = node.span.start.offset;
    var end = node.span.end.offset;
    if (start == end && start < yaml.length && yaml[start] == ':') {
      start++;
      end++;
    }
    updated = yaml.replaceRange(start, end, ' $encoded');
  } else if (properties?.style == CollectionStyle.FLOW) {
    final start = properties!.span.start.offset;
    final insert = yaml.indexOf('{', start) + 1;
    final suffix = properties.isEmpty ? '' : ', ';
    updated = yaml.replaceRange(insert, insert, 'daymark-id: $encoded$suffix');
  } else {
    final column = properties == null || properties.isEmpty
        ? 0
        : (properties.nodes.keys.first as YamlNode).span.start.column;
    final indent = ' ' * column;
    updated = '$yaml$eol${indent}daymark-id: $encoded';
  }
  final checked = loadYaml(updated);
  if (checked is! YamlMap || checked['daymark-id'] != id) {
    throw const FormatException('无法安全写入 daymark-id 属性，请检查 YAML 格式。');
  }
  return updated;
}

/// Returns the complete canonical block ID, including its caret.
String? obsidianBlockId(String line) {
  final block = _blockId.firstMatch(line)?[1];
  return block != null && isObsidianId(block) ? block : null;
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
