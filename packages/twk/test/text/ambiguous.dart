/// An app on a terminal that takes the East Asian Ambiguous characters
/// (`│ ─ … – ● ○`) as two columns, as one in a CJK locale does, its
/// screen read back through an emulator that takes them so too: what the
/// tests of the rows that the mouse hits by parts run on.
library;

import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// An app showing a widget on a [HeadlessTerminal] whose ambiguous
/// characters are two columns wide.
///
/// It runs on a [FakeClock]: its frames are timers, which fire when
/// [settle] moves the clock on, however long the machine takes to run
/// them.
final class WideApp {
  WideApp._(this.clock, this.terminal, this.binding, this._running);

  /// Starts [app] on a terminal [width] × [height] and lets it draw its
  /// first frame.
  static Future<WideApp> start(
    Widget app, {
    int width = 60,
    int height = 3,
  }) async {
    final clock = FakeClock();
    final terminal = clock.run(
      () => HeadlessTerminal(width: width, height: height, ambiguousWidth: 2),
    );
    final binding = clock.run(
      () => AppBinding(
        terminal,
        maxFps: 1000,
        logs: LogSink(),
        clock: clock.stopwatch,
      ),
    );
    final running = clock.run(() => binding.run(app));
    final shown = WideApp._(clock, terminal, binding, running);
    await shown.settle();
    return shown;
  }

  /// The app's clock, which moves only as the test says.
  final FakeClock clock;
  final HeadlessTerminal terminal;
  final AppBinding binding;
  final Future<void> _running;

  late final _vt = Vt(
    terminal.width,
    terminal.height,
    segmenter: TextSegmenter(ambiguousWidth: 2),
  );
  var _fed = 0;

  /// Lets the app take its input and draw its frames, over 40 ms of its
  /// clock.
  Future<void> settle() => clock.elapse(const Duration(milliseconds: 40));

  /// A click of the left button at column [x] of row [y], from 0.
  Future<void> click(int x, int y) async {
    terminal.type('\x1b[<0;${x + 1};${y + 1}M\x1b[<0;${x + 1};${y + 1}m');
    await settle();
  }

  /// The screen as lines, blanks at their ends trimmed; the second column
  /// of a wide character is not one of their characters.
  List<String> lines() {
    for (; _fed < terminal.frames.length; _fed++) {
      _vt.feed(terminal.frames[_fed]);
    }
    return [
      for (var y = 0; y < terminal.height; y++)
        [
          for (var x = 0; x < terminal.width; x++) _vt.cell(x, y).text,
        ].join().trimRight(),
    ];
  }

  /// Ends the app, and runs it until it has ended, throwing the error it
  /// ended with.
  Future<void> quit() async {
    clock.run(binding.quit);
    await clock.elapseUntil(_running);
  }
}
