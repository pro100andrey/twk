// The screen-reader mode: the app read out as lines of plain text through
// the emulator, no box glyphs, the focused line reversed with the cursor at
// its end; a frame writing only the lines that changed; long lines broken,
// the lines around the focused one shown when they do not fit; turned off,
// the app drawn again; the terminal keeping the mouse; and runApp reading
// an app out on a terminal in the inline mode until it ends.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';
import 'package:twk_test/vt_terminal.dart';

/// A sign-in form in a box: a title, a checkbox and two buttons.
final class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

final class _FormState extends State<_Form> {
  var _remember = false;

  @override
  Widget build(BuildContext context) => Box(
    border: const Border.all(),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sign in'),
        Checkbox(
          value: _remember,
          onChanged: (v) => setState(() => _remember = v),
          label: 'Remember me',
        ),
        Button('OK', autofocus: true, onPressed: () {}),
        Button('Cancel', onPressed: () {}),
      ],
    ),
  );
}

/// `one`, in red once [_RecolorState.flip]ped: the same text.
final class _Recolor extends StatefulWidget {
  const _Recolor({super.key});

  @override
  State<_Recolor> createState() => _RecolorState();
}

final class _RecolorState extends State<_Recolor> {
  var _red = false;

  void flip() => setState(() => _red = !_red);

  @override
  Widget build(BuildContext context) =>
      Text('one', style: Style(fg: _red ? Color.red : null));
}

const _lines =
    'Sign in\n'
    'checkbox Remember me, not checked\n'
    'button OK\n'
    'button Cancel';

/// Whether [lines] have a glyph of the Box Drawing block.
bool _boxed(List<String> lines) =>
    lines.any((line) => line.contains(RegExp('[─-╿]')));

/// Starts [app] in the inline mode on a terminal of [size], then reads it
/// out.
Future<void> _read(TwkTester t, Widget app, (int, int) size) async {
  await t.pumpWidget(app, mode: ScreenMode.inline, size: size);
  t.binding.screenReader = true;
  await t.pump();
}

