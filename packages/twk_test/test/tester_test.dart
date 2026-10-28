// The tester: an app run by the real binding under the fake clock, input
// through the parser, the screen read back from the emulator.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Shows the characters typed so far and keeps every event in [events].
final class Echo extends StatefulWidget {
  const Echo(this.events, {super.key});

  final List<InputEvent> events;

  @override
  State<Echo> createState() => _EchoState();
}

final class _EchoState extends State<Echo> {
  var _text = '';

  @override
  Widget build(BuildContext context) => InputListener(
    onEvent: (e) {
      widget.events.add(e);
      if (e case KeyEvent(code: KeyCode.char, :final char, modifiers: 0)) {
        setState(() => _text += char);
      }
      return e is! KeyEvent || !e.ctrl;
    },
    child: Text(_text),
  );
}

/// Shows `count`, changed by `change`; keeps the time of each build on
/// [clock].
final class Counter extends StatefulWidget {
  const Counter(this.clock, {super.key});

  final FakeClock clock;

  @override
  State<Counter> createState() => CounterState();
}

final class CounterState extends State<Counter> {
  var count = 0;
  final builtAt = <Duration>[];

  void change() => setState(() => count++);

  @override
  Widget build(BuildContext context) {
    builtAt.add(widget.clock.elapsed);
    return Text('count $count');
  }
}

/// Starts a timer of [after] when mounted and shows whether it fired;
/// calls [onDispose] when disposed.
final class Delayed extends StatefulWidget {
  const Delayed(this.after, {this.onDispose, super.key});

  final Duration after;
  final void Function()? onDispose;

  @override
  State<Delayed> createState() => _DelayedState();
}

final class _DelayedState extends State<Delayed> {
  var _fired = false;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.after, () => setState(() => _fired = true));
  }

  @override
  void dispose() {
    _timer.cancel();
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(_fired ? 'fired' : 'waiting');
}

/// Shows how many times [period] has passed, for ever; with [shown] false
/// what it shows stays as it was.
final class TickingCounter extends StatefulWidget {
  const TickingCounter(this.period, {this.shown = true, super.key});

  final Duration period;
  final bool shown;

  @override
  State<TickingCounter> createState() => _TickingCounterState();
}

final class _TickingCounterState extends State<TickingCounter> {
  var _ticks = 0;
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.period, (_) {
      if (widget.shown) {
        setState(() => _ticks++);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('tick $_ticks');
}

/// Fails to build.
final class Broken extends StatelessWidget {
  const Broken({super.key});

  @override
  Widget build(BuildContext context) => throw StateError('broken');
}

Column column(List<Widget> children) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);

KeyEvent char(String c, [int mods = 0]) =>
    KeyEvent(KeyCode.char, char: c, modifiers: mods);

void main() {
  testTwk('typed text goes through the parser, a key per character, and '
      'the next frame shows what it changed', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(Echo(events), size: (20, 3));
    expect(t.lines, ['', '', '']);
    await t.type('привет');
    expect(events, [for (final c in 'привет'.split('')) char(c)]);
    expect(t.lines.first, '', reason: 'no frame yet');
    await t.pump();
    expect(t.lines, ['привет', '', '']);
  });

