import 'package:daymark/domain/appearance.dart';
import 'package:daymark/domain/journal_presentation.dart';
import 'package:daymark/domain/journal_view_preferences.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/timeline_axis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 10, 25);
  DateTime at(int minute) => day.add(Duration(minutes: minute));
  Event event(String id, int start, int? end, {String? tag, String? title}) =>
      Event(id, title ?? id, tag, at(start), end == null ? null : at(end));
  const presentation = JournalPresentation(
    tags: {'life': Tag('life', '生活', null)},
    tagDisplays: {'life': TagDisplay.routine},
    view: JournalViewPreferences(showUnclassified: false),
  );

  test('all-hidden days retain records while the empty axis stays usable', () {
    final records = [
      event('sleep', 0, 600, tag: 'life'),
      event('unclassified', 600, 660),
      event('incomplete', 700, null),
    ];
    final axis = TimelineAxis(
      day: day,
      width: 900,
      events: records.where(presentation.includes),
      foldEmptyTime: true,
    );
    expect(axis.isFolded, isFalse);
    expect(presentation.hiddenEvents(records, day), records);
    expect(presentation.hiddenEvents([], day), isEmpty);
  });

  test(
    'four merged intervals retain seven hidden records including overlaps',
    () {
      final visible = [
        event('chore', 630, 730, tag: 'project'),
        event('career', 810, 990, tag: 'project'),
        event('daymark', 1185, 1260, tag: 'project'),
        event('run', 1260, 1310, tag: 'project'),
        event('daymark2', 1310, 1350, tag: 'project'),
      ];
      final hidden = [
        event('sleep', 0, 630, tag: 'life'),
        event('cook', 730, 760),
        event('lunch', 760, 810),
        event('cook2', 990, 1080),
        event('dinner', 1080, 1185),
        event('late', 1350, 1440),
        event('parallel', 690, 710),
      ];
      final all = [...visible, ...hidden];
      final axis = TimelineAxis(
        day: day,
        width: 900,
        events: all.where(presentation.includes),
        foldEmptyTime: true,
      );
      expect(axis.folds.length, 4);
      final result = presentation.hiddenEvents(all, day);
      expect(
        result.map((item) => item.id).toSet(),
        hidden.map((item) => item.id).toSet(),
      );
      expect(result.length, 7);
      expect(
        presentation
            .hiddenEvents(all, day, within: Interval(at(990), at(1185)))
            .map((item) => item.id),
        ['cook2', 'dinner'],
      );
    },
  );

  test('distinct names and cross-midnight rows keep their full timestamps', () {
    final overnight = event('overnight', -30, 30, title: '睡觉');
    final sameName = event('later', 1380, 1500, title: '睡觉');
    final records = [sameName, overnight, event('tomorrow', 1500, 1600)];
    final result = presentation.hiddenEvents(records, day);
    expect(result, [overnight, sameName]);
    expect(result.first.start, at(-30));
    expect(result.last.end, at(1500));
    expect(result.first.intervalOn(day)!.duration, const Duration(minutes: 30));
  });

  test(
    'recording policy, temporary reveals and incomplete rows stay distinct',
    () {
      final gap = event('undefined:gap', 60, 120, title: '已填写空档');
      final incomplete = event('incomplete', 100, null);
      const disabled = JournalPresentation(
        tags: {},
        view: JournalViewPreferences(showUnclassified: false),
        autoUndefined: false,
        revealedIds: {'revealed'},
      );
      final records = [
        gap,
        incomplete,
        event('revealed', 0, 60),
        event('yesterday', -60, null),
        event('tomorrow', 1500, null),
      ];
      expect(disabled.hiddenEvents(records, day), [incomplete]);
      expect(
        disabled.hiddenEvents(records, day, within: Interval(at(90), at(110))),
        [incomplete],
      );
      expect(
        disabled.hiddenEvents(records, day, within: Interval(at(110), at(130))),
        isEmpty,
      );
      final full = JournalPresentation(
        tags: const {},
        view: JournalViewPreferences.fullDay.copyWith(showUnclassified: false),
      );
      expect(full.foldsEmptyTime, isFalse);
      expect(full.hiddenEvents([gap], day), [gap]);
    },
  );
}
