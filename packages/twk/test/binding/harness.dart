/// What the binding tests run apps with: an app full screen on a terminal
/// in memory whose frames go into the emulator, stderr caught, on a
/// [FakeClock] the test moves; and widgets that show a line of text, fill
/// their room or count their builds.
library;

import 'dart:async';
import 'dart:io';

import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart' show FakeClock, FakeStderr;
import 'package:twk_test/vt.dart';

/// The frame loop of an app run on a [FakeClock] by hand: its binding
/// made in the clock's zone and reading [FakeClock.stopwatch].
extension FrameLoop on FakeClock {
  /// Lets the frame loop run: builds, frames and the timers they start,
  /// over [ms] ms of the app's clock, however long the machine takes to
  /// run them.
  Future<void> settle([int ms = 30]) => elapse(Duration(milliseconds: ms));
}

/// An app run by an [AppBinding] full screen on a [HeadlessTerminal] in
/// memory whose default background is the RGB `backgroundRgb` gives
/// (unknown when null), stderr caught in [stderrLines], on [clock]: its
/// frames and timers wait until [settle] moves the clock on. With `zone`,
/// the binding runs in a zone of that specification forked inside the
/// clock's.
final class Run {
  Run(
    Widget app, {
    int width = 20,
    int height = 4,
    int maxFps = 1000,
    bool exitOnCtrlC = true,
    int? backgroundRgb,
    ZoneSpecification? zone,
  }) : vt = Vt(width, height) {
    clock.run(() {
      term = HeadlessTerminal(
        width: width,
        height: height,
        backgroundRgb: backgroundRgb,
      );
      done = IOOverrides.runZoned(
        () => runZoned(
          () => AppBinding(
            term,
            maxFps: maxFps,
            logs: logs,
            exitOnCtrlC: exitOnCtrlC,
            clock: clock.stopwatch,
            // none of the shell's TWK_* variables
            environment: const {},
          ).run(app),
          zoneSpecification: zone,
        ),
        stderr: () => _err,
      );
    });
    // an error is expected by the test that awaits it, not by the zone
    unawaited(done.then((_) {}, onError: (_) {}));
  }

  /// The time of the app.
  final clock = FakeClock();
  late final HeadlessTerminal term;
  final Vt vt;
  final logs = LogSink();

  /// The app's run, which completes in the clock's zone as the clock
  /// moves: [ended] awaits it.
  late final Future<void> done;
  // ignore: close_sinks, stands in for stderr, which stays open
  late final _err = FakeStderr(
    tag: () => term.closed ? 'restored' : 'on screen',
  );
  var _fed = 0;

  /// Lets the frame loop run for [ms] ms of the app's clock.
  Future<void> settle([int ms = 30]) => clock.settle(ms);

  /// The app's run once the clock has moved on until it ended: awaited,
  /// it throws the error the app ended with.
  Future<void> ended() => clock.elapseUntil(done);

  /// What reached stderr, each line after whether the terminal was
  /// restored then.
  List<String> get stderrLines => _err.writes;

  /// The rows the emulator shows, without the blanks that end them.
  List<String> get rows {
    _feed();
    return [
      for (var y = 0; y < vt.height; y++)
        [
          for (var x = 0; x < vt.width; x++) vt.cell(x, y).text,
        ].join().trimRight(),
    ];
  }

  /// Whether the cell at ([x], [y]) has the red background of an error.
  bool redAt(int x, int y) => cell(x, y).bg == _red;

  /// The cell at ([x], [y]) the emulator shows.
  VtCell cell(int x, int y) {
    _feed();
    return vt.cell(x, y);
  }

  // what the emulator keeps for Color.red
  static const int _red = 0x2000000 | 1;

  void _feed() {
    for (; _fed < term.frames.length; _fed++) {
      vt.feed(term.frames[_fed]);
    }
  }

  /// The messages of the records in [logs] at [level].
  List<String> logged(LogLevel level) => [
    for (final r in logs.records)
      if (r.level == level) r.message,
  ];
}

/// [children] in a column, each at its left edge.
Column column(List<Widget> children) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);

/// One line of [text] (one column per character), as wide as the text.
final class Label extends LeafRenderObjectWidget {
  const Label(this.text, {super.key});

  final String text;

  @override
  RenderLabel createRenderObject(BuildContext context) => RenderLabel(text);

  @override
  void updateRenderObject(BuildContext context, RenderLabel renderObject) =>
      renderObject.text = text;
}

/// What a [Label] lays out and paints.
final class RenderLabel extends RenderObject {
  RenderLabel(this._text);

  String _text;
  String get text => _text;
  set text(String t) {
    if (t != _text) {
      _text = t;
      markNeedsLayout();
    }
  }

  @override
  int computeMaxIntrinsicWidth(int height) => _text.length;

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_text.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.text(0, 0, _text, ctx.canvas.styles.pen(const Pen()));
}

/// Fills all the room it gets with [char].
final class Fill extends LeafRenderObjectWidget {
  const Fill(this.char, {super.key});

  final String char;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFill(char);
}

final class _RenderFill extends RenderObject {
  _RenderFill(this.char);

  final String char;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) => ctx.canvas.fill(
    0,
    0,
    width,
    height,
    ctx.canvas.styles.pen(const Pen()),
    char.codeUnitAt(0),
  );
}

/// Shows what [builder] builds from the state, which counts its builds
/// and runs [onInit] and [onDispose].
final class Probe extends StatefulWidget {
  const Probe(this.builder, {this.onInit, this.onDispose, super.key});

  final Widget Function(ProbeState state) builder;
  final void Function(ProbeState state)? onInit;
  final void Function()? onDispose;

  @override
  State<Probe> createState() => ProbeState();
}

final class ProbeState extends State<Probe> {
  /// What the builder may show; [change] changes it.
  var count = 0;

  /// How many times the state built.
  var builds = 0;

  /// Runs [fn] in setState.
  void change(void Function() fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    widget.onInit?.call(this);
  }

  @override
  void dispose() {
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    return widget.builder(this);
  }
}
