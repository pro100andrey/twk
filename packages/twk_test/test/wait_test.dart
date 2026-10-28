// The waits on real time, each bounded: what they wait for, and how they
// fail when it does not come.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart';

Matcher _failure(String message) =>
    throwsA(isA<TestFailure>().having((e) => e.message, 'message', message));

void main() {
  group('waitUntil', () {
    test('completes once the condition holds, set in real time', () async {
      var ready = false;
      // the event in real time, which the wait helpers are for
      // ignore: twk_lints/wall_time_in_tests
      Timer(const Duration(milliseconds: 20), () => ready = true);
      await waitUntil(() => ready, 'ready');
      expect(ready, isTrue);
    });

    test('looks no more once the condition holds', () async {
      var looks = 0;
      await waitUntil(() => ++looks == 3, 'the third look');
      expect(looks, 3);
    });

    test('awaits an asynchronous condition', () async {
      var looks = 0;
      await waitUntil(() => Future.value(++looks == 2), 'the second look');
      expect(looks, 2);
    });

    test('runs between after each look that failed, before the next', () async {
      final seen = <String>[];
      var looks = 0;
      await waitUntil(
        () {
          seen.add('look');
          return ++looks == 3;
        },
        'the third look',
        between: () => seen.add('between'),
      );
      expect(seen, ['look', 'between', 'look', 'between', 'look']);
    });

    test('fails naming what it waited for once the timeout passed', () async {
      final watch = Stopwatch()..start();
      await expectLater(
        waitUntil(
          () => false,
          'what never comes',
          timeout: const Duration(milliseconds: 50),
        ),
        _failure('waited 0.050 s for what never comes, in vain'),
      );
      expect(watch.elapsed, greaterThan(const Duration(milliseconds: 50)));
    });

    test('throws what the condition throws', () async {
      await expectLater(
        waitUntil(() => throw StateError('boom'), 'boom'),
        throwsStateError,
      );
    });
  });

  group('waitFor', () {
    test('returns what the event completes with', () async {
      final line = Completer<String>();
      // the event in real time, which the wait helpers are for
      // ignore: twk_lints/wall_time_in_tests
      Timer(const Duration(milliseconds: 20), () => line.complete('running'));
      expect(await waitFor(line.future, 'the line'), 'running');
    });

    test('throws the error the event completes with', () async {
      await expectLater(
        waitFor(Future<void>.error(StateError('boom')), 'the error'),
        throwsStateError,
      );
    });

    test('fails naming what it waited for once the timeout passed', () async {
      await expectLater(
        waitFor(
          Completer<int>().future,
          'the exit of the server',
          timeout: const Duration(milliseconds: 50),
        ),
        _failure('waited 0.050 s for the exit of the server, in vain'),
      );
    });
  });
}
