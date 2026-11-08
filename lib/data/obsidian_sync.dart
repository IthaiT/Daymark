import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../domain/obsidian.dart';
import 'atomic_file.dart';
import 'store.dart';

/// Source writes only add IDs. Markdown remains the authority for imported fields.
class ObsidianSync {
  const ObsidianSync({this.writer = AtomicFile.write});
  final FileWriter writer;

  Future<int> synchronize(Store store, Directory directory) async {
    final root = Directory(await directory.resolveSymbolicLinks());
    final sources = <String, String>{};
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
        final name = entity.uri.pathSegments.last;
        sources[name] = await entity.readAsString();
      }
    }
    final aliases = <String, String>{};
    for (final item in store.items.values) {
      final source = item.source;
      if (source?.directory != root.path || source?.kind != 'task') continue;
      final block = obsidianBlockId(source!.raw);
      if (block == null) continue;
      if (aliases.containsKey(block) && aliases[block] != item.id) {
        throw FormatException('历史事项中存在重名块 ID：$block。');
      }
      aliases[block] = item.id;
    }
    final parsed = parseObsidian(
      sources,
      directory: root.path,
      knownBlockIds: aliases,
    );
    await store.importObsidian(
      parsed,
      directory: root.path,
      beforeSave: () async {
        // Check every source, including ones that need no IDs, before writing any.
        for (final entry in sources.entries) {
          await _check(File('${root.path}/${entry.key}'), entry.value);
        }
        final changed = <String, String>{
          for (final entry in sources.entries)
            if (parsed.documents[entry.key] != entry.value)
              entry.key: entry.value,
        };
        if (changed.isNotEmpty) {
          final backup = File(
            '${store.directory.path}/obsidian-originals/${const Uuid().v4()}.json',
          );
          await backup.parent.create(recursive: true);
          await AtomicFile.write(
            backup,
            utf8.encode(
              jsonEncode({
                'version': 1,
                'directory': root.path,
                'documents': changed,
              }),
            ),
          );
        }
        for (final entry in changed.entries) {
          final file = File('${root.path}/${entry.key}');
          await _check(file, entry.value);
          await writer(file, utf8.encode(parsed.documents[entry.key]!));
        }
      },
    );
    return parsed.items.length;
  }

  Future<void> _check(File file, String expected) async {
    if (!await file.exists() || await file.readAsString() != expected) {
      throw FileSystemException('同步期间 Markdown 已变化，请稍后重试。', file.path);
    }
  }
}
