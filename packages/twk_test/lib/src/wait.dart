/// Waits on real time for what takes as long as the machine lets it, with
/// a bound that fails saying what was waited for: [waitUntil], [waitFor].
///
/// @docImport 'fake_clock.dart';
library;

import 'dart:async';

import 'package:test/test.dart';

// Examples can assume:
// import 'dart:async';
// import 'dart:io';
// import 'package:test/test.dart';

/// Completes once [condition] holds, looked at again every millisecond
/// of real time: for what a real process, a pseudo-terminal, a socket or
/// the file system does, which no clock of the test's moves. A
/// [TestFailure] naming [what] once [timeout] of real time passed and it
/// still does not hold, instead of a test that hangs or a sleep that
/// guesses how long is long enough.
///
/// [condition] may be asynchronous: it is awaited before the next look.
/// [between] runs after each look that failed, before the next: a
/// tester's `pump` there lets an app on a [FakeClock] take in what
/// arrived in real time. What [condition] or [between] throws, this
/// throws.
///
/// Its looks are real timers: called in a [FakeClock]'s zone it would
/// wait for that clock, so it is called outside it, as a test's body is.
///
/// A file another process writes:
///
/// ```dart
/// final file = File('${Directory.systemTemp.path}/ready');
/// await waitUntil(file.existsSync, 'the ready file');
/// ```
///
/// See also:
///
///  * [waitFor], for an event that is a future.
///  * [FakeClock.elapseUntil], for a future of code on a fake clock.
Future<void> waitUntil(
  FutureOr<bool> Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 10),
  FutureOr<void> Function()? between,
}) async {
  final watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > timeout) {
      fail('waited ${_seconds(timeout)} for $what, in vain');
    }
    await between?.call();
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// What [event] completes with, once it has, in real time: a line a
/// process prints, its exit code, the data a socket gets. A
/// [TestFailure] naming [what] once [timeout] of real time passed
/// without it; the error [event] completes with, it throws.
///
/// Its bound is a real timer: called in a [FakeClock]'s zone it would
/// wait for that clock, so it is called outside it, as a test's body is.
///
/// A process's exit:
///
/// ```dart
/// final process = await Process.start('true', []);
/// expect(await waitFor(process.exitCode, 'the exit of true'), 0);
/// ```
///
/// See also:
///
///  * [waitUntil], for a condition that no future tells.
Future<T> waitFor<T>(
  Future<T> event,
  String what, {
  Duration timeout = const Duration(seconds: 10),
}) => event.timeout(
  timeout,
  onTimeout: () => fail('waited ${_seconds(timeout)} for $what, in vain'),
);

String _seconds(Duration d) =>
    '${(d.inMicroseconds / 1e6).toStringAsFixed(3)} s';
