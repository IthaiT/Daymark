import 'package:daymark/domain/appearance.dart';
import 'package:daymark/domain/journal_presentation.dart';
import 'package:daymark/domain/journal_view_preferences.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/timeline_axis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 10, 24);
  DateTime at(int minute, [int second = 0]) =>
      day.add(Duration(minutes: minute, seconds: second));
  Event event(String id, int start, int end, {String? tag}) =>
      Event(id, id, tag, at(start), at(end));

  test(
    'folded time recovers space while retaining durations and inverse mapping',
    () {
      final events = [event('a', 600, 630), event('b', 900, 960)];
      final axis = TimelineAxis(
        day: day,
        width: 900,
        events: events,
        foldEmptyTime: true,
      );
      expect(axis.folds.length, 3);
      expect(axis.visibleDuration, const Duration(minutes: 90));
      expect(
        axis.foldedDuration + axis.visibleDuration,
        const Duration(days: 1),
      );
      expect(
        axis.x(at(960)) - axis.x(at(900)),
        closeTo(2 * (axis.x(at(630)) - axis.x(at(600))), .001),
      );
      expect(axis.x(at(960)) - axis.x(at(600)), greaterThan(800));
      for (final item in events) {
        for (
          var second = 0;
          second <= item.end!.difference(item.start).inSeconds;
          second += 37
        ) {
          final time = item.start.add(Duration(seconds: second));
          expect(axis.timeAt(axis.x(time), snapFold: false), time);
        }
      }
      final gap = axis.folds.elementAt(1);
      expect(axis.timeAt(gap.left + gap.width * .25), at(630));
      expect(axis.timeAt(gap.left + gap.width * .75), at(900));
    },
  );

  test(
    'visible overlaps, cross-midnight clips and legacy seconds never fold',
    () {
      final events = [
        event('overnight', -60, 90),
        event('a', 60, 120),
        Event('seconds', '秒', null, at(120), at(150, 37)),
        event('next-day', 1400, 1500),
      ];
      final axis = TimelineAxis(
        day: day,
        width: 700,
        events: events,
        foldEmptyTime: true,
      );
      expect(axis.visibleDuration, const Duration(minutes: 190, seconds: 37));
      expect(axis.folds.length, 1);
      expect(axis.folds.single.start, at(150, 37));
      expect(axis.folds.single.end, at(1400));
      for (final minute in [0, 60, 90, 120, 1400, 1440]) {
        expect(axis.timeAt(axis.x(at(minute)), snapFold: false), at(minute));
      }
      expect(axis.x(at(-60)), 0);
      expect(axis.x(at(1500)), 700);
    },
  );

  test(
    'many cuts stay within a bounded budget and empty days remain usable',
    () {
      final events = [for (var m = 1; m < 1440; m += 10) event('$m', m, m + 1)];
      final axis = TimelineAxis(
        day: day,
        width: 320,
        events: events,
        foldEmptyTime: true,
      );
      expect(
        axis.folds.fold(0.0, (sum, fold) => sum + fold.width),
        closeTo(64, .001),
      );
      expect(axis.spans.last.right, closeTo(320, .001));
      final empty = TimelineAxis(
        day: day,
        width: 320,
        events: [],
        foldEmptyTime: true,
      );
      expect(empty.isFolded, isFalse);
      expect(empty.timeAt(160), at(720));
      final full = TimelineAxis(day: day, width: 1440, events: events);
      expect(full.isFolded, isFalse);
      expect(full.x(at(600)), 600);
    },
  );

  test(
    'filter distinguishes real unclassified and user-filled derived records',
    () {
      const tags = {
        'life': Tag('life', '生活', null),
        'sleep': Tag('sleep', '睡觉', 'life'),
        'work': Tag('work', '工作', null),
      };
      const presentation = JournalPresentation(
        tags: tags,
        tagDisplays: {'life': TagDisplay.routine},
      );
      expect(presentation.includes(event('real', 0, 60)), isTrue);
      expect(
        presentation.includes(event('sleep', 0, 60, tag: 'sleep')),
        isFalse,
      );
      final gap = Event('undefined:gap', '未定义', null, at(60), at(120));
      expect(presentation.includes(gap), isFalse);
      expect(presentation.includes(gap.copyWith(title: '买菜')), isTrue);
      expect(presentation.includes(gap.copyWith(notes: '已经填写')), isTrue);
      expect(
        const JournalPresentation(
          tags: tags,
          autoUndefined: false,
        ).includes(gap.copyWith(title: '买菜')),
        isFalse,
      );
      expect(
        const JournalPresentation(
          tags: tags,
          view: JournalViewPreferences.fullDay,
        ).includes(gap),
        isTrue,
      );
      expect(
        effectiveTagDisplay(tags, 'sleep', {
          'life': TagDisplay.routine,
          'sleep': TagDisplay.normal,
        }),
        TagDisplay.normal,
      );
      final selected = JournalPresentation(
        tags: tags,
        tagDisplays: const {'life': TagDisplay.routine},
        revealedIds: {'sleep'},
      );
      expect(selected.includes(event('sleep', 0, 60, tag: 'sleep')), isTrue);
    },
  );

  test('unclassified visibility covers ordinary, renamed and noted gaps', () {
    final ordinary = event('ordinary', 0, 60);
    final gap = Event('undefined:gap', '未定义', null, at(60), at(120));
    final records = [
      ordinary,
      gap,
      gap.copyWith(title: '买菜'),
      gap.copyWith(notes: '已填写备注'),
    ];
    for (final preset in JournalViewPreset.values) {
      final hidden = JournalPresentation(
        tags: const {},
        view: JournalViewPreferences(preset: preset, showUnclassified: false),
      );
      for (final record in records) {
        expect(
          hidden.includes(record),
          isFalse,
          reason: '${preset.name}: ${record.title}',
        );
      }
      expect(hidden.includes(event('tagged', 0, 60, tag: 'work')), isTrue);
      final revealed = JournalPresentation(
        tags: const {},
        view: hidden.view,
        revealedIds: {ordinary.id, gap.id},
      );
      expect(revealed.includes(ordinary), isTrue);
      expect(revealed.includes(gap.copyWith(title: '正在编辑')), isTrue);
      final disabled = JournalPresentation(
        tags: const {},
        view: hidden.view,
        autoUndefined: false,
        revealedIds: {gap.id},
      );
      expect(disabled.includes(gap), isFalse);
    }
  });
}
