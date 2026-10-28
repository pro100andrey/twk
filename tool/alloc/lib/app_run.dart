/// An app of package:twk run in memory for measuring: the real binding on a
/// [HeadlessTerminal], time a [SyncClock]'s — what `TwkTester` runs, less
/// the emulator, which would add its own work to every frame, and less
/// the test clock's turns of the real event loop, which would add theirs.
library;

import 'dart:async';
import 'dart:convert';

import 'package:twk/twk.dart';

import 'sync_clock.dart';

/// The gap between two frames at 60 fps.
const frameGap = Duration(microseconds: 16667);

final class AppRun {
  AppRun._(this.clock, this.terminal, this.binding);

  /// Starts [app] on a terminal of [width] × [height] cells and runs its
  /// first frames.
  static Future<AppRun> start(
    Widget app, {
    int width = 200,
    int height = 60,
  }) async {
    final clock = SyncClock();
    late final HeadlessTerminal term;
    late final AppBinding binding;
    clock.run(() {
      term = HeadlessTerminal(width: width, height: height);
      // the log kept in memory, as an app's is: not printed; none of the
      // shell's TWK_* variables, so that each run measures the same app
      binding = AppBinding(
        term,
        clock: clock.stopwatch,
        logs: LogSink(),
        environment: const {},
      );
      unawaited(binding.run(app));
    });
    final r = AppRun._(clock, term, binding)
      ..pump(const Duration(milliseconds: 100));
    // what the app started outside the clock's zone, if anything
    await Future<void>.delayed(Duration.zero);
    return r;
  }

  final SyncClock clock;
  final HeadlessTerminal terminal;
  final AppBinding binding;

  /// The frames written and their bytes since the start.
  var frames = 0;
  var bytes = 0;

  /// Moves the clock on by [d]: the frames due by then run. What they
  /// wrote is counted and dropped. ([HeadlessTerminal.write] copies each
  /// frame: a `Uint8List` of the frame's bytes the app itself would not
  /// allocate, which the report shows as such.)
  void pump([Duration d = frameGap]) {
    clock.elapse(d);
    // by index: a for-in would be the tool's own iterator a step
    final written = terminal.frames;
    for (var i = 0; i < written.length; i++) {
      frames++;
      bytes += written[i].length;
    }
    written.clear();
  }

  /// [bytes] arrive from the terminal: decoded by the real parser, they go
  /// to the app as events.
  void input(List<int> bytes) => clock.run(() => terminal.input(bytes));

  void type(String text) => input(utf8.encode(text));

  Future<void> stop() async {
    clock.run(binding.quit);
    pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(Duration.zero);
  }
}

const keyDown = [0x1B, 0x5B, 0x42];
const keyUp = [0x1B, 0x5B, 0x41];
const keyBackspace = [0x7F];

/// An SGR mouse motion with no button at column [x], row [y] (from 0).
List<int> mouseMotion(int x, int y) =>
    ascii.encode('\x1b[<35;${x + 1};${y + 1}M');
