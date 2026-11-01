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

  test('formatBytes in binary units: 1024 to a unit, IEC suffixes, the '
      'digits as the decimal ones', () {
    String b(num n) => formatBytes(n, units: ByteUnits.binary);
    expect(b(0), '0 B');
    expect(b(1000), '1000 B');
    expect(b(1023), '1023 B');
    expect(b(1024), '1.0 KiB');
    expect(b(1536), '1.5 KiB');
    expect(b(4096), '4.0 KiB');
    expect(b(102300), '99.9 KiB');
    expect(b(102400), '100 KiB');
    expect(b(1000 * 1024), '1000 KiB');
    expect(b(1048576), '1.0 MiB');
    expect(b(1.5 * 1048576), '1.5 MiB');
    expect(b(3 * 1073741824), '3.0 GiB');
    expect(b(1024 * 1024 * 1024 * 1024), '1.0 TiB');
    expect(b(1024 * 1024 * 1024 * 1024 * 1024), '1.0 PiB');
    // a rate in bytes need not be whole
    expect(b(12.5), '12.5 B');
  });

  test('formatBytes in binary moves to the next unit where the figures '
      'would round to 1024, as the decimal does at 1000', () {
    String b(num n) => formatBytes(n, units: ByteUnits.binary);
    expect(b(1023.4), '1023 B');
    expect(b(1023.6), '1.0 KiB');
    expect(b(1048063), '1023 KiB');
    expect(b(1048064), '1.0 MiB');
    expect(byteUnit(1048064, ByteUnits.binary), (1048576, 'MiB'));
    expect(byteUnit(1023, ByteUnits.binary), (1, 'B'));
  });

  test('formatBytes is decimal when no units are given', () {
    expect(formatBytes(1024), '1.0 kB');
    expect(formatBytes(1536), '1.5 kB');
  });
}
