// The terminal's palette: the probe asks for its first 16 entries (OSC 4)
// with the rest, keeps those answered, asks for them again after the color
// scheme changed, and an app blends palette colors with them.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' show FakeClock;

import 'fake_link.dart';
import 'on_clock.dart';

const _options = TerminalOptions(probeTimeout: Duration(seconds: 5));

/// DA1, the probe's last answer.
const _da1 = '\x1b[?62;22c';

/// The probe's question about the palette, every entry in one sequence.
const _query =
    '\x1b]4;0;?;1;?;2;?;3;?;4;?;5;?;6;?;7;?;'
    '8;?;9;?;10;?;11;?;12;?;13;?;14;?;15;?\x1b\\';

/// The clock the terminals and the app run on: their timers fire as the
/// test moves it on, what their link is given comes in as it flushes.
late FakeClock _clock;

/// A terminal on [_clock] over a link whose probe gets [answers]; closed
/// when the test ends.
Future<(Terminal, FakeLink)> _open(String answers) async {
  final link = FakeLink()..type(answers);
  return (await _clock.open(link, _options), link);
}

void main() {
  setUp(() => _clock = FakeClock());

  test('the probe asks for the 16 entries in one OSC 4 before DA1 and '
      'keeps those answered', () async {
    final (term, link) = await _open(
      '\x1b]4;1;rgb:f3f3/8b8b/a8a8\x1b\\'
      '\x1b]4;4;rgb:89/b4/fa\x07'
      '\x1b]4;200;rgb:0000/0000/0000\x1b\\' // not asked: left out
      '$_da1',
    );
    final asked = link.text.indexOf(_query);
    expect(asked, greaterThan(link.text.indexOf('\x1b]11;?\x1b\\')));
    expect(asked, lessThan(link.text.indexOf('\x1b[c')));
    expect(term.info.palette, {1: 0xf38ba8, 4: 0x89b4fa});
    expect(term.info.answeredQueries, isTrue);
    expect(() => term.info.palette[2] = 0, throwsUnsupportedError);
  });

  test('a terminal that answers no entry: none kept, and the probe ends '
      'with DA1 as before', () async {
    final (term, _) = await _open(_da1);
    expect(term.info.palette, isEmpty);
    expect(term.info.answeredQueries, isTrue);
    expect(_clock.elapsed, lessThan(_options.probeTimeout));
  });

  test('after the color scheme changed the entries the terminal told are '
      'asked for again, and come as ColorReports', () async {
    final (term, link) = await _open(
      '\x1b[?2031;2\$y'
      '\x1b]11;rgb:1010/1212/1818\x1b\\'
      '\x1b]4;4;rgb:89/b4/fa\x1b\\\x1b]4;1;rgb:f3/8b/a8\x1b\\'
      '$_da1',
    );
    final reports = <ColorReport>[];
    final sub = term.events.listen((e) {
      if (e is ColorReport) {
        reports.add(e);
      }
    });
    addTearDown(sub.cancel);
    final before = link.text.length;
    link.type('\x1b[?997;2n');
    await _clock.flushMicrotasks();
    expect(link.text.indexOf('\x1b]4;', before), greaterThanOrEqualTo(before));
    expect(
      link.text.substring(before),
      contains('\x1b]11;?\x1b\\\x1b]4;4;?;1;?\x1b\\'),
    );
    link.type('\x1b]4;4;rgb:1e/66/f5\x1b\\');
    await _clock.flushMicrotasks();
    expect(
      [for (final r in reports) (r.which, r.index, r.rgb)],
      [(4, 4, 0x1e66f5)],
    );
  });

  test("an app blends palette colors with the terminal's entries, and "
      'repaints with one it reports later', () async {
    final term = HeadlessTerminal(width: 4, height: 1, palette: {4: 0x89b4fa});
    final app = TwkApp(
      term,
      maxFps: 1000,
      clock: _clock.stopwatch,
      environment: const {},
    );
    final styles = app.screen.styles;
    expect((styles.paletteRgb(4), styles.paletteRgb(1)), (0x89b4fa, 0xcd0000));
    const glass = Pen(bg: Color.blue, bgAlpha: 255 ~/ 2);
    final paint = RenderParagraph([('ab', glass)]);
    final done = _clock.run(() => app.run(paint, (_) {}));
    await _clock.elapse(const Duration(milliseconds: 30));
    expect(term.frames, hasLength(1));
    String last() => String.fromCharCodes(term.frames.last);
    // half the terminal's blue over its unknown (black) background
    expect(last(), contains('48;2;68;90;125'));
    term.type('\x1b]4;4;rgb:1e/66/f5\x1b\\');
    await _clock.elapse(const Duration(milliseconds: 30));
    expect(term.frames, hasLength(2), reason: 'a repaint');
    expect(styles.paletteRgb(4), 0x1e66f5);
    expect(last(), contains('48;2;15;51;122'));
    app.quit();
    await _clock.elapseUntil(done);
  });
}
