import 'package:daymark/domain/event_clipboard.dart';
import 'package:daymark/domain/model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 10, 7);
  test(
    'clipboard preserves calendar fields, seconds, notes and unfinished drafts',
    () {
      final events = [
        Event(
          'original',
          '夜间',
          'work',
          DateTime(2026, 10, 7, 23, 45, 35, 123, 456),
          DateTime(2026, 10, 8, 2, 15, 35, 123, 456),
          '中文备注\n第二行',
        ),
        Event('old', '旧记录', null, day, null),
        Event('draft', '', null, day, day.add(const Duration(hours: 1))),
      ];
      final clipboard = EventClipboard(day, events);
      final decoded = EventClipboard.tryDecode(clipboard.encode())!;
      expect(decoded.day, day);
      for (var i = 0; i < events.length; i++) {
        expect(
          decoded.events[i],
          Event(
            i.toString(),
            events[i].title,
            events[i].tagId,
            civilTime(events[i].start),
            events[i].end == null ? null : civilTime(events[i].end!),
            events[i].notes,
          ),
        );
      }
      expect(clipboard.encode(), isNot(contains('original')));
      events.clear();
      expect(clipboard.events.length, 3);
    },
  );

  test('clipboard ignores ordinary text and rejects damaged event data', () {
    for (final text in [null, '', '普通文字', '{"events":[]}']) {
      expect(EventClipboard.tryDecode(text), isNull);
    }
    for (final payload in [
      'broken',
      '{}',
      '{"day":"2026-10-07","events":[{}]}',
      '{"day":"2026-10-07","events":[{"title":"事件","tag_id":2,"start":"2026-10-07T09:00:00","end":null,"notes":""}]}',
      '{"day":"2026-02-30","events":[]}',
      '{"day":"2026-10-07","events":[{"title":"事件","start":"2026-10-07T09:00:00","end":"2026-10-07T08:00:00","notes":""}]}',
    ]) {
      expect(
        () => EventClipboard.tryDecode('Daymark events 1\n$payload'),
        throwsFormatException,
      );
    }
  });
}
