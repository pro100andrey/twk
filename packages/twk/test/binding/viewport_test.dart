// An app in a fixed viewport of the normal screen, its frames through the
// emulator over a screen that showed a pattern everywhere before, which
// stays outside the viewport: the app laid out at the rectangle and drawn
// in it alone, as full screen at its size (the debug console over it,
// the items of a Static in place, the screen reader's lines in it), the
// mouse relative to it; last in a pseudo-terminal (tool/pty_run.py)
// running viewport_app.dart, whose terminal runApp opens with the mouse
// reported on the normal screen and ordered as runApp's bidi says.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart'
    show FakeClock, compiledProgram, runProcess;
import 'package:twk_test/vt.dart';

import 'harness.dart';

/// Where the apps here draw: 12 x 4 cells from column 6 of row 2.
const _viewport = Viewport.fixed(6, 2, 12, 4);

/// Where the cursor is before an app starts, and after it ends.
const _cursor = (2, 0);

/// An app run by an [AppBinding] in [_viewport] of the normal screen of a
/// [HeadlessTerminal] that reports the mouse there, whose frames go into
/// an emulator showing a pattern everywhere before, on [clock].
final class _Run {
  _Run(Widget app, {bool screenReader = false}) : vt = Vt(30, 10) {
    final b = StringBuffer();
    for (var y = 0; y < vt.height; y++) {
      b.write('\x1b[${y + 1}H\x1b[38;5;${1 + y % 7}m');
      for (var x = 0; x < vt.width; x++) {
        b.writeCharCode(0x61 + (x + y) % 26);
      }
    }
    b.write('\x1b[m\x1b[${_cursor.$2 + 1};${_cursor.$1 + 1}H');
    vt.feed(utf8.encode(b.toString()));
    _before = _outside();
    clock.run(() {
      term = HeadlessTerminal(
        width: 30,
        height: 10,
        options: const TerminalOptions(
          alternateScreen: false,
          normalScreenMouse: true,
        ),
      );
      done = AppBinding(
        term,
        viewport: _viewport,
        maxFps: 1000,
        logs: logs,
        screenReader: screenReader,
        clock: clock.stopwatch,
      ).run(app);
    });
  }

  /// The time of the app.
  final clock = FakeClock();
  late final HeadlessTerminal term;
  final Vt vt;
  final logs = LogSink();
  late final Future<void> done;
  late final List<String> _before;
  var _fed = 0;

  /// The rows of the viewport the emulator shows.
  List<String> get inside {
    _feed();
    return [
      for (var y = _viewport.top; y < _viewport.top + _viewport.height; y++)
        [
          for (
            var x = _viewport.left;
            x < _viewport.left + _viewport.width;
            x++
          )
            vt.cell(x, y).text,
        ].join(),
    ];
  }

  /// The cells outside the viewport that the app changed.
  List<String> get outsideChanged {
    _feed();
    final now = _outside();
    return [
      for (var i = 0; i < now.length; i++)
        if (now[i] != _before[i]) now[i],
    ];
  }

  /// Each cell outside the viewport: where it is and what it shows.
  List<String> _outside() => [
    for (var y = 0; y < vt.height; y++)
      for (var x = 0; x < vt.width; x++)
        if (x < _viewport.left ||
            y < _viewport.top ||
            x >= _viewport.left + _viewport.width ||
            y >= _viewport.top + _viewport.height)
          '($x, $y) ${vt.cell(x, y)}',
  ];

  void _feed() {
    for (; _fed < term.frames.length; _fed++) {
      vt.feed(term.frames[_fed]);
    }
  }

  /// Lets the frame loop run for 30 ms of the app's clock.
  Future<void> settle() => clock.settle();

  /// Quits the app of [context] and runs it until it has ended.
  Future<void> quit(BuildContext context) async {
    AppBinding.of(context).quit();
    await clock.elapseUntil(done);
    _feed();
  }
}

/// Shows the size it is laid out at, the last one in [sizes], as a text a
/// screen reader reads.
Widget _size(List<String> sizes) => LayoutBuilder(
  builder: (_, c) {
    sizes.add('${c.maxW} x ${c.maxH}');
    return Text(sizes.last);
  },
);

