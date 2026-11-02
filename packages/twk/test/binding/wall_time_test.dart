// The app's wall time (AppBinding.now): the start time the test fixes,
// moved on by the app's clock as the test moves it; the system's time
// where none is fixed, whatever the app's clock does (a sleep stops it);
// what a Calendar and a DatePicker take for today when they are given
// none.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('now is the start time, moved on by the fake clock', (t) async {
    await t.pumpWidget(
      const Text('x'),
      startTime: DateTime(2026, 10, 31, 23, 59, 59),
    );
    final start = t.clock.elapsed;
    expect(t.binding.now(), DateTime(2026, 10, 31, 23, 59, 59).add(start));
    await t.pump(const Duration(seconds: 2));
    expect(t.binding.now(), DateTime(2026, 11, 1, 0, 0, 1).add(start));
  });

  testTwk('a test that fixes no start time starts at the same one every '
      'run', (t) async {
    await t.pumpWidget(const Text('x'));
    expect(
      t.binding.now(),
      TwkTester.defaultStartTime.add(t.clock.elapsed),
    );
  });

  testTwk("a Calendar given no today marks the app's today", (t) async {
    await t.pumpWidget(
      Theme.terminal(child: Calendar(onSelected: (_) {})),
      startTime: DateTime(2026, 2, 14, 12),
      size: (30, 10),
    );
    expect(t, containsLine(contains('February 2026')));
    // today in bold, the only bold day of the month
    final row = t.lines.indexWhere((l) => l.contains('14'));
    final x = t.lines[row].indexOf('14');
    expect(t.cell(x, row).attrs & Attr.bold, Attr.bold);
    expect(t.cell(t.lines[row].indexOf('13'), row).attrs & Attr.bold, 0);
  });

  test("with no start time, the system's time, not the app's clock moved "
      'on', () async {
    final clock = FakeClock();
    final binding = AppBinding(
      HeadlessTerminal(width: 10, height: 1),
      clock: clock.stopwatch,
      environment: const {},
    );
    await clock.elapse(const Duration(hours: 1));
    final now = DateTime.now();
    expect(
      binding.now().difference(now).abs(),
      lessThan(const Duration(minutes: 1)),
    );
  });
}
