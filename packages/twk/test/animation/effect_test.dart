// Effect on the fake clock: an effect run from its start to its end, a
// frame at a time, then no frame asked for; one of no duration shown at
// once. The recolorings and the colors they come to, the sweep, dissolve,
// typewriter and glitch and the cells they show at chosen times; the
// effects composed; an equal effect not run again, another one run from
// its start; the child repainting underneath.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

const black = Color.rgb(0, 0, 0);
const white = Color.rgb(255, 255, 255);

/// Starts an app at 100 frames a second, a frame each 10 ms, on a terminal
/// of [size].
Future<void> start(TwkTester t, Widget app, {(int, int) size = (20, 1)}) =>
    t.pumpWidget(app, size: size, maxFps: 100);

/// What [shot] makes of the screen after each of [count] frames.
Future<List<R>> frames<R>(TwkTester t, int count, R Function() shot) async {
  final shots = <R>[];
  for (var i = 0; i < count; i++) {
    await t.pump();
    shots.add(shot());
  }
  return shots;
}

/// What [shot] makes of the screen now and after each of [count] frames.
Future<List<R>> run<R>(TwkTester t, int count, R Function() shot) async => [
  shot(),
  ...await frames(t, count, shot),
];

/// Pumps for 10 s and expects no frame written, nor any timer waiting.
Future<void> expectIdle(TwkTester t) async {
  expect(t.clock.pendingTimers, 0);
  final written = t.frames.length;
  await t.pump(const Duration(seconds: 10));
  expect(t.frames, hasLength(written));
  expect(t.clock.pendingTimers, 0);
}

/// [count] rows of [char], [width] wide, white on black.
Widget rows(String char, {int count = 3, int width = 20}) => Column(
  children: [
    for (var i = 0; i < count; i++)
      Text(
        char * width,
        style: const Style(fg: white, bg: black),
      ),
  ],
);

/// [child] through [effect], over [under].
Widget over(Widget under, CellEffect? effect, Widget child) => Stack(
  children: [
    under,
    Effect(effect: effect, child: child),
  ],
);

/// How many cells of the screen show [char].
int countOf(TwkTester t, String char) =>
    t.lines.join().split('').where((c) => c == char).length;

/// The red of the text color of the cell at [x], [y].
int redAt(TwkTester t, int x, [int y = 0]) => t.cell(x, y).fg >> 16 & 0xFF;

/// The text of the first line and the red of the color of its first
/// cell, null while it shows none.
(String, int?) redText(TwkTester t) {
  final line = t.lines.first;
  return (line, line.isEmpty ? null : redAt(t, 0));
}

Color invert(Color c) => Color.rgb(255 - c.r, 255 - c.g, 255 - c.b);

