// How the widgets write amounts: a percent cut, never 100 % before the
// whole, and right at the whole percents a float lands a hair short of; a
// time as a clock or as the time something took; bytes in decimal units.
import 'package:test/test.dart';
import 'package:twk/src/foundation/format.dart';

void main() {
  test('formatPercent cuts: 100% only for the whole', () {
    expect(formatPercent(0), '0%');
    expect(formatPercent(0.5), '50%');
    expect(formatPercent(0.996), '99%');
    expect(formatPercent(0.99999999), '99%');
    expect(formatPercent(1), '100%');
    expect(formatPercent(1.5), '100%');
    expect(formatPercent(-1), '0%');
    expect(formatPercent(double.nan), '0%');
    expect(formatPercent(2 / 3), '66%');
  });

  test('formatPercent reads a whole percent whole although the float of '
      'it times 100 is a hair short', () {
    // 0.29 * 100 is 28.999999999999996
    expect(formatPercent(0.29), '29%');
    expect(formatPercent(0.57), '57%');
    for (var total = 1; total <= 400; total++) {
      for (var done = 0; done <= total; done++) {
        expect(
          formatPercent(done / total),
          '${done * 100 ~/ total}%',
          reason: '$done/$total',
        );
      }
    }
  });

  test('formatClock: minutes and seconds, then hours, cut to the second', () {
    expect(formatClock(Duration.zero), '00:00');
    expect(formatClock(const Duration(milliseconds: 4999)), '00:04');
    expect(formatClock(const Duration(minutes: 12, seconds: 34)), '12:34');
    expect(formatClock(const Duration(minutes: 59, seconds: 59)), '59:59');
    expect(
      formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(formatClock(const Duration(hours: 100)), '100:00:00');
  });

  test('formatTook: to the tenth, cut, under a minute, then a clock', () {
    expect(formatTook(Duration.zero), '0.0 s');
    expect(formatTook(const Duration(milliseconds: 3190)), '3.1 s');
    expect(formatTook(const Duration(milliseconds: 59999)), '59.9 s');
    expect(formatTook(const Duration(minutes: 1, seconds: 5)), '01:05');
    expect(
      formatTook(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
  });

  test('formatBytes: decimal units, to the tenth under 100 of one, whole '
      'from there', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(999), '999 B');
    expect(formatBytes(1000), '1.0 kB');
    expect(formatBytes(4096), '4.1 kB');
    expect(formatBytes(620000), '620 kB');
    expect(formatBytes(1200000), '1.2 MB');
    expect(formatBytes(3.4e12), '3.4 TB');
    expect(formatBytes(2e18), '2000 PB');
    // a rate in bytes need not be whole
    expect(formatBytes(12.5), '12.5 B');
  });

  test('formatBytes moves to the next unit where the figures would round '
      'to 1000, and to whole figures where they would round to 100', () {
    expect(formatBytes(999.6), '1.0 kB');
    expect(formatBytes(99940), '99.9 kB');
    expect(formatBytes(99960), '100 kB');
    expect(formatBytes(999499), '999 kB');
    expect(formatBytes(999999), '1.0 MB');
    expect(byteUnit(999999), (1000000, 'MB'));
    expect(byteUnit(999), (1, 'B'));
  });
}
