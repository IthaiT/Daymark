import 'dart:convert';
import 'dart:io';

import '../domain/item.dart';
import '../domain/model.dart';
import 'atomic_file.dart';

/// Complete, independently readable tree and record snapshots.
class TreeBackupStore {
  TreeBackupStore(this.directory, {this.writer = AtomicFile.write});
  final Directory directory;
  final Future<void> Function(File, List<int>) writer;
  Directory get root => Directory('${directory.path}/tree-backups');
  File get latest => File('${root.path}/latest.json');
  File get yesterday => File('${root.path}/yesterday.json');

  Future<void> capture({
    required Map<String, Item> items,
    required Map<String, Tag> tags,
    required Map<String, Event> events,
    required DateTime now,
  }) async {
    await root.create(recursive: true);
    final day = dayStart(now);
    if (await latest.exists()) {
      final previousBytes = await latest.readAsBytes();
      final value = jsonDecode(utf8.decode(previousBytes));
      if (value is! Map<String, Object?> ||
          value['version'] != 1 ||
          value['date'] is! String ||
          value['items'] is! List ||
          value['tags'] is! List ||
          value['events'] is! List) {
        throw const FormatException('事项树备份损坏，原文件已保留。');
      }
      final previousDay = parseDate(value['date']! as String);
      if (previousDay.isBefore(day)) await writer(yesterday, previousBytes);
    }
    final bytes = utf8.encode(
      '${const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'date': dateText(day),
        'captured_at': timestampText(civilTime(now)),
        'items': [for (final item in items.values) item.toJson()],
        'tags': [for (final tag in tags.values) tag.toJson()],
        'events': [
          for (final event in events.values) {'id': event.id, 'title': event.title, 'tag_ids': event.tagIds, 'item_id': event.itemId, 'start': timestampText(event.start), 'end': event.end == null ? null : timestampText(event.end!), 'notes': event.notes},
        ],
      })}\n',
    );
    if (day.day == 1) {
      final monthly = File('${root.path}/monthly/${dateText(day)}.json');
      await monthly.parent.create(recursive: true);
      if (!await monthly.exists()) await writer(monthly, bytes);
    }
    await writer(latest, bytes);
  }
}
