/// What the tests of the pointer's shape run: an app on a terminal in
/// memory that shows the shape, the mouse moved, pressed, dragged and
/// released on it, and the shapes the app set read back.
library;

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

/// An app run full screen on a terminal in memory, by default 20 × 4
/// cells, that shows the pointer's shape unless told it does not: the
/// arrow from the first frame on, where nothing gives it another
/// ([start]).
///
/// It runs on a [FakeClock]: its frames are timers, which fire when
/// [settle] moves the clock on, however long the machine takes to run
/// them.
final class ShapeRun {
  ShapeRun(Widget app, {int width = 20, int height = 4, this.shows = true}) {
    clock.run(() {
      term = HeadlessTerminal(
        width: width,
        height: height,
        pointerShapes: shows,
      );
      unawaited(
        AppBinding(term, maxFps: 1000, clock: clock.stopwatch)
            .run(app)
            .then<void>(
              (_) => _ended = true,
              onError: (Object error, StackTrace stack) {
                _ended = true;
                _error = (error, stack);
              },
            ),
      );
    });
  }

  /// Whether the terminal shows the pointer's shape.
  final bool shows;

  /// The app's clock, which moves only as the test says.
  final clock = FakeClock();
  late final HeadlessTerminal term;
  var _ended = false;
  (Object, StackTrace)? _error;
  var _read = 0;

  /// Lets the frame loop run: builds, frames and the timers they start,
  /// over 30 ms of the app's clock.
  Future<void> settle() => clock.elapse(const Duration(milliseconds: 30));

  /// Lets the first frames run, and reads the arrow the app shows where
  /// the terminal shows the pointer's shape, nothing where it does not.
  Future<void> start() async {
    await settle();
    expect(shapes(), shows ? ['default'] : isEmpty);
  }

  /// Runs [fn] in the app's zone, then lets the frame loop run.
  Future<void> act(void Function() fn) async {
    clock.run(fn);
    await settle();
  }

  /// What the app wrote since the last call.
  String written() {
    final s = utf8.decode([
      for (final f in term.frames.skip(_read)) ...f,
    ], allowMalformed: true);
    _read = term.frames.length;
    return s;
  }

  /// The shapes the app set since the last call, `` for the terminal's
  /// own, `default` for the arrow.
  List<String> shapes() => [
    for (final m in RegExp('\x1b]22;([^\x1b]*)\x1b\\\\').allMatches(written()))
      m[1]!,
  ];

  /// The mouse moved to the cell ([x], [y]) with no button held.
  Future<void> move(int x, int y) => _mouse(35, x, y);

  /// The left button pressed at the cell ([x], [y]).
  Future<void> press(int x, int y) => _mouse(0, x, y);

  /// The mouse moved to the cell ([x], [y]) with the left button held.
  Future<void> drag(int x, int y) => _mouse(32, x, y);

  /// The left button released at the cell ([x], [y]).
  Future<void> release(int x, int y) => _mouse(0, x, y, release: true);

  /// The mouse reported at ([x], [y]) as SGR [code] says, and frames run.
  Future<void> _mouse(int code, int x, int y, {bool release = false}) async {
    term.type('\x1b[<$code;${x + 1};${y + 1}${release ? 'm' : 'M'}');
    await settle();
  }

  /// Quits the app and runs it until it has ended, throwing the error it
  /// ended with.
  ///
  /// The app's future completes in the clock's zone, as the clock moves:
  /// awaited without moving it, it never would.
  Future<void> quit() async {
    term.type('\x03');
    for (var i = 0; !_ended; i++) {
      if (i == 100) {
        throw StateError('the app did not end within 100 settles of quit');
      }
      await settle();
    }
    if (_error case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
  }
}