  testTwk('press sends the bytes of each key in turn, decoded by the '
      'parser', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(Echo(events));
    await t.press('ctrl+s');
    await t.press('shift+tab');
    await t.press('g g');
    await t.press('alt+enter ctrl+left f5');
    expect(events, [
      char('s', Mod.ctrl),
      const KeyEvent(KeyCode.tab, modifiers: Mod.shift),
      char('g'),
      char('g'),
      const KeyEvent(KeyCode.enter, modifiers: Mod.alt),
      const KeyEvent(KeyCode.left, modifiers: Mod.ctrl),
      const KeyEvent(KeyCode.f5),
    ]);
    expect(
      () => t.press('ctrl+shift+s'),
      throwsArgumentError,
      reason: 'no bytes of its own without the kitty protocol',
    );
  });

  testTwk('a lone ESC is the Escape key once the escape timeout passed on '
      'the clock without more input', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(Echo(events), duration: Duration.zero);
    await t.type('\x1b');
    await t.pump(const Duration(milliseconds: 29));
    expect(events, isEmpty);
    await t.pump(const Duration(milliseconds: 1));
    expect(events, [const KeyEvent(KeyCode.escape)]);
    // more input in time makes it a sequence
    await t.type('\x1b');
    await t.pump(const Duration(milliseconds: 20));
    await t.type('[A');
    expect(events.last, const KeyEvent(KeyCode.up));
  });

  testTwk('press delivers Escape after the escape timeout, which moves the '
      'clock on', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(Echo(events), duration: Duration.zero);
    await t.press('escape');
    expect(events, [const KeyEvent(KeyCode.escape)]);
    expect(t.clock.elapsed, const Duration(milliseconds: 30));
  });

  testTwk('with the kitty keyboard protocol, Escape is a sequence of its '
      'own and a lone ESC waits 500 ms', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(
      Echo(events),
      kittyKeyboard: true,
      duration: Duration.zero,
    );
    await t.press('escape ctrl+shift+s');
    expect(events, [
      const KeyEvent(KeyCode.escape),
      char('s', Mod.ctrl | Mod.shift),
    ]);
    expect(t.clock.elapsed, Duration.zero);
    await t.type('\x1b');
    await t.pump(const Duration(milliseconds: 499));
    expect(events, hasLength(2));
    await t.pump(const Duration(milliseconds: 1));
    expect(events.last, const KeyEvent(KeyCode.escape));
  });

  testTwk('a paste arrives as one event', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(Echo(events));
    await t.paste('two\nlines');
    expect(events, [const PasteEvent('two\nlines')]);
  });

  testTwk('mouse reports and clicks arrive as mouse events; the inline mode '
      'gets none', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(Echo(events), size: (10, 4));
    await t.mouse(MouseKind.wheelDown, 2, 1, modifiers: Mod.ctrl);
    await t.click(9, 3, button: 2);
    expect(events, [
      const MouseEvent(MouseKind.wheelDown, 2, 1, modifiers: Mod.ctrl),
      const MouseEvent(MouseKind.down, 9, 3, button: 2),
      const MouseEvent(MouseKind.up, 9, 3, button: 2),
    ]);
    expect(() => t.click(10, 0), throwsRangeError);
  });

  testTwk('motions in one read coalesce as on a real terminal: the last of '
      'a run with no button held, every point of a drag', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(Echo(events), size: (10, 4));
    String sgr(int cb, int x, int y, {bool up = false}) =>
        '\x1b[<$cb;${x + 1};${y + 1}${up ? 'm' : 'M'}';
    await t.type(
      [
        for (var x = 0; x < 8; x++) sgr(35, x, 1),
        sgr(0, 7, 1),
        sgr(32, 8, 1),
        sgr(32, 9, 2),
        sgr(0, 9, 2, up: true),
        sgr(35, 8, 2),
        sgr(35, 7, 3),
      ].join(),
    );
    expect(events, [
      const MouseEvent(MouseKind.move, 7, 1),
      const MouseEvent(MouseKind.down, 7, 1),
      const MouseEvent(MouseKind.drag, 8, 1),
      const MouseEvent(MouseKind.drag, 9, 2),
      const MouseEvent(MouseKind.up, 9, 2),
      const MouseEvent(MouseKind.move, 7, 3),
    ]);
    events.clear();
    await t.mouse(MouseKind.move, 1, 0);
    await t.mouse(MouseKind.move, 2, 0);
    expect(events, [
      const MouseEvent(MouseKind.move, 1, 0),
      const MouseEvent(MouseKind.move, 2, 0),
    ], reason: 'a report a read');
  });

  testTwk('the inline mode gets no mouse reports', (t) async {
    await t.pumpWidget(const Text('x'), mode: ScreenMode.inline);
    expect(() => t.click(0, 0), throwsStateError);
  });

  testTwk('the screen reads back with colors and attributes, as Color and '
      'Attr number them', (t) async {
    await t.pumpWidget(
      column(const [
        Text(
          'red',
          style: Style(fg: Color.red, attrs: Attr.bold | Attr.underline),
        ),
        Text('on rgb', style: Style(bg: Color.rgb(1, 2, 3))),
        Text('界'),
      ]),
      size: (10, 3),
    );
    expect(t.lines, ['red', 'on rgb', '界']);
    final r = t.cell(0, 0);
    expect((r.text, r.fg, r.bg), ('r', Color.red, Color.defaultColor));
    expect(r.attrs, Attr.bold | Attr.underline);
    expect(t.cell(3, 0).attrs, 0);
    expect(t.cell(0, 1).bg, const Color.rgb(1, 2, 3));
    expect((t.cell(0, 2).text, t.cell(1, 2).text), ('界', ''));
  });

  testTwk('the cursor reads back where the app puts it', (t) async {
    await t.pumpWidget(const Text('x'), size: (10, 3));
    expect(t.cursorVisible, isFalse);
    t.binding.twkApp.screen.presenter
      ..cursorVisible = true
      ..cursorX = 4
      ..cursorY = 2;
    t.binding.twkApp.requestFrame();
    await t.pump();
    expect(t.cursorVisible, isTrue);
    expect(t.cursor, (4, 2));
  });

  testTwk('in the inline mode the app is a region below the history, which '
      'scrolls into the scrollback as it grows and stays when it '
      'ends', (t) async {
    final rows = ValueNotifier(2);
    await t.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: rows,
        builder: (_, n, _) =>
            column([for (var i = 0; i < n; i++) Text('row $i')]),
      ),
      mode: ScreenMode.inline,
      size: (20, 4),
      history: [r'$ app'],
    );
    expect(t.lines, [r'$ app', 'row 0', 'row 1', '']);
    expect(t.scrollback, isEmpty);
    rows.value = 4;
    await t.pump();
    expect(t.scrollback, [r'$ app']);
    expect(t.lines, ['row 0', 'row 1', 'row 2', 'row 3']);
    await t.press('ctrl+c');
    expect(t.isRunning, isFalse);
    expect(t.terminal.closed, isTrue);
    // the cursor goes to the line below, which scrolls the screen
    expect(t.scrollback, [r'$ app', 'row 0']);
    expect(t.lines, ['row 1', 'row 2', 'row 3', '']);
    expect(t.cursor, (0, 3));
  });

  testTwk('frames are capped at maxFps on the fake clock: setState calls '
      'between two frames make one build, a frame gap after the last', (
    t,
  ) async {
    final key = GlobalKey<CounterState>();
    await t.pumpWidget(
      Counter(key: key, t.clock),
      maxFps: 20,
      duration: Duration.zero,
    );
    final state = key.currentState!;
    expect(state.builtAt, [Duration.zero]);
    state
      ..change()
      ..change();
    await t.pump(const Duration(milliseconds: 49));
    expect(state.builtAt, [Duration.zero]);
    await t.pump(const Duration(milliseconds: 1));
    expect(state.builtAt, [Duration.zero, const Duration(milliseconds: 50)]);
    expect(t.lines.first, 'count 2');
    // a change long after the last frame builds at once
    await t.pump(const Duration(seconds: 1));
    state.change();
    await t.pump(Duration.zero);
    expect(state.builtAt.last, const Duration(milliseconds: 1050));
  });

  testTwk('pump with no duration moves the clock on by a frame gap: a frame '
      'asked for before it has run', (t) async {
    final key = GlobalKey<CounterState>();
    await t.pumpWidget(Counter(key: key, t.clock), maxFps: 50);
    expect(t.clock.elapsed, const Duration(milliseconds: 20));
    key.currentState!.change();
    await t.pump();
    expect(t.lines.first, 'count 1');
    expect(t.clock.elapsed, const Duration(milliseconds: 40));
  });

  testTwk("the app's timers fire only as the clock reaches them", (t) async {
    await t.pumpWidget(const Delayed(Duration(seconds: 1)));
    expect(t.lines.first, 'waiting');
    await t.pump(const Duration(milliseconds: 900));
    expect(t.lines.first, 'waiting');
    await t.pump(const Duration(milliseconds: 100));
    await t.pump();
    expect(t.lines.first, 'fired');
  });

  testTwk('pumpWidget again shows the new widget, keeping the state of the '
      'widgets that match, and given another size resizes first', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(Echo(events), size: (10, 2));
    await t.type('ab');
    final others = <InputEvent>[];
    await t.pumpWidget(Echo(others), size: (12, 3));
    expect(events.last, const ResizeEvent(12, 3));
    expect(t.lines, ['ab', '', ''], reason: 'the state kept');
    await t.pumpWidget(column([const Text('top'), Echo(events)]));
    expect(t.lines, ['top', '', '']);
    await expectLater(
      t.pumpWidget(const Text('x'), mode: ScreenMode.inline),
      throwsArgumentError,
    );
  });

  testTwk('a resize reaches the app as an event and the next frame paints '
      'the whole screen at the new size', (t) async {
    final events = <InputEvent>[];
    await t.pumpWidget(Echo(events), size: (10, 2));
    await t.type('hi');
    await t.pump();
    await t.resize(6, 3);
    expect(events.last, const ResizeEvent(6, 3));
    await t.pump();
    expect(t.lines, ['hi', '', '']);
  });

  testTwk('an error that ends the app is thrown by the call during which it '
      'ended; the app is over then', (t) async {
    await t.pumpWidget(
      InputListener(
        onEvent: (e) => throw StateError('no input'),
        child: const Text('x'),
      ),
    );
    await expectLater(
      t.type('a'),
      throwsA(
        isA<WidgetError>().having((e) => e.error, 'error', isStateError),
      ),
    );
    expect(t.isRunning, isFalse);
    expect(t.terminal.closed, isTrue);
    expect(() => t.type('b'), throwsStateError);
    await t.quit();
  });

  testTwk('a build that fails is logged, written to stderr once the app '
      'ended, and shown in place', (t) async {
    await t.pumpWidget(const Broken(), size: (20, 2));
    expect(t.cell(0, 0).bg, Color.red);
    expect(t.logs.records.single.message, 'Broken failed to build');
    expect(t.stderrLines, isEmpty);
    await t.quit();
    expect(t.stderrLines, contains(contains('Broken failed to build')));
  });

  testTwk('quit runs the app to its end: the terminal restored, the tree '
      'unmounted', (t) async {
    var disposed = false;
    await t.pumpWidget(
      Delayed(const Duration(seconds: 1), onDispose: () => disposed = true),
    );
    await t.quit();
    expect(t.isRunning, isFalse);
    expect(t.terminal.closed, isTrue);
    expect(disposed, isTrue);
    await t.quit();
  });

  testTwk('quit runs the clock on, frame gap by frame gap, while the app '
      'still writes what it committed to a slow terminal', (t) async {
    final items = ValueNotifier<List<int>>([]);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: items,
        builder: (_, _) => Static(
          items: items.value,
          builder: (_, i) => Text('line $i'),
        ),
      ),
      mode: ScreenMode.inline,
    );
    // more rows than one frame commits, each write flushed 0.1 s late
    t.terminal.holdFlush = t.clock.run(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    items.value = [for (var i = 0; i < 300; i++) i];
    await t.pump();
    expect(t.isRunning, isTrue);
    final before = t.clock.elapsed;
    await t.quit();
    expect(t.isRunning, isFalse);
    expect(t.terminal.closed, isTrue);
    expect(
      t.clock.elapsed - before,
      greaterThanOrEqualTo(const Duration(milliseconds: 50)),
    );
    expect(
      [
        for (final l in t.vt.lines)
          if (l.startsWith('line ')) l,
      ],
      [for (var i = 0; i < 300; i++) 'line $i'],
    );
  });

  testTwk('quit fails when the app has not ended 100 frames after it was '
      'asked to', (t) async {
    final items = ValueNotifier<List<int>>([]);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: items,
        builder: (_, _) => Static(
          items: items.value,
          builder: (_, i) => Text('line $i'),
        ),
      ),
      mode: ScreenMode.inline,
    );
    // a terminal that takes no more: the rows of the second frame wait
    final hold = Completer<void>();
    t.terminal.holdFlush = hold.future;
    items.value = [for (var i = 0; i < 300; i++) i];
    await t.pump();
    final before = t.clock.elapsed;
    await expectLater(
      t.quit(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'the app did not end within 100 frames of quit',
        ),
      ),
    );
    expect(t.isRunning, isTrue);
    expect(t.clock.elapsed - before, const Duration(microseconds: 99 * 16666));
    hold.complete();
    await t.quit();
    expect(t.isRunning, isFalse);
  });

  testTwk('pumpUntilIdle pumps until a frame gap passes without a frame '
      'and no timer of the app waits', (t) async {
    await t.pumpWidget(
      const Delayed(Duration(milliseconds: 100)),
      size: (10, 1),
    );
    expect(t.lines, ['waiting']);
    await t.pumpUntilIdle();
    expect(t.lines, ['fired']);
    expect(t.clock.pendingTimers, 0);
    // the frame at 100 ms is seen by the gap ending at 7 × 16.666 ms, the
    // next gap passes without one
    expect(t.clock.elapsed, const Duration(microseconds: 8 * 16666));
    await t.type('x');
    await t.pumpUntilIdle();
    expect(t.clock.elapsed, const Duration(microseconds: 9 * 16666));
  });

  testTwk('pumpUntilIdle fails on an app that keeps changing the screen, '
      'naming the frames it wrote and the timers that wait', (t) async {
    await t.pumpWidget(
      const TickingCounter(Duration(milliseconds: 100)),
      size: (10, 1),
    );
    final error = await t
        .pumpUntilIdle(timeout: const Duration(seconds: 1))
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<TestFailure>());
    final lines = (error! as TestFailure).message!.split('\n');
    expect(
      lines.first,
      'pumpUntilIdle: the app is still busy after 1.000 s: it wrote 10 '
      'frames, and 1 timer waits, the next due in 0.083 s',
    );
    expect(lines.skip(1).take(5), [
      '',
      'screen 10×1:',
      '0│tick 10',
      '',
      'render tree:',
    ]);
    expect(lines[6], startsWith('_RenderView'));
    expect(t.clock.elapsed, const Duration(microseconds: 16666 + 1000000));
  });

  testTwk('pumpUntilIdle fails while a timer keeps waiting, though no frame '
      'changes the screen', (t) async {
    await t.pumpWidget(
      const TickingCounter(Duration(seconds: 1), shown: false),
      size: (10, 1),
    );
    await expectLater(
      t.pumpUntilIdle(timeout: const Duration(milliseconds: 500)),
      throwsA(
        isA<TestFailure>().having(
          (e) => e.message,
          'message',
          startsWith(
            'pumpUntilIdle: the app is still busy after 0.500 s: it wrote no '
            'frame, and 1 timer waits, the next due in 0.483 s\n',
          ),
        ),
      ),
    );
  });

  testTwk('act runs its function in the zone of the app, whose timers '
      'then wait for the clock, and pumps a frame that shows what it '
      'changed', (t) async {
    final count = ValueNotifier(0);
    await t.pumpWidget(
      ValueListenableBuilder(
        valueListenable: count,
        builder: (context, value, _) => Text('$value'),
      ),
      size: (4, 1),
    );
    await t.act(() {
      count.value = 1;
      Timer(const Duration(seconds: 1), () => count.value = 2);
    });
    expect(t.lines, ['1']);
    await t.pump(const Duration(seconds: 1));
    expect(t.lines, ['2']);
    expect(() => t.act(() => throw StateError('no')), throwsStateError);
  });

  testTwk('written is what the app wrote, as text: every frame, or the '
      'frames from one on', (t) async {
    await t.pumpWidget(const Text('one'), size: (6, 1));
    expect(t.written(), contains('one'));
    final from = t.terminal.frames.length;
    await t.pumpWidget(const Text('two'));
    expect(t.written(since: from), contains('two'));
    expect(t.written(since: from), isNot(contains('one')));
    final after = t.terminal.frames.length;
    await t.pump();
    expect(t.written(since: after), isEmpty, reason: 'nothing changed');
  });

  testTwk('without an app the tester has nothing to drive', (t) {
    expect(t.pump, throwsStateError);
    expect(() => t.type('a'), throwsStateError);
    expect(() => t.lines, throwsStateError);
    expect(() => t.act(() {}), throwsStateError);
    expect(t.written, throwsStateError);
  });

  testTwk('the app reads none of the environment of the shell that runs the '
      'tests, only what pumpWidget gives it', (t) async {
    await t.pumpWidget(const Text('app'), size: (6, 1));
    expect(t.binding.twkApp.environment, isEmpty);
    expect(t.binding.screenReader, isFalse);
    expect(t.binding.twkApp.framesInRow, isFalse);
    expect(t.binding.debug.keys, isFalse);
    expect(t.lines, ['app']);
  });

  testTwk("an environment given to pumpWidget is the app's", (t) async {
    await t.pumpWidget(
      const Text('app'),
      size: (6, 2),
      environment: const {'TWK_SCREEN_READER': '1', 'TWK_DEBUG': 'keys'},
    );
    expect(t.binding.screenReader, isTrue);
    expect(t.binding.debug.keys, isTrue);
  });
}