void main() {
  test('the app is laid out at the viewport and drawn in it alone, the '
      'cursor and the screen around it left as they were', () async {
    final key = GlobalKey<ProbeState>();
    final sizes = <String>[];
    final run = _Run(Probe(key: key, (_) => _size(sizes)));
    await run.settle();
    final binding = AppBinding.of(key.currentContext!);
    expect(binding.mode, ScreenMode.inline);
    expect(binding.twkApp.viewport, _viewport);
    expect(sizes.last, '12 x 4');
    expect(run.inside, ['12 x 4      ', ' ' * 12, ' ' * 12, ' ' * 12]);
    expect(run.outsideChanged, isEmpty);
    expect((run.vt.cx, run.vt.cy), _cursor);
    await run.quit(key.currentContext!);
    expect(run.term.closed, isTrue);
    expect(run.inside.first, '12 x 4      ');
    expect(run.outsideChanged, isEmpty);
    expect((run.vt.cx, run.vt.cy), _cursor);
    expect(run.vt.errors, isEmpty);
    expect(run.vt.printWraps, 0);
  });

  test('the debug console is drawn over the app in the viewport, the app '
      'keeping all of it', () async {
    final key = GlobalKey<ProbeState>();
    final sizes = <String>[];
    final run = _Run(Probe(key: key, (_) => _size(sizes)));
    await run.settle();
    AppBinding.of(key.currentContext!).debug.console.open();
    await run.settle();
    expect(sizes.last, '12 x 4');
    expect(run.inside.first, isNot('12 x 4      '));
    expect(run.outsideChanged, isEmpty);
    await run.quit(key.currentContext!);
    expect(run.outsideChanged, isEmpty);
    expect(run.vt.errors, isEmpty);
  });

  test('a Static shows its items in place, as full screen: a viewport has '
      'no history', () async {
    final key = GlobalKey<ProbeState>();
    final run = _Run(
      Probe(
        key: key,
        (_) => column([
          Static<String>(
            items: const ['one', 'two'],
            builder: (_, s) => Label(s),
          ),
          const Label('prompt'),
        ]),
      ),
    );
    await run.settle();
    expect(run.inside, [
      'one         ',
      'two         ',
      'prompt      ',
      ' ' * 12,
    ]);
    await run.quit(key.currentContext!);
    expect(run.outsideChanged, isEmpty);
    expect(run.vt.errors, isEmpty);
  });

  test('a press comes in the cells of the viewport, and the terminal '
      'reports the mouse while a Listener needs it', () async {
    final key = GlobalKey<ProbeState>();
    final presses = <String>[];
    final run = _Run(
      Probe(
        key: key,
        (_) => Listener(
          behavior: HitTestBehavior.opaque,
          onDown: (e) => presses.add('${e.x}, ${e.y}'),
          child: const SizedBox(),
        ),
      ),
    );
    await run.settle();
    expect(run.term.mouseTracking, MouseTracking.buttons);
    // screen cell (9, 3), and one outside the viewport
    run.term.type('\x1b[<0;10;4M\x1b[<0;10;4m\x1b[<0;2;2M\x1b[<0;2;2m');
    await run.settle();
    expect(presses, ['3, 1']);
    await run.quit(key.currentContext!);
  });

  test('in the screen-reader mode the lines are read in the viewport, the '
      "app laid out at the viewport's height", () async {
    final key = GlobalKey<ProbeState>();
    final sizes = <String>[];
    final run = _Run(
      Probe(key: key, (_) => _size(sizes)),
      screenReader: true,
    );
    await run.settle();
    expect(sizes.last, '12 x 4');
    expect(run.inside, ['12 x 4      ', ' ' * 12, ' ' * 12, ' ' * 12]);
    expect(run.outsideChanged, isEmpty);
    await run.quit(key.currentContext!);
    expect(run.outsideChanged, isEmpty);
    expect(run.vt.errors, isEmpty);
  });

  group('in a pseudo-terminal, runApp opens it', () {
    late String app;
    setUpAll(
      () async => app = await compiledProgram(
        'test/binding/viewport_app.dart',
        packages: (await Isolate.packageConfig)!.toFilePath(),
        cache: '.dart_tool/twk_test/programs',
      ),
    );

    /// Runs viewport_app.dart with [args] in a pseudo-terminal of 100 x
    /// 30, a press at screen cell (12, 4) once the app has drawn its box
    /// and a `q` once the box shows the press, however long the app takes
    /// to get there; returns what it wrote, checked restored by
    /// tool/pty_run.py.
    Future<String> runPty(List<String> args) async {
      final dir = Directory.systemTemp.createTempSync('viewport');
      addTearDown(() => dir.deleteSync(recursive: true));
      final out = '${dir.path}/out.bin';
      final res = await runProcess('python3', [
        '../../tool/pty_run.py',
        '--when',
        'pressed nothing',
        '--when',
        'at 2, 1',
        '--input',
        r'#1:\x1b[<0;13;5M\x1b[<0;13;5m,#2:q',
        '--out',
        out,
        '--',
        Platform.resolvedExecutable,
        app,
        ...args,
      ], group: true);
      expect(
        res.stdout,
        endsWith('terminal restored\n'),
        reason: '${res.stderr}',
      );
      expect(res.exitCode, 0);
      return latin1.decode(File(out).readAsBytesSync());
    }

    /// The rows of the viewport app's box that [written] leaves on the
    /// screen.
    List<String> box(String written) {
      final vt = Vt(100, 30)..feed(latin1.encode(written));
      expect(vt.errors, isEmpty);
      expect(vt.printWraps, 0);
      return [
        for (var y = 3; y < 8; y++)
          [for (var x = 10; x < 40; x++) vt.cell(x, y).text].join().trimRight(),
      ];
    }

    test(
      'on the normal screen with the mouse reported in the viewport, '
      'relative to it, and the text ordered for the terminal found',
      () async {
        final written = await runPty([]);
        expect(written, contains('\x1b[?1000h'));
        // the probe found a terminal that honours BDSM: explicit mode
        expect(written, contains('\x1b[8l'));
        expect(box(written), [
          '╭────────────────────────────╮',
          '│text in visual order        │',
          '│pressed at 2, 1             │',
          '│>                           │',
          '╰────────────────────────────╯',
        ]);
      },
      testOn: 'linux || mac-os',
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'ordered by the terminal where bidi says so, in its implicit mode',
      () async {
        final written = await runPty(['--bidi=terminal']);
        expect(written, isNot(contains('\x1b[8l')));
        expect(box(written)[1], '│text in logical order       │');
      },
      testOn: 'linux || mac-os',
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
