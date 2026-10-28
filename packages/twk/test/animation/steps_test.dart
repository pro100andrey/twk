// Steps on the fake clock: the step a frame is in, onStep at the first
// frame of each while started and never once stopped, and an interval set
// while started going on at the next step of the new one; without a
// binding, the first step for good.
import 'package:test/test.dart';
import 'package:twk/src/animation/steps.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

/// Pumps until the clock reads [at].
Future<void> until(TwkTester t, Duration at) => t.pump(at - t.clock.elapsed);

void main() {
  testTwk('started, it calls onStep at the first frame of each step; '
      'stopped, no more', (t) async {
    await t.pumpWidget(const Text('app'), size: (4, 1));
    final at = <int>[];
    late final Steps steps;
    steps = Steps(ms * 100, () => at.add(steps.current), binding: t.binding)
      ..start();
    await until(t, ms * 350);
    expect(at, [1, 2, 3]);
    steps.stop();
    await until(t, ms * 600);
    expect(at, [1, 2, 3]);
  });

  testTwk('an interval set while started goes on at the next step of the '
      'new one, and is the one it has', (t) async {
    await t.pumpWidget(const Text('app'), size: (4, 1));
    final at = <int>[];
    late final Steps steps;
    steps = Steps(ms * 100, () => at.add(steps.current), binding: t.binding)
      ..start();
    expect(steps.interval, ms * 100);
    await until(t, ms * 150);
    expect(at, [1]);
    steps.interval = ms * 40;
    expect(steps.interval, ms * 40);
    await until(t, ms * 250);
    // the steps of 40 from the one the last frame was in on: 120 to 160,
    // then those from 160, 200 and 240
    expect(at, [1, 3, 4, 5, 6]);
    steps.stop();
  });

  test('without a binding it stays at the first step', () {
    final steps = Steps(ms * 10, () => fail('stepped'))..start();
    expect(steps.current, 0);
    expect(steps.interval, ms * 10);
  });
}
