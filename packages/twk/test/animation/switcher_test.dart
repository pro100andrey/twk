// AnimatedSwitcher on the fake clock: a new child comes in as the old one
// goes out, faded, slid or dissolved a frame at a time, from where it was
// when it is replaced on the way; the old one dropped, and then no frame
// asked for. Opacity, Dissolve and FractionalTranslation on their own: the
// colors and glyphs they mix, two-column glyphs kept whole, a repaint
// boundary inside an Opacity mixed as it repaints on its own.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show LogLevel, Screen, kCont, kWide;
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

const black = Color.rgb(0, 0, 0);
const white = Color.rgb(255, 255, 255);

/// Starts an app at 100 frames a second, a frame each 10 ms, that shows
/// what [build] makes of the value of the notifier it returns, on a
/// terminal of [size].
Future<ValueNotifier<T>> start<T>(
  TwkTester t,
  T first,
  Widget Function(T value) build, {
  (int, int) size = (20, 1),
}) async {
  final value = ValueNotifier(first);
  await t.pumpWidget(
    ValueListenableBuilder<T>(
      valueListenable: value,
      builder: (_, v, _) => build(v),
    ),
    size: size,
    maxFps: 100,
  );
  return value;
}

/// What [shot] makes of the screen after each of [count] frames. The
/// first frame after a child changed builds with it, showing the old one
/// still; the run starts in the frame after it.
Future<List<R>> frames<R>(TwkTester t, int count, R Function() shot) async {
  final shots = <R>[];
  for (var i = 0; i < count; i++) {
    await t.pump();
    shots.add(shot());
  }
  return shots;
}

/// Pumps for 10 s and expects no frame written, nor any timer waiting.
Future<void> expectIdle(TwkTester t) async {
  expect(t.clock.pendingTimers, 0);
  final written = t.frames.length;
  await t.pump(const Duration(seconds: 10));
  expect(t.frames, hasLength(written));
  expect(t.clock.pendingTimers, 0);
}

/// The labels of the [Label]s disposed so far.
final disposed = <String>[];

/// [text] in white, keyed by it: another text is another child.
final class Label extends StatefulWidget {
  Label(this.text) : super(key: ValueKey(text));

  final String text;

  @override
  State<Label> createState() => _LabelState();
}

