/// A twk_cli program as it runs at a terminal, shown in a widget: [CliRun]
/// runs it on twk_cli's fake terminal ([FakeCliTerminal.interactive]),
/// typing what somebody at it would ([CliScript]), on a clock of its own
/// moved to the time it shows, and draws the fake terminal's screen, its
/// emulator's cells, as they are then.
///
/// The gallery's App › Cli page shows its programs (`create.dart`,
/// `install.dart`, `check.dart`, next to this file) so; its Code check
/// copies this file beside a Code that is a twk_cli program and runs the
/// Code in it, to hold the one to the other.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:twk/twk.dart';
import 'package:twk_cli/testing.dart';
import 'package:twk_cli/twk_cli.dart';

/// What a twk_cli program's `main` hands `Cli.runWithArgs`.
typedef CliProgram = FutureOr<void> Function(Cli cli, List<String> rest);

/// Keys as a terminal sends them.
const _enter = '\r';
const _down = '\x1B[B';
const _backspace = '\x7F';

/// What somebody at the terminal does in a run of a program: the
/// [command] typed at the shell, then the keys [typed], each at its time
/// in ms from the start; the run is played again every [period] ms.
final class CliScript {
  const CliScript({
    required this.command,
    required this.period,
    this.typed = const [],
  });

  /// The shell's line the program was started from.
  final String command;

  /// Keys as a terminal sends them, by the time they are typed at.
  final List<(int, String)> typed;

  /// How long a run lasts, its end shown until the next starts.
  final int period;
}

/// The keys of [text] typed one each [ms] from [at].
List<(int, String)> _typing(int at, String text, [int ms = 80]) => [
  for (final (i, char) in text.split('').indexed) (at + i * ms, char),
];

/// The gallery's runs of its programs, by the program's name.
final cliScripts = <String, CliScript>{
  // a name refused, put right; a template, a feature more, a yes
  'create': CliScript(
    command: 'dart run lib/cli/create.dart',
    typed: [
      ..._typing(150, 'todo cli'),
      (900, _enter),
      for (var i = 0; i < 4; i++) (1150 + i * 60, _backspace),
      ..._typing(1450, '_cli', 70),
      (1850, _enter),
      (2150, _down),
      (2350, _down),
      (2600, _enter),
      (2900, _down),
      (3050, _down),
      (3200, ' '),
      (3500, _enter),
      (3900, 'y'),
      (4150, _enter),
    ],
    period: 7000,
  ),
  'install': const CliScript(
    command: 'dart run lib/cli/install.dart',
    period: 5000,
  ),
  'check': const CliScript(
    command: 'dart run lib/cli/check.dart',
    period: 5000,
  ),
};

/// [program] run as [script] says, a run starting at 0 and every period
/// after, on a terminal the size of the room it is given (72 × 20 where
/// that is unbounded): its screen as it is at [at], or at the app's time
/// ([AppBinding.frameTime]) where [at] is null, which moves it on a step
/// of 50 ms a frame while the program runs.
///
/// The program runs in the interactive mode, in the terminal's colors of
/// the theme's brightness ([ThemeData.terminal]); after it the shell's
/// prompt shows, until the run starts again.
final class CliRun extends StatefulWidget {
  const CliRun({
    required this.script,
    required this.program,
    this.at,
    super.key,
  });

  final CliScript script;
  final CliProgram program;

  /// The time shown, which stands still; null for the app's time.
  final Duration? at;

  @override
  State<CliRun> createState() => _CliRunState();
}

/// A run of a program: its terminal and the clock it runs on, from
/// [start] on the app's clock.
final class _Run {
  _Run(this.start, this.width, this.height, this.brightness);

  final int start;
  final int width;
  final int height;
  final Brightness brightness;

  final clock = FakeClock();
  late final terminal = FakeCliTerminal.interactive(
    width: width,
    height: height,
    fakeClock: clock,
  );

  /// Whether the program ended.
  var ended = false;

  /// Whether the clock is moving, and the time it moves to, in ms.
  var moving = false;
  var target = 0;

  /// The screen as it was at times of the clock, in ms, a row of spans a
  /// line: those from the last shown on.
  final shots = <int, List<List<Span>>>{};

  /// The screen at the latest time at or before [ms] it was read at; null
  /// before the first.
  List<List<Span>>? shotAt(int ms) {
    int? best;
    for (final t in shots.keys) {
      if (t <= ms && (best == null || t > best)) {
        best = t;
      }
    }
    shots.removeWhere((t, _) => best != null && t < best);
    return best == null ? null : shots[best];
  }

  void begin(CliScript script, CliProgram program) {
    terminal.out.write('\x1B[32m\$\x1B[0m ${script.command}\n');
    clock.run(() {
      for (final (at, keys) in script.typed) {
        Timer(Duration(milliseconds: at), () => terminal.type(keys));
      }
      unawaited(
        Cli.run(
          (cli) => program(cli, const []),
          open: ({ansi, interactive}) => terminal,
          theme: CliTheme(data: ThemeData.terminal(brightness)),
        ).whenComplete(() {
          // the shell's prompt again
          terminal.out.write('\x1B[32m\$\x1B[0m ');
          ended = true;
        }),
      );
    });
  }

