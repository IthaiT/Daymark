import 'package:daymark/domain/event_stats.dart';
import 'package:daymark/domain/model.dart';
import 'package:daymark/domain/item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = DateTime.utc(2026, 11, 7);
  final window = StatsWindow.days(day, day);
  Event event(
    String id,
    int from,
    int to, {
    List<String> tags = const ['work'],
    String? item,
  }) => Event(
    id,
    id,
    tags,
    day.add(Duration(minutes: from)),
    day.add(Duration(minutes: to)),
    '',
    item,
  );

  test('17:00–21:30 with a parallel half hour credits 4h15 and 15m', () {
    final discussion = event('discussion', 1020, 1290);
    final dinner = event('dinner', 1020, 1050);
    final profile = ConcurrencyProfile.of(window, [discussion, dinner]);
    expect(profile.durationOf([discussion]), const Duration(minutes: 255));
    expect(profile.durationOf([dinner]), const Duration(minutes: 15));
    expect(
      profile.durationOf([discussion, dinner]),
      const Duration(minutes: 270),
    );
  });

  test('stale gap boundaries never dilute saved events or project totals', () {
    final a = event('a', 540, 600, item: 'p');
    final b = event('b', 720, 780);
    final original = currentGaps([
      a,
      b,
    ]).single.copyWith(title: '散步', notes: '备注');
    final changed = a.copyWith(end: day.add(const Duration(minutes: 690)));
    final pool = accountingEvents([changed, b, original]);
    final gap = pool.singleWhere((e) => e.isUndefined);
    expect(gap.start, changed.end);
    expect(gap.title, '散步');
    expect(gap.notes, '备注');
    final profile = ConcurrencyProfile.of(window, pool);
    expect(profile.durationOf([changed]), const Duration(minutes: 150));
    expect(profile.durationOf(pool), const Duration(minutes: 240));
    expect(
      itemDurations(
        {'p': const Item(id: 'p', name: '项目')},
        [changed, b, original],
        splitOverlap: true,
      )['p'],
      const Duration(minutes: 150),
    );
  });

  test('duplicate event identities count once in a concurrency query', () {
    final a = event('a', 540, 600);
    final b = event('b', 540, 600);
    final profile = ConcurrencyProfile.of(window, [a, b, a]);
    expect(profile.durationOf([a, a]), const Duration(minutes: 30));
    expect(
      profile.heatOf([a, a])[day.weekday - 1][9],
      const Duration(minutes: 30),
    );
  });
}
