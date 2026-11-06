// Steps, Ticker, StepCount and MuteGroup without an app: on a fake frame
// clock the test moves, with no tester, terminal or binding.
import 'package:test/test.dart';
import 'package:twk/src/animation/mute.dart';
import 'package:twk/src/animation/step_count.dart';
import 'package:twk/src/animation/steps.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

final class _Flag implements Muteable {
  @override
  var muted = false;
}

void main() {
  group('StepCount', () {
    test('counts the step a time is in, and the time the next starts at', () {
      final c = StepCount(ms * 100);
      expect(c.current(ms * 250), 2);
      expect(c.nextAt(ms * 250), ms * 300);
    });

    test('muted it stays at its step, unmuted it goes on from it', () {
      final c = StepCount(ms * 100)..mute(ms * 300);
      expect(c.current(ms * 1300), 3);
      c.unmute();
      expect(c.current(ms * 1300), 3);
      expect(c.current(ms * 1500), 5);
    });

    test('an interval set keeps the step it is in', () {
      final c = StepCount(ms * 100)
        ..mute(ms * 300)
        ..unmute();
      expect(c.current(ms * 1300), 3);
      expect(c.setInterval(ms * 50, ms * 1300), isTrue);
      expect(c.current(ms * 1300), 3);
      expect(c.current(ms * 1400), 5);
      expect(c.setInterval(ms * 50, ms * 1400), isFalse);
    });

    test('an interval not longer than zero is an ArgumentError', () {
      expect(() => StepCount(Duration.zero), throwsArgumentError);
      expect(() => StepCount(ms).setInterval(-ms, ms), throwsArgumentError);
    });
  });

  group('MuteGroup', () {
    test('mute sets all of its items, and add returns the item', () {
      final group = MuteGroup<_Flag>();
      final a = group.add(_Flag());
      final b = group.add(_Flag());
      group.mute(true);
      expect([a.muted, b.muted], [true, true]);
      group
        ..remove(b)
        ..mute(false);
      expect([a.muted, b.muted], [false, true]);
    });
  });

  group('Steps on a FakeFrameClock', () {
    test('onStep at the first frame of each step; none once stopped', () {
      final clock = FakeFrameClock();
      final at = <int>[];
      late final Steps steps;
      steps = Steps(ms * 100, () => at.add(steps.current), binding: clock)
        ..start();
      for (var t = 100; t <= 350; t += 50) {
        clock.advance(ms * t);
      }
      expect(at, [1, 2, 3]);
      steps.stop();
      expect(clock.pending, 0);
    });

    test('muted it asks for nothing and keeps its step; then goes on', () {
      final clock = FakeFrameClock();
      final steps = Steps(ms * 100, () {}, binding: clock)..start();
      clock.advance(ms * 300);
      steps.muted = true;
      expect(clock.pending, 0);
      clock.advance(ms * 1300);
      expect(steps.current, 3);
      steps.muted = false;
      expect(clock.pending, 1);
      expect(steps.current, 3);
      clock.advance(ms * 1500);
      expect(steps.current, 5);
      steps.stop();
    });
  });

  group('Ticker on a FakeFrameClock', () {
    test('ticks with the time since its first tick, muted not at all', () {
      final clock = FakeFrameClock();
      final ticks = <Duration>[];
      final ticker = Ticker(ticks.add, binding: clock)..start();
      clock
        ..advance(ms * 10)
        ..advance(ms * 25);
      ticker.muted = true;
      clock.advance(ms * 40);
      ticker.muted = false;
      clock.advance(ms * 60);
      expect(ticks, [Duration.zero, ms * 15, ms * 50]);
      ticker.dispose();
      expect(clock.pending, 0);
    });
  });
}