  /// The screen as it is: each cell's glyph and style, the cursor's cell
  /// in reverse video where it shows.
  List<List<Span>> read() {
    // brings the screen up to date with the session's frames
    terminal.screenLines;
    final vt = terminal.screen;
    return [
      for (var y = 0; y < vt.height; y++)
        _row(vt, y, vt.cursorVisible && vt.cy == y ? vt.cx : -1),
    ];
  }

  static List<Span> _row(Vt vt, int y, int cursor) {
    final spans = <Span>[];
    final text = StringBuffer();
    var style = const Style();
    void flush() {
      if (text.isNotEmpty) {
        spans.add(Span('$text', style));
        text.clear();
      }
    }

    // the cells up to the last one that shows something
    var end = vt.width;
    while (end > 0 && end - 1 != cursor && _blank(vt, end - 1, y)) {
      end--;
    }
    for (var x = 0; x < end; x++) {
      final c = vt.cell(x, y);
      if (c.role == -1) {
        continue;
      }
      final s = Style(
        fg: _color(c.fg),
        bg: _color(c.bg),
        attrs: x == cursor ? c.attrs ^ Attr.reverse : c.attrs,
      );
      if (s != style) {
        flush();
        style = s;
      }
      text.write(c.text);
    }
    flush();
    return spans;
  }

  static bool _blank(Vt vt, int x, int y) {
    final c = vt.cell(x, y);
    return c.text == ' ' && c.bg == 0 && c.attrs == 0 && c.role == 0;
  }

  /// The terminal's color [v] as twk's: null for the default.
  static Color? _color(int v) => v == 0
      ? null
      : v & 0x1000000 != 0
      ? Color.rgb(v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF)
      : Color.indexed(v & 0xFF);
}

final class _CliRunState extends State<CliRun> {
  _Run? _run;
  AppBinding? _binding;
  int? _wake;

  /// The screen shown last, kept while a new run has none yet.
  var _rows = const <List<Span>>[];

  @override
  void dispose() {
    _cancelWake();
    _run = null;
    super.dispose();
  }

  void _cancelWake() {
    if (_wake case final id?) {
      _binding?.cancelFrameCallback(id);
    }
    _wake = null;
  }

  /// The screen at [now] ms on a terminal [width] × [height], of a new
  /// run where the period, the size or the brightness changed. The clock
  /// is moved to [now], and a step further where time moves, so that the
  /// screen of the next step is there by the frame that shows it.
  List<List<Span>> _advance(
    int now,
    int width,
    int height,
    Brightness brightness,
  ) {
    final period = widget.script.period;
    final start = now - now % period;
    var run = _run;
    if (run == null ||
        run.start != start ||
        run.width != width ||
        run.height != height ||
        run.brightness != brightness) {
      run = _run = _Run(start, width, height, brightness)
        ..begin(widget.script, widget.program);
    }
    final live = widget.at == null;
    final at = now - start + (live ? _step : 0);
    if (at > run.target || run.shots.isEmpty && !run.moving) {
      run.target = math.max(run.target, at);
      unawaited(_move(run));
    }
    final rows = _rows = run.shotAt(now - start) ?? _rows;
    if (live) {
      _cancelWake();
      // after the program, once its last screen shows: the next run
      final idle =
          run.ended &&
          !run.moving &&
          run.shots.keys.every((t) => t <= now - start);
      final next = idle ? start + period : now + _step;
      _wake = _binding?.scheduleFrameCallback((_) {
        _wake = null;
        if (mounted) {
          setState(() {});
        }
      }, at: Duration(milliseconds: next));
    }
    return rows;
  }

  /// Moves [run]'s clock to its target a step at a time, reading the
  /// screen at each; then builds again.
  Future<void> _move(_Run run) async {
    if (run.moving) {
      return;
    }
    run.moving = true;
    try {
      while (identical(run, _run)) {
        final now = run.clock.elapsed.inMilliseconds;
        if (run.shots.isNotEmpty && now >= run.target) {
          break;
        }
        final next = run.shots.isEmpty
            ? now
            : math.min(run.target, (now ~/ _step + 1) * _step);
        await run.clock.elapse(Duration(milliseconds: next - now));
        run.shots[next] = run.read();
      }
    } finally {
      run.moving = false;
    }
    if (mounted && identical(run, _run)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _binding = AppBinding.maybeOf(context);
    final brightness = Theme.of(context).brightness;
    // the time on a step, the nearest: a frame a moment short of a step
    // shows it, as the step a time on it does
    final time = widget.at ?? _binding?.frameTime ?? Duration.zero;
    final now = (time.inMicroseconds + _step * 500) ~/ (_step * 1000) * _step;
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxW < BoxConstraints.unbounded ? c.maxW : 72;
        final height = c.maxH < BoxConstraints.unbounded ? c.maxH : 20;
        final rows = _advance(now, width, height, brightness);
        return SizedBox(
          width: width,
          height: height,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: [
              for (final row in rows)
                SizedBox(
                  height: 1,
                  child: Text.rich(row, wrap: TextWrap.none),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The steps the screen is shown at, in ms.
const _step = 50;