void main() {
  group('recolors', () {
    testTwk('dim, at once without a duration, and then no frame asked for', (
      t,
    ) async {
      await start(
        t,
        const Effect(
          effect: CellEffect.dim(),
          child: Text(
            'ab',
            style: Style(fg: white, bg: Color.rgb(200, 100, 0)),
          ),
        ),
      );
      expect(t.lines, ['ab']);
      expect(t, styleAt(0, 0, hasFg(const Color.rgb(128, 128, 128))));
      expect(t, styleAt(1, 0, hasBg(const Color.rgb(100, 50, 0))));
      await expectIdle(t);
    });

    testTwk('dim makes text faint whose color the terminal has not told, '
        'from half the way on', (t) async {
      await start(
        t,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Effect(effect: CellEffect.dim(amount: 0.4), child: Text('ab')),
            Effect(effect: CellEffect.dim(), child: Text('ab')),
          ],
        ),
        size: (4, 2),
      );
      expect(t, isNot(styleAt(0, 0, hasAttr(Attr.dim))));
      expect(t, styleAt(0, 1, hasAttr(Attr.dim)));
    });

    testTwk('desaturate takes colors to the gray of their lightness; tint '
        'toward its color, a palette color as the terminal shows it', (
      t,
    ) async {
      await start(
        t,
        const Row(
          children: [
            Effect(
              effect: CellEffect.desaturate(),
              child: Text(
                'a',
                style: Style(
                  fg: Color.rgb(0, 255, 0),
                  bg: Color.rgb(255, 0, 0),
                ),
              ),
            ),
            Effect(
              effect: CellEffect.tint(Color.rgb(0, 0, 255)),
              child: Text(
                'b',
                style: Style(fg: white, bg: black),
              ),
            ),
            Effect(
              effect: CellEffect.tint(Color.blue, amount: 1),
              child: Text('c', style: Style(bg: black)),
            ),
          ],
        ),
        size: (3, 1),
      );
      expect(t, styleAt(0, 0, hasFg(const Color.rgb(150, 150, 150))));
      expect(t, styleAt(0, 0, hasBg(const Color.rgb(76, 76, 76))));
      expect(t, styleAt(1, 0, hasFg(const Color.rgb(128, 128, 255))));
      expect(t, styleAt(1, 0, hasBg(const Color.rgb(0, 0, 128))));
      // xterm's blue
      expect(t, styleAt(2, 0, hasBg(const Color.rgb(0, 0, 238))));
    });

    testTwk("tint toward a palette color takes the terminal's own, also "
        'once it tells another (OSC 4) after the tint has ended', (t) async {
      await start(
        t,
        const Effect(
          effect: CellEffect.tint(Color.blue),
          child: Text(
            'a',
            style: Style(fg: white, bg: black),
          ),
        ),
        size: (1, 1),
      );
      // halfway to xterm's blue, 0x0000ee
      expect(t, styleAt(0, 0, hasBg(const Color.rgb(0, 0, 119))));
      expect(t, styleAt(0, 0, hasFg(const Color.rgb(128, 128, 247))));
      // a themed terminal's blue
      await t.input('\x1b]4;4;rgb:89/b4/fa\x1b\\'.codeUnits);
      await t.pump();
      expect(t, styleAt(0, 0, hasBg(const Color.rgb(69, 90, 125))));
      expect(t, styleAt(0, 0, hasFg(const Color.rgb(196, 218, 253))));
    });

    testTwk('grade maps the colors by its function, from none of the way to '
        'all of it over its run, and stays at its end', (t) async {
      await start(
        t,
        const Effect(
          effect: CellEffect.grade(
            invert,
            duration: Duration(milliseconds: 40),
          ),
          child: Text(
            'ab',
            style: Style(fg: white, bg: black),
          ),
        ),
      );
      expect(await run(t, 4, () => redAt(t, 0)), [255, 191, 128, 64, 0]);
      await expectIdle(t);
      expect(redAt(t, 0), 0);
      expect(t, styleAt(0, 0, hasBg(white)));
    });

    testTwk('scanlines darken every other row', (t) async {
      await start(
        t,
        Effect(
          effect: const CellEffect.scanlines(),
          child: Column(
            children: [
              for (var i = 0; i < 3; i++)
                const Text('ab', style: Style(bg: Color.rgb(200, 200, 200))),
            ],
          ),
        ),
        size: (2, 3),
      );
      expect(t, styleAt(0, 0, hasBg(const Color.rgb(200, 200, 200))));
      expect(t, styleAt(0, 1, hasBg(const Color.rgb(140, 140, 140))));
      expect(t, styleAt(1, 2, hasBg(const Color.rgb(200, 200, 200))));
    });
  });

  group('shares of the cells', () {
    const child = Text(
      'abcdefgh',
      style: Style(fg: white, bg: Color.rgb(0, 0, 200)),
    );
    final under = Text(
      'o' * 8,
      style: const Style(fg: white, bg: black),
    );

    testTwk('sweep shows the child up to its front, its colors coming in '
        'from the background under it over the edge, what is under it '
        'beyond', (t) async {
      await start(
        t,
        over(
          under,
          const CellEffect.sweep(edge: 2, duration: Duration(milliseconds: 40)),
          child,
        ),
        size: (8, 1),
      );
      expect(await run(t, 2, () => t.lines.single), [
        'oooooooo',
        'abcooooo',
        'abcdeooo',
      ]);
      // half way through the edge
      expect(t, styleAt(4, 0, hasBg(const Color.rgb(0, 0, 100))));
      expect(t, styleAt(4, 0, hasFg(const Color.rgb(128, 128, 128))));
      expect(t, styleAt(3, 0, hasBg(const Color.rgb(0, 0, 200))));
      expect(await frames(t, 2, () => t.lines.single), [
        'abcdefgh',
        'abcdefgh',
      ]);
      expect(t, styleAt(7, 0, hasBg(const Color.rgb(0, 0, 200))));
      await expectIdle(t);
    });

    testTwk('sweep from the right comes in from the right', (t) async {
      await start(
        t,
        over(
          under,
          const CellEffect.sweep(
            from: Alignment.centerRight,
            edge: 2,
            duration: Duration(milliseconds: 40),
          ),
          child,
        ),
        size: (8, 1),
      );
      expect(await run(t, 2, () => t.lines.single), [
        'oooooooo',
        'ooooofgh',
        'ooodefgh',
      ]);
    });

    testTwk('dissolve shows more of the cells each frame, every cell the '
        "child's or what is under it, then the child as it paints", (
      t,
    ) async {
      await start(
        t,
        over(
          rows('o'),
          const CellEffect.dissolve(duration: Duration(milliseconds: 40)),
          rows('n'),
        ),
        size: (20, 3),
      );
      final shots = await run(t, 4, () => (countOf(t, 'o'), countOf(t, 'n')));
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

    testTwk('typewriter shows the cells one after another, the next to come '
        'in reversed as a cursor', (t) async {
      await start(
        t,
        over(
          const Text('xxxxx'),
          const CellEffect.typewriter(duration: Duration(milliseconds: 50)),
          const Text('abcde'),
        ),
        size: (5, 1),
      );
      expect(t.lines, ['axxxx']);
      expect(t, styleAt(0, 0, hasAttr(Attr.reverse)));
      expect(await frames(t, 2, () => t.lines.single), ['abxxx', 'abcxx']);
      expect(t, isNot(styleAt(1, 0, hasAttr(Attr.reverse))));
      expect(t, styleAt(2, 0, hasAttr(Attr.reverse)));
      await frames(t, 3, () {});
      expect(t.lines, ['abcde']);
      expect(t, isNot(styleAt(4, 0, hasAttr(Attr.reverse))));
      await expectIdle(t);
    });

    testTwk('glitch puts symbols in a scattered share of the cells, others '
        'each 40 ms, ever fewer until none', (t) async {
      await start(
        t,
        Effect(
          effect: const CellEffect.glitch(
            amount: 0.5,
            duration: Duration(milliseconds: 200),
          ),
          child: rows('a'),
        ),
        size: (20, 3),
      );
      final first = t.lines.join();
      final glitched = await run(t, 20, () => 60 - countOf(t, 'a'));
      expect(glitched.first, inInclusiveRange(15, 45));
      expect(glitched[10], lessThan(glitched.first));
      expect(glitched.last, 0);
      expect(
        first.split('').where((c) => c != 'a'),
        everyElement(isIn(r'!#$%&*+/<=>?@\^_|~'.split(''))),
      );
      await expectIdle(t);
    });

    testTwk('the same glitch again glitches the same cells; another seed '
        'others', (t) async {
      final seed = ValueNotifier(0);
      await start(
        t,
        ValueListenableBuilder(
          valueListenable: seed,
          builder: (_, seed, _) => Effect(
            key: ValueKey(seed),
            effect: CellEffect.glitch(
              amount: 0.5,
              seed: seed ~/ 2,
              duration: const Duration(milliseconds: 200),
            ),
            child: rows('a'),
          ),
        ),
        size: (20, 3),
      );
      final first = t.lines;
      // a new key runs it again
      seed.value = 1;
      await t.pump();
      expect(t.lines, first);
      seed.value = 2;
      await t.pump();
      expect(t.lines, isNot(first));
    });
  });

  group('composed', () {
    const d40 = Duration(milliseconds: 40);
    const d60 = Duration(milliseconds: 60);

    test('one after another takes as long as they all do; at once, as the '
        'longest; backwards as long; after a delay, as long and the delay', () {
      const a = CellEffect.dissolve(duration: d40);
      const b = CellEffect.dim(duration: d60);
      expect(const CellEffect.sequence([a, b]).duration, ms * 100);
      expect(const CellEffect.parallel([a, b]).duration, d60);
      expect(a.reversed.duration, d40);
      expect(a.delayed(ms * 20).duration, d60);
      expect(const CellEffect.dim().duration, Duration.zero);
    });

    test('equal effects are the same effect', () {
      expect(
        const CellEffect.dissolve(duration: d40),
        CellEffect.dissolve(duration: ms * 40),
      );
      expect(
        const CellEffect.dissolve(duration: d40),
        isNot(const CellEffect.dissolve(duration: d60)),
      );
      expect(
        const CellEffect.dissolve(),
        isNot(const CellEffect.dissolve(curve: Curves.easeIn)),
      );
      expect(const CellEffect.dim(), isNot(const CellEffect.desaturate()));
      expect(
        const CellEffect.tint(white),
        isNot(const CellEffect.tint(black)),
      );
      expect(
        CellEffect.sequence([
          CellEffect.dim(duration: ms * 40),
          CellEffect.tint(white, duration: ms * 40),
        ]),
        const CellEffect.sequence([
          CellEffect.dim(duration: d40),
          CellEffect.tint(white, duration: d40),
        ]),
      );
      expect(
        const CellEffect.sequence([CellEffect.dim()]),
        isNot(const CellEffect.parallel([CellEffect.dim()])),
      );
      const dissolve = CellEffect.dissolve(duration: d40);
      expect(dissolve.reversed, dissolve.reversed);
      expect(dissolve.reversed.reversed, dissolve);
      expect(dissolve.delayed(d40), dissolve.delayed(d40));
      expect(dissolve.delayed(d40), isNot(dissolve.delayed(d60)));
      expect(
        const CellEffect.grade(invert).hashCode,
        const CellEffect.grade(invert).hashCode,
      );
    });

    test('equal composed effects have equal hashes', () {
      List<CellEffect> two() => [
        CellEffect.dim(duration: ms * 40),
        CellEffect.tint(white, duration: ms * 40),
      ];
      expect(
        CellEffect.sequence(two()).hashCode,
        CellEffect.sequence(two()).hashCode,
      );
      expect(
        CellEffect.parallel(two()).hashCode,
        CellEffect.parallel(two()).hashCode,
      );
      final dissolve = CellEffect.dissolve(duration: ms * 40);
      final again = CellEffect.dissolve(duration: ms * 40);
      expect(dissolve.reversed.hashCode, again.reversed.hashCode);
      expect(
        dissolve.delayed(ms * 10).hashCode,
        again.delayed(ms * 10).hashCode,
      );
    });

    testTwk('one after another: each from where the one before it ends, not '
        'at all until then, and as it is at its end once it has ended', (
      t,
    ) async {
      await start(
        t,
        const Effect(
          effect: CellEffect.sequence([
            CellEffect.dim(amount: 1, duration: Duration(milliseconds: 20)),
            CellEffect.typewriter(
              cursor: false,
              duration: Duration(milliseconds: 30),
            ),
          ]),
          child: Text(
            'abc',
            style: Style(fg: white, bg: black),
          ),
        ),
        size: (3, 1),
      );
      expect(await run(t, 5, () => redText(t)), [
        ('abc', 255),
        ('abc', 128),
        ('', null),
        ('a', 0),
        ('ab', 0),
        ('abc', 0),
      ]);
      await expectIdle(t);
    });

    testTwk('at once: each shown after those before it', (t) async {
      await start(
        t,
        const Effect(
          effect: CellEffect.parallel([
            CellEffect.typewriter(
              cursor: false,
              duration: Duration(milliseconds: 40),
            ),
            CellEffect.dim(amount: 1, duration: Duration(milliseconds: 20)),
          ]),
          child: Text(
            'abcd',
            style: Style(fg: white, bg: black),
          ),
        ),
        size: (4, 1),
      );
      expect(await run(t, 4, () => redText(t)), [
        ('', null),
        ('a', 128),
        ('ab', 0),
        ('abc', 0),
        ('abcd', 0),
      ]);
    });

    testTwk('backwards: a dissolve that takes the child out, and leaves what '
        'is under it', (t) async {
      await start(
        t,
        over(
          rows('o'),
          const CellEffect.dissolve(
            duration: Duration(milliseconds: 40),
          ).reversed,
          rows('n'),
        ),
        size: (20, 3),
      );
      final news = await run(t, 4, () => countOf(t, 'n'));
      expect(news.first, 60);
      expect(news.last, 0);
      await expectIdle(t);
      expect(countOf(t, 'o'), 60);
    });

    testTwk('after a delay: as it is at its start until then', (t) async {
      await start(
        t,
        over(
          rows('o'),
          const CellEffect.dissolve(
            duration: Duration(milliseconds: 20),
          ).delayed(const Duration(milliseconds: 20)),
          rows('n'),
        ),
        size: (20, 3),
      );
      final news = await run(t, 4, () => countOf(t, 'n'));
      expect(news.sublist(0, 3), [0, 0, 0]);
      expect(news[3], inInclusiveRange(15, 45));
      expect(news[4], 60);
    });
  });

  testTwk('an equal effect given again is not run again, another one is run '
      'from its start, and none shows the child as it paints', (t) async {
    // built again each time, with a new number
    final effect = ValueNotifier<(int, CellEffect?)>((
      0,
      const CellEffect.dissolve(duration: Duration(milliseconds: 40)),
    ));
    await start(
      t,
      ValueListenableBuilder(
        valueListenable: effect,
        builder: (_, effect, _) => over(rows('o'), effect.$2, rows('n')),
      ),
      size: (20, 3),
    );
    await frames(t, 4, () {});
    expect(countOf(t, 'n'), 60);
    effect.value = (1, CellEffect.dissolve(duration: ms * 40));
    await t.pump();
    expect(countOf(t, 'n'), 60);
    await expectIdle(t);
    effect.value = (
      2,
      const CellEffect.dissolve(duration: Duration(milliseconds: 40)).reversed,
    );
    await t.pump();
    expect(countOf(t, 'n'), 60);
    await frames(t, 4, () {});
    expect(countOf(t, 'n'), 0);
    effect.value = (3, null);
    await t.pump();
    expect(countOf(t, 'n'), 60);
    await expectIdle(t);
  });

  testTwk('onEnd is called once a run ends', (t) async {
    var ends = 0;
    await start(
      t,
      Effect(
        effect: const CellEffect.dissolve(duration: Duration(milliseconds: 40)),
        onEnd: () => ends++,
        child: rows('n'),
      ),
      size: (20, 3),
    );
    await frames(t, 3, () {});
    expect(ends, 0);
    await t.pump();
    expect(ends, 1);
    await expectIdle(t);
    expect(ends, 1);
  });

  testTwk('the child repaints underneath, shown through the effect as it '
      'does', (t) async {
    await start(
      t,
      const Box(
        style: Style(bg: black),
        child: Effect(
          effect: CellEffect.dim(),
          child: Spinner(
            style: Style(fg: white, bg: Color.rgb(0, 0, 200)),
          ),
        ),
      ),
      size: (3, 1),
    );
    final first = t.lines.single;
    for (var step = 0; step < 3; step++) {
      expect(t, styleAt(0, 0, hasBg(const Color.rgb(0, 0, 100))));
      expect(t, styleAt(0, 0, hasFg(const Color.rgb(128, 128, 128))));
      await t.pump(ms * 80);
    }
    expect(t.lines.single, isNot(first));
  });

  testTwk('without an effect the child shows as it paints', (t) async {
    await start(
      t,
      over(
        const Text('xxxx'),
        null,
        const Text('ab', style: Style(fg: white)),
      ),
      size: (4, 1),
    );
    expect(t.lines, ['abxx']);
    expect(t, styleAt(0, 0, hasFg(white)));
    await expectIdle(t);
  });

  testTwk('without an effect a repaint boundary in the child repaints on its '
      'own under a sibling over it', (t) async {
    await start(
      t,
      const Stack(
        children: [
          Effect(
            effect: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [Spinner(), Text('ab')],
            ),
          ),
          Text('x'),
        ],
      ),
      size: (3, 1),
    );
    for (var step = 0; step < 3; step++) {
      expect(t.lines, ['xab']);
      await t.pump(ms * 80);
    }
  });

  testTwk("a filter of one's own reads what the child painted in a cell and "
      'what was under it', (t) async {
    final seen = <(int, int, String, String)>{};
    await start(
      t,
      over(
        const Text('xy'),
        _Inspect(seen),
        const Text('a', style: Style(fg: Color.red)),
      ),
      size: (2, 1),
    );
    expect(seen, {
      (0, 0, 'a', 'x'),
    });
    expect(t.lines, ['xy'], reason: 'the filter shows what was under it');
  });

  testTwk('sweep makes text faint whose color the terminal has not told on '
      'the first half of its edge', (t) async {
    await start(
      t,
      over(
        const Text('oooooooo'),
        const CellEffect.sweep(duration: Duration(milliseconds: 40)),
        const Text('abcdefgh'),
      ),
      size: (8, 1),
    );
    await frames(t, 2, () {});
    final dim = [
      for (var x = 0; x < 8; x++)
        if (t.cell(x, 0).attrs & Attr.dim != 0) t.lines.single[x],
    ];
    expect(dim, isNotEmpty);
    expect(dim.every('abcdefgh'.contains), isTrue);
  });
}

/// Writes down, for each cell it is asked about, where it is, the glyph
/// the child painted and the one under it, and shows the one under it.
final class _Inspect extends CellEffect {
  const _Inspect(this.seen);

  final Set<(int, int, String, String)> seen;

  @override
  Duration get duration => Duration.zero;

  @override
  CellFilter? at(Duration elapsed) => (cell) {
    final styles = cell.styles;
    expect(cell.childStyle, cell.style);
    expect(styles.fgOf(cell.childStyle), Color.red);
    seen.add((
      cell.x,
      cell.y,
      String.fromCharCode(cell.childGlyph),
      String.fromCharCode(cell.underGlyph),
    ));
    cell.showUnder();
  };
}
