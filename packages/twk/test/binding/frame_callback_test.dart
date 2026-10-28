// Frame callbacks: called once at the start of a frame, before its build,
// with the frame's time on the app's clock, in the order they were
// scheduled; with a time, at the first frame at or after it, asked for by
// one timer; and no frame or timer while none waits.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

/// [text]'s value, rebuilt when it changes.
Widget show(ValueNotifier<String> text) => ValueListenableBuilder(
  valueListenable: text,
  builder: (_, value, _) => Text(value),
);

void main() {
  testTwk('a frame callback is called once, at the start of the next frame '
      "and before its build, with the frame's time", (t) async {
    final text = ValueNotifier('before');
    await t.pumpWidget(show(text), size: (10, 1), maxFps: 100);
    final written = t.frames.length;
    final times = <Duration>[];
    t.binding.scheduleFrameCallback((time) {
      times.add(time);
      text.value = 'after';
    });
    await t.pump();
    expect(t.frames, hasLength(written + 1));
    expect(t.lines, ['after'], reason: 'the frame builds what it changed');
    expect(times, [t.frames.last.time]);
    expect(t.binding.frameTime, t.frames.last.time);
    await t.pump(const Duration(seconds: 1));
    expect(times, hasLength(1));
    expect(t.frames, hasLength(written + 1));
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('frame callbacks are called in the order they were scheduled; one '
      'scheduled or cancelled while they are called waits for the next '
      'frame or is not called', (t) async {
    await t.pumpWidget(const Text('x'), size: (10, 1), maxFps: 100);
    final binding = t.binding;
    final calls = <String>[];
    late int third;
    binding
      ..scheduleFrameCallback((_) {
        calls.add('first');
        binding
          ..cancelFrameCallback(third)
          ..scheduleFrameCallback((_) => calls.add('next frame'));
      })
      ..scheduleFrameCallback((_) => calls.add('second'));
    third = binding.scheduleFrameCallback((_) => calls.add('third'));
    final cancelled = binding.scheduleFrameCallback((_) => calls.add('no'));
    binding.cancelFrameCallback(cancelled);
    // the next frame a gap later
    await t.pump(ms * 5);
    expect(calls, ['first', 'second']);
    await t.pump(ms * 5);
    expect(calls, ['first', 'second', 'next frame']);
    await t.pump(const Duration(seconds: 1));
    expect(calls, hasLength(3));
  });

  testTwk('a frame callback with a time is called at the first frame at or '
      'after it; one timer waits for the earliest, none once they are '
      'called or cancelled', (t) async {
    await t.pumpWidget(const Text('x'), size: (10, 1), maxFps: 100);
    final binding = t.binding;
    final start = t.clock.elapsed;
    final written = t.frames.length;
    final calls = <(String, Duration)>[];
    for (final (name, at) in [('b', 100), ('a', 100), ('c', 250)]) {
      binding.scheduleFrameCallback(
        (time) => calls.add((name, time - start)),
        at: start + ms * at,
      );
    }
    final last = binding.scheduleFrameCallback(
      (time) => calls.add(('d', time - start)),
      at: start + ms * 400,
    );
    expect(t.clock.pendingTimers, 1);
    await t.pump(ms * 99);
    expect(calls, isEmpty);
    expect(t.frames, hasLength(written), reason: 'no frame before');
    await t.pump(ms);
    expect(calls, [('b', ms * 100), ('a', ms * 100)]);
    expect(t.clock.pendingTimers, 1);
    expect(t.clock.nextTimerDue, start + ms * 250);
    await t.pump(ms * 150);
    expect(calls.last, ('c', ms * 250));
    binding.cancelFrameCallback(last);
    expect(t.clock.pendingTimers, 0);
    await t.pump(const Duration(seconds: 1));
    expect(calls, hasLength(3));
    expect(t.frames, hasLength(written), reason: 'nothing to write');
  });

  testTwk('a frame callback for a time past is called at the next frame, '
      'and one for later waits for its own when a frame comes earlier', (
    t,
  ) async {
    await t.pumpWidget(const Text('x'), size: (10, 1), maxFps: 100);
    final binding = t.binding;
    final start = t.clock.elapsed;
    final calls = <(String, Duration)>[];
    binding
      ..scheduleFrameCallback(
        (time) => calls.add(('later', time - start)),
        at: start + ms * 35,
      )
      ..scheduleFrameCallback(
        (time) => calls.add(('past', time - start)),
        at: start - ms,
      );
    await t.pump(ms * 10);
    expect(calls, [('past', Duration.zero)]);
    await t.pump(ms * 30);
    expect(calls, [('past', Duration.zero), ('later', ms * 35)]);
  });

  testTwk('the timer stops when the app ends, and a callback scheduled '
      'then is never called', (t) async {
    await t.pumpWidget(const Text('x'), size: (10, 1));
    final binding = t.binding;
    var called = false;
    binding.scheduleFrameCallback(
      (_) => called = true,
      at: const Duration(seconds: 5),
    );
    expect(t.clock.pendingTimers, 1);
    await t.quit();
    // what the end of the app left due at once
    await t.clock.elapse(Duration.zero);
    expect(t.clock.pendingTimers, 0);
    binding
      ..scheduleFrameCallback((_) => called = true)
      ..scheduleFrameCallback((_) => called = true, at: ms);
    expect(t.clock.pendingTimers, 0);
    await t.clock.elapse(const Duration(seconds: 10));
    expect(called, isFalse);
  });

  test('a frame callback scheduled before the app runs is called by its '
      'first frame, and one for a time then', () async {
    final clock = FakeClock();
    final binding = clock.run(
      () => AppBinding(
        HeadlessTerminal(width: 10, height: 1),
        clock: clock.stopwatch,
      ),
    );
    final calls = <(String, Duration)>[];
    binding
      ..scheduleFrameCallback((time) => calls.add(('first', time)))
      ..scheduleFrameCallback(
        (time) => calls.add(('later', time)),
        at: ms * 100,
      );
    expect(clock.pendingTimers, 0);
    final done = clock.run(() => binding.run(const Text('x')));
    await clock.elapse(Duration.zero);
    expect(calls, [('first', Duration.zero)]);
    expect(clock.nextTimerDue, ms * 100);
    await clock.elapse(ms * 100);
    expect(calls, [('first', Duration.zero), ('later', ms * 100)]);
    var ended = false;
    unawaited(done.then((_) => ended = true));
    clock.run(binding.quit);
    for (var i = 0; i < 10 && !ended; i++) {
      await clock.elapse(ms * 20);
    }
    expect(ended, isTrue);
  });
}