final class _LabelState extends State<Label> {
  @override
  void dispose() {
    disposed.add(widget.text);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Text(widget.text, style: const Style(fg: white));
}

/// [AnimatedSwitcher] of a [Label] of [text], none when null, on black.
Widget switcher(
  String? text, {
  SwitcherTransition transition = SwitcherTransition.fade,
  Duration duration = const Duration(milliseconds: 40),
}) => Box(
  style: const Style(bg: black),
  child: Align(
    alignment: Alignment.topLeft,
    child: AnimatedSwitcher(
      duration: duration,
      transition: transition,
      child: text == null ? null : Label(text),
    ),
  ),
);

/// The text of the first line and the red of the color of its first cell.
(String, int) redText(TwkTester t) =>
    (t.lines.first, t.cell(0, 0).fg >> 16 & 0xFF);

/// [count] rows of [char], [width] wide.
Widget rows(String char, {int count = 3, int width = 20}) => Column(
  children: [for (var i = 0; i < count; i++) Text(char * width)],
);

/// Expects every two-column glyph the app last painted whole: a first
/// half followed by a second half in its style, and no second half alone.
void expectWhole(TwkTester t) {
  final surface = t.binding.twkApp.screen.surface;
  final cells = surface.cells;
  final styles = surface.styles;
  for (var i = 0; i < cells.length; i++) {
    final x = i % surface.width;
    if ((cells[i] & kWide) != 0) {
      expect(x + 1, lessThan(surface.width), reason: 'a first half at $i');
      expect(cells[i + 1] & kCont, kCont, reason: 'the first half at $i');
      expect(styles[i + 1], styles[i], reason: 'the halves at $i');
    } else if ((cells[i] & kCont) != 0) {
      expect(x, greaterThan(0), reason: 'a second half at $i');
      expect(cells[i - 1] & kWide, kWide, reason: 'the second half at $i');
    }
  }
}

/// How many cells of the screen show [char].
int countOf(TwkTester t, String char) =>
    t.lines.join().split('').where((c) => c == char).length;

void main() {
  setUp(disposed.clear);

  testTwk('the first child shows at once; a new one fades in over the old '
      'one, whose text it takes from halfway, and the old one fades out and '
      'is dropped; then the app asks for no frame', (t) async {
    final text = await start(t, 'one', switcher, size: (5, 1));
    expect(t.lines, ['one']);
    expect(t.clock.pendingTimers, 0);
    text.value = 'two';
    expect(await frames(t, 5, () => redText(t)), [
      ('one', 255),
      // the old at 191 of 255, seen through the new at 64
      ('one', (191 * 191 / 255).round()),
      ('two', 128),
      ('two', 191),
      ('two', 255),
    ]);
    expect(disposed, ['one']);
    await expectIdle(t);
  });

  testTwk('a child replaced on its way in goes out from where it was', (
    t,
  ) async {
    final text = await start(t, 'one', switcher, size: (5, 1));
    text.value = 'two';
    await frames(t, 3, () {});
    expect(redText(t), ('two', 128));
    // the frame that builds with it has two at 0.75 and one at 0.25: one
    // is out a frame later, two goes out from there, its text under six's
    // until six is halfway in
    text.value = 'six';
    expect(await frames(t, 6, () => t.lines.first), [
      'two',
      'two',
      'two',
      'six',
      'six',
      'six',
    ]);
    expect(disposed, ['one', 'two']);
    await expectIdle(t);
  });

  testTwk('a child of the same type and key is updated at once; none takes '
      'no room once the old one is out', (t) async {
    final text = await start<String?>(
      t,
      'one',
      (text) => Row(
        children: [
          AnimatedSwitcher(
            duration: ms * 40,
            child: text == null ? null : Text(text),
          ),
          const Text('|'),
        ],
      ),
    );
    text.value = 'two';
    await t.pump();
    expect(t.lines, ['two|']);
    await expectIdle(t);
    text.value = null;
    await frames(t, 5, () {});
    expect(t.lines, ['|']);
    await expectIdle(t);
  });

  testTwk('slide moves the new child in from the side it says and the old '
      'one out to the other side, a share of its width each frame', (
    t,
  ) async {
    final text = await start(
      t,
      'aaaa',
      (text) => switcher(text, transition: const SwitcherTransition.slide()),
      size: (6, 1),
    );
    text.value = 'bbbb';
    expect(await frames(t, 5, () => t.lines.first), [
      'aaaa',
      'aaab',
      'aabb',
      'abbb',
      'bbbb',
    ]);
    await expectIdle(t);
  });

  testTwk('slide from the left: in from the left, out to the right', (
    t,
  ) async {
    final text = await start(
      t,
      'aaaa',
      (text) => switcher(
        text,
        transition: const SwitcherTransition.slide(from: Alignment.centerLeft),
      ),
      size: (6, 1),
    );
    text.value = 'bbbb';
    expect(await frames(t, 5, () => t.lines.first), [
      'aaaa',
      'baaa',
      'bbaa',
      'bbba',
      'bbbb',
    ]);
    await expectIdle(t);
  });

  testTwk('dissolve puts more of the new cells in place of the old ones '
      'each frame, every cell the one or the other', (t) async {
    final char = await start(
      t,
      'o',
      (char) => Box(
        style: const Style(bg: black),
        child: AnimatedSwitcher(
          duration: ms * 40,
          transition: SwitcherTransition.dissolve,
          child: SizedBox(key: ValueKey(char), child: rows(char)),
        ),
      ),
      size: (20, 3),
    );
    char.value = 'n';
    final shots = await frames(t, 5, () => (countOf(t, 'o'), countOf(t, 'n')));
    expect([for (final (o, n) in shots) o + n], everyElement(60));
    final news = [for (final (_, n) in shots) n];
    expect(news.first, 0);
    expect(news.last, 60);
    for (var i = 1; i < news.length; i++) {
      expect(news[i], greaterThan(news[i - 1]), reason: 'frame $i');
    }
    expect(news[2], inInclusiveRange(20, 40), reason: 'about half');
    await expectIdle(t);
  });

  testTwk('Opacity shows the text under it below half its opacity, seen '
      'through its background, and its own from half on, as translucent', (
    t,
  ) async {
    const gray = Color.rgb(100, 100, 100);
    final opacity = await start(
      t,
      0.25,
      (opacity) => Stack(
        children: [
          const Text(
            'cdef',
            style: Style(fg: white, bg: black),
          ),
          Opacity(
            opacity: opacity,
            child: const Text(
              'ab',
              style: Style(fg: white, bg: gray),
            ),
          ),
        ],
      ),
      size: (4, 1),
    );
    // background: 100 at 64 of 255 over 0; text: 100 at 64 over 255
    expect(t.lines, ['cdef']);
    expect(t.cell(0, 0).bg, const Color.rgb(25, 25, 25).value);
    expect(t.cell(0, 0).fg, const Color.rgb(216, 216, 216).value);
    expect(t, styleAt(2, 0, hasFg(white)));
    opacity.value = 0.75;
    await t.pump();
    // background: 100 at 191 over 0; text: 255 at 191 over that
    expect(t.lines, ['abef']);
    expect(t.cell(0, 0).bg, const Color.rgb(75, 75, 75).value);
    expect(t.cell(0, 0).fg, const Color.rgb(210, 210, 210).value);
    opacity.value = 0;
    await t.pump();
    expect(t.lines, ['cdef']);
    expect(t, styleAt(0, 0, hasBg(black)));
    opacity.value = 1;
    await t.pump();
    expect(t.lines, ['abef']);
    expect(t, styleAt(0, 0, hasBg(gray)));
  });

  testTwk('Opacity makes text faint whose color the terminal has not told', (
    t,
  ) async {
    await t.pumpWidget(
      const Opacity(opacity: 0.5, child: Text('ab')),
      size: (4, 1),
    );
    expect(t.lines, ['ab']);
    expect(t, styleAt(0, 0, hasAttr(Attr.dim)));
  });

  testTwk('Opacity keeps two-column glyphs whole: the text under it below '
      'half, its own from half on', (t) async {
    final opacity = await start(
      t,
      0.4,
      (opacity) => Stack(
        children: [
          const Text('ab中文'),
          Opacity(opacity: opacity, child: const Text('x中y')),
        ],
      ),
      size: (8, 1),
    );
    expect(t.lines, ['ab中文']);
    expectWhole(t);
    opacity.value = 0.6;
    await t.pump();
    expect(t.lines, ['x中y文']);
    expectWhole(t);
  });

  testTwk('Dissolve keeps two-column glyphs whole, taking both halves from '
      'the child or what is under it', (t) async {
    final shown = await start<double>(
      t,
      0,
      (shown) => Stack(
        children: [
          Text('中文' * 10),
          Dissolve(shown: shown, child: Text('a${'中文' * 9}b')),
        ],
      ),
      size: (40, 1),
    );
    for (var i = 1; i < 10; i++) {
      shown.value = i / 10;
      await t.pump();
      expectWhole(t);
    }
  });

  testTwk('a repaint boundary inside an Opacity is mixed as it repaints on '
      'its own', (t) async {
    await t.pumpWidget(
      const Box(
        style: Style(bg: black),
        child: Opacity(
          opacity: 0.5,
          child: Spinner(
            style: Style(fg: white, bg: Color.rgb(0, 0, 200)),
          ),
        ),
      ),
      size: (3, 1),
    );
    final first = t.lines.single;
    for (var step = 0; step < 3; step++) {
      expect(t.cell(0, 0).bg, const Color.rgb(0, 0, 100).value);
      expect(t.cell(0, 0).fg, const Color.rgb(128, 128, 178).value);
      await t.pump(ms * 80);
    }
    expect(t.lines.single, isNot(first));
  });

  testTwk('what an Opacity keeps of the cells under it lives through the '
      "screen's sweeps, as a repaint boundary in it repaints", (t) async {
    final floor = Screen.sweepFloor;
    addTearDown(() => Screen.sweepFloor = floor);
    Screen.sweepFloor = 8;
    await t.pumpWidget(
      const Box(
        // no cell but those under the Opacity has it, nor any pen, as a
        // translucent pen's style is made over what is under it
        style: Style(bg: Color.rgb(0, 200, 0), bgAlpha: 128),
        child: Opacity(
          opacity: 0.5,
          child: Spinner(
            style: Style(fg: white, bg: Color.rgb(0, 0, 200)),
          ),
        ),
      ),
      // all of it under the Opacity
      size: (1, 1),
    );
    final screen = t.binding.twkApp.screen;
    final first = t.lines.single;
    for (var step = 0; step < 6; step++) {
      // styles and glyphs no cell has: the next frames sweep them
      for (var i = 0; i < 64; i++) {
        screen.styles.style(fg: Color.rgb(step, i, 9));
        screen.glyphs.intern('a${String.fromCharCode(0x300 + i)}', 0, 2);
      }
      await t.pump(ms * 80);
      // the spinner's blue half over the green half under it
      expect(t.cell(0, 0).bg, const Color.rgb(0, 50, 100).value);
    }
    expect(screen.styles.sweeps, greaterThan(0));
    expect(screen.glyphs.sweeps, greaterThan(0));
    expect(t.lines.single, isNot(first));
    // a style kept and freed would fail an assert as it is mixed
    expect([
      for (final r in t.logs.records)
        if (r.level == LogLevel.error) r,
    ], isEmpty);
  });

  testTwk('Dissolve shows a share of its cells; one with inverse at 1 - t '
      'shows just those one without leaves out at t', (t) async {
    final shown = await start(
      t,
      0.3,
      (shown) => Stack(
        children: [
          Dissolve(shown: 1 - shown, inverse: true, child: rows('o')),
          Dissolve(shown: shown, child: rows('n')),
        ],
      ),
      size: (20, 3),
    );
    expect(countOf(t, 'o') + countOf(t, 'n'), 60);
    expect(countOf(t, 'n'), inInclusiveRange(8, 28));
    shown.value = 0;
    await t.pump();
    expect(countOf(t, 'o'), 60);
    shown.value = 1;
    await t.pump();
    expect(countOf(t, 'n'), 60);
  });

  testTwk('FractionalTranslation moves its child a share of its size, cut '
      'off at its own place', (t) async {
    final x = await start(
      t,
      0.5,
      (x) => Row(
        children: [
          const Text('['),
          FractionalTranslation(
            x: x,
            y: x,
            child: rows('ab', count: 2, width: 3),
          ),
          const Text(']'),
        ],
      ),
      size: (10, 2),
    );
    expect(t.lines, ['[      ]', '    aba']);
    x.value = -0.5;
    await t.pump();
    expect(t.lines, ['[bab   ]', '']);
  });

  test('two slides from the same side are equal, with equal hashes; from '
      'another side they differ', () {
    var right = Alignment.centerRight;
    final a = SwitcherTransition.slide(from: right);
    final b = SwitcherTransition.slide(from: right);
    expect(identical(a, b), isFalse);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    right = Alignment.centerLeft;
    expect(SwitcherTransition.slide(from: right), isNot(a));
  });

  testTwk('Opacity, Dissolve and FractionalTranslation are as big as their '
      'child, and as small as they may be without one', (t) async {
    const withChild = ValueKey('with');
    const without = ValueKey('without');
    for (final wrap in <Widget Function(Key, Widget?)>[
      (key, child) => Opacity(key: key, opacity: 0.5, child: child),
      (key, child) => Dissolve(key: key, shown: 0.5, child: child),
      (key, child) => FractionalTranslation(key: key, x: 0.5, child: child),
    ]) {
      await t.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicWidth(
              child: IntrinsicHeight(child: wrap(withChild, const Text('ab'))),
            ),
            wrap(without, null),
            const Text('end'),
          ],
        ),
        size: (6, 3),
      );
      final type = wrap(without, null).runtimeType;
      expect(
        t.rect(find.byKey(withChild)),
        (x: 0, y: 0, width: 2, height: 1),
        reason: '$type',
      );
      expect(
        t.rect(find.byKey(without)),
        (x: 0, y: 1, width: 0, height: 0),
        reason: '$type',
      );
      expect(t.lines[1], 'end', reason: '$type');
    }
  });

  testTwk('the render tree says how much of its child an Opacity and a '
      'Dissolve show, and how far a FractionalTranslation moves it', (
    t,
  ) async {
    await t.pumpWidget(
      const Column(
        children: [
          Opacity(opacity: 0.5, child: Text('a')),
          Dissolve(shown: 0.25, inverse: true, child: Text('b')),
          FractionalTranslation(x: 0.5, y: -1, child: Text('c')),
        ],
      ),
      size: (6, 3),
    );
    String described(Type type) =>
        t.renderObject<RenderObject>(find.byType(type)).describe().toString();
    expect(described(Opacity), contains('opacity: 50%'));
    expect(
      described(Dissolve),
      allOf(contains('shown: 25%'), contains('inverse: true')),
    );
    expect(
      described(FractionalTranslation),
      allOf(contains('x: 0.5'), contains('y: -1.0')),
    );
  });
}