void main() {
  testTwk('an app is drawn until it is read out, then shows its lines as '
      'plain text, the region as tall as they are, the focused line '
      'reversed and the cursor at its end', (t) async {
    await t.pumpWidget(const _Form(), mode: ScreenMode.inline, size: (40, 10));
    expect(_boxed(t.lines), isTrue);
    expect(t.binding.screenReader, isFalse);
    t.binding.screenReader = true;
    await t.pump();
    expect(t, matchesScreen(_lines));
    expect(_boxed(t.lines), isFalse);
    expect(t.binding.twkApp.screen.height, 4);
    expect(t, styleAt(0, 2, hasAttr(Attr.reverse)));
    expect(t, styleAt(8, 2, hasAttr(Attr.reverse)));
    expect(t, styleAt(0, 1, isNot(hasAttr(Attr.reverse))));
    expect(t, cursorAt(9, 2));
  });

  testTwk('a frame writes the lines the focus or a build changed, and none '
      'while none changed', (t) async {
    await _read(t, const _Form(), (40, 10));
    var from = t.terminal.frames.length;
    await t.press('tab');
    await t.pump();
    var written = t.written(since: from);
    expect(written, allOf(contains('OK'), contains('Cancel')));
    expect(written, isNot(contains('Sign in')));
    expect(written, isNot(contains('Remember')));
    expect(t, cursorAt(13, 3));
    expect(t, styleAt(0, 3, hasAttr(Attr.reverse)));
    expect(t, styleAt(0, 2, isNot(hasAttr(Attr.reverse))));
    from = t.terminal.frames.length;
    await t.pump();
    expect(t.terminal.frames.length, from);
    await t.press('shift+tab');
    await t.press('shift+tab');
    await t.press('space');
    await t.pump();
    written = t.written(since: from);
    expect(written, allOf(contains('checked'), contains('Cancel')));
    expect(written, isNot(contains('Sign in')));
    expect(written, isNot(contains('OK')));
    expect(t, containsLine('checkbox Remember me, checked'));
    expect(t, cursorAt(29, 1));
  });

  testTwk('a line wider than the screen is broken at the blank that does '
      'not fit, or after the last one that does; with more rows than the '
      'region has, those of the focused line show', (t) async {
    final first = FocusNode();
    final last = FocusNode();
    addTearDown(first.dispose);
    addTearDown(last.dispose);
    await _read(
      t,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Button(
            'one two threefold four',
            focusNode: first,
            onPressed: () {},
          ),
          Button('A', onPressed: () {}),
          Button('one two three four', onPressed: () {}),
          Button('C', focusNode: last, onPressed: () {}),
        ],
      ),
      (20, 3),
    );
    expect(t, matchesScreen('button one two\nthreefold four\nbutton A'));
    last.requestFocus();
    await t.pump();
    expect(t, matchesScreen('button one two three\nfour\nbutton C'));
    expect(t, cursorAt(8, 2));
    first.requestFocus();
    await t.pump();
    expect(t, matchesScreen('button one two\nthreefold four\nbutton A'));
    expect(t, styleAt(0, 1, hasAttr(Attr.reverse)));
    expect(t, cursorAt(14, 1));
  });

  testTwk('the region fits the lines when there are fewer', (t) async {
    await _read(t, const _Form(), (40, 10));
    expect(t.binding.twkApp.screen.height, 4);
    await t.pumpWidget(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [Button('OK', autofocus: true, onPressed: () {})],
      ),
    );
    await t.pump();
    expect(t.binding.twkApp.screen.height, 1);
    expect(t, matchesScreen('button OK'));
  });

  testTwk('turned off, the app is drawn again, all of it', (t) async {
    await t.pumpWidget(const _Form(), mode: ScreenMode.inline, size: (40, 10));
    final drawn = t.lines;
    t.binding.screenReader = true;
    await t.pump();
    expect(t, matchesScreen(_lines));
    expect(t.cursorVisible, isTrue);
    t.binding.screenReader = false;
    await t.pump();
    expect(t.lines, drawn);
    expect(t.cursorVisible, isFalse);
  });

  testTwk('what of the app repaints on its own shows nothing over the lines', (
    t,
  ) async {
    final key = GlobalKey<_RecolorState>();
    await _read(
      t,
      SizedBox(
        height: 2,
        child: ListView(
          children: [
            _Recolor(key: key),
            const Text('two'),
          ],
        ),
      ),
      (20, 6),
    );
    const lines = 'list 2 items\nlistitem one\nlistitem two';
    expect(t, matchesScreen(lines));
    final from = t.terminal.frames.length;
    key.currentState!.flip();
    await t.pump();
    // the list repainted, out of the screen's cells
    expect(t.binding.twkApp.stats.lastRepaints, 1);
    expect(t.terminal.frames.length, from);
    expect(t, matchesScreen(lines));
  });

  testTwk('the terminal keeps the mouse while the app is read out', (t) async {
    await t.pumpWidget(
      Listener(onDown: (_) {}, child: const Text('click')),
      size: (20, 3),
    );
    expect(t.terminal.mouseTracking, MouseTracking.buttons);
    t.binding.screenReader = true;
    await t.pump();
    expect(t.terminal.mouseTracking, MouseTracking.off);
    expect(t, matchesScreen('click'));
  });

  test('what the layout builds, the items of a list, is read in the frame '
      'that builds it', () async {
    final clock = FakeClock();
    final term = clock.run(() => VtTerminal(height: 6));
    final done = clock.run(
      () => runApp(
        SizedBox(
          height: 3,
          child: ListView(
            autofocus: true,
            children: const [Text('a'), Text('b'), Text('c')],
          ),
        ),
        mode: ScreenMode.inline,
        terminal: term,
        maxFps: 1000,
        logs: LogSink(),
        screenReader: true,
        clock: clock.stopwatch,
      ),
    );
    await clock.elapse(const Duration(milliseconds: 30));
    expect(term.lines.take(4), [
      'list 3 items',
      'listitem a',
      'listitem b',
      'listitem c',
    ]);
    term.type('\x03');
    await clock.elapseUntil(done);
  });

  test('runApp with screenReader reads the app out on a terminal in the '
      'inline mode below its history, takes input, and leaves the lines '
      'there when it ends', () async {
    final clock = FakeClock();
    final term = clock.run(() => VtTerminal(height: 8, history: [r'$ app']));
    final done = clock.run(
      () => runApp(
        const _Form(),
        mode: ScreenMode.inline,
        terminal: term,
        maxFps: 1000,
        logs: LogSink(),
        screenReader: true,
        clock: clock.stopwatch,
      ),
    );
    Future<void> settle() => clock.elapse(const Duration(milliseconds: 30));
    await settle();
    expect(term.lines, [r'$ app', ..._lines.split('\n'), '', '', '']);
    expect(_boxed(term.lines), isFalse);
    expect((term.vt.cx, term.vt.cy), (9, 3));
    term.type('\t');
    await settle();
    expect((term.vt.cx, term.vt.cy), (13, 4));
    term.type('\x03');
    await clock.elapseUntil(done);
    expect(term.lines.take(5), [r'$ app', ..._lines.split('\n')]);
    expect(term.vt.cy, 5);
  });
}
