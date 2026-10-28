// Skeleton and Skeletonize: every cell of the child that shows something
// becomes the glyph in the muted color, the blanks kept, the layout the
// child's; read as loading, the mouse and the focus kept from it; the
// shimmer's band sweeping left to right on the fake clock, all skeletons
// on one timer, and no frame asked for when disabled, without shimmer, on
// a theme of palette colors, in the screen-reader mode or on plain output;
// the blocks of a Skeleton and its lines of text; the theme's glyph, and
// a blank in reverse video for one that is not a column wide.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/plain_lines.dart';

const ms = Duration(milliseconds: 1);

const ThemeData dark = ThemeData.dark;
final Color muted = dark.muted.fg!;
final Color bright = dark.text.fg!;

/// Pumps until the clock reads [at].
Future<void> until(TwkTester t, Duration at) => t.pump(at - t.clock.elapsed);

/// [child] at the top left, under the dark theme, an RGB one.
Widget rgb(Widget child) => Theme(
  data: dark,
  child: Align(alignment: Alignment.topLeft, child: child),
);

/// [child] at the top left, under the default theme, the terminal's
/// palette colors.
Widget palette(Widget child) =>
    Align(alignment: Alignment.topLeft, child: child);

/// The columns of row [y] whose text is in [color].
List<int> columnsIn(TwkTester t, Color color, {int y = 0, int width = 20}) => [
  for (var x = 0; x < width; x++)
    if (t.cell(x, y).fg == color.value) x,
];

/// Pumps for 10 s and expects no frame written, nor any timer waiting.
Future<void> expectIdle(TwkTester t) async {
  expect(t.clock.pendingTimers, 0);
  final written = t.frames.length;
  await t.pump(const Duration(seconds: 10));
  expect(t.frames, hasLength(written));
  expect(t.clock.pendingTimers, 0);
}

void main() {
  group('Skeletonize', () {
    testTwk('each cell of the child that shows something becomes the glyph '
        'in the muted color, the blanks kept; disabled, the child shows as '
        'it paints', (t) async {
      Widget app(bool enabled) => palette(
        Skeletonize(enabled: enabled, child: const Text('User: Alice  漢')),
      );
      await t.pumpWidget(Theme.terminal(child: app(true)), size: (20, 1));
      expect(t.lines, ['░░░░░ ░░░░░  ░░']);
      const terminal = ThemeData.terminal(Brightness.dark);
      expect(
        t,
        styleAt(
          0,
          0,
          allOf(hasFg(terminal.muted.fg!), hasFg(const Color.indexed(245))),
        ),
      );
      expect(
        t,
        styleAt(14, 0, hasFg(const Color.indexed(245))),
        reason: 'the wide glyph',
      );
      await t.pumpWidget(Theme.terminal(child: app(false)));
      expect(t.lines, ['User: Alice  漢']);
      expect(t, styleAt(0, 0, isNot(hasFg(const Color.indexed(245)))));
    });

    testTwk('keeps the background of the content, laid out as the child '
        'is', (t) async {
      const bg = Color.rgb(1, 2, 3);
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(
            const Skeletonize(
              enabled: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                gap: 2,
                children: [
                  Text('a b', style: Style(bg: bg)),
                  Text('c'),
                ],
              ),
            ),
          ),
        ),
        size: (10, 1),
      );
      expect(t.lines, ['░ ░  ░'], reason: 'a blank the child paints kept');
      expect(t, styleAt(0, 0, allOf(hasFg(muted), hasBg(bg))));
      expect(t, styleAt(1, 0, hasBg(bg)));
      expect(t.rect(find.byType(Skeletonize)).width, 6);
    });

    testTwk('read as loading while enabled, as the child once not', (
      t,
    ) async {
      Widget app(bool enabled) =>
          palette(Skeletonize(enabled: enabled, child: const Text('Alice')));
      await t.pumpWidget(Theme.terminal(child: app(true)), size: (10, 1));
      expect(t.binding.semantics.lines, ['loading']);
      await t.pumpWidget(Theme.terminal(child: app(false)));
      expect(t.binding.semantics.lines, ['Alice']);
    });

    testTwk('the mouse passes the child by and its focus nodes take no '
        'focus while enabled; disabled, both reach it', (t) async {
      var pressed = 0;
      Widget app(bool enabled) => palette(
        Skeletonize(
          enabled: enabled,
          child: Button('OK', onPressed: () => pressed++),
        ),
      );
      await t.pumpWidget(Theme.terminal(child: app(true)), size: (10, 1));
      await t.click(1, 0);
      await t.press('tab');
      await t.press('enter');
      expect(pressed, 0);
      await t.pumpWidget(Theme.terminal(child: app(false)));
      await t.click(1, 0);
      expect(pressed, 1);
      await t.press('tab');
      await t.press('enter');
      expect(pressed, 2);
    });

    testTwk('the shimmer, a band of brighter cells, sweeps from left to '
        'right over the period, a step each 50 ms, then from the left '
        'again', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(Skeletonize(enabled: true, child: Text('x' * 20))),
        ),
        size: (20, 1),
      );
      expect(Skeletonize.step, ms * 50);
      expect(SkeletonTheme.defaultPeriod, ms * 1500);
      // the band's middle at step s of 30: s / 30 of the way from 4 cells
      // before the left edge to 4 after the right one
      expect(columnsIn(t, bright), isEmpty, reason: 'off the left edge');
      expect(columnsIn(t, muted), hasLength(20));
      await until(t, ms * 50 * 14);
      expect(columnsIn(t, bright), [9], reason: 'the middle at 9.07');
      await until(t, ms * 50 * 15 - ms);
      expect(columnsIn(t, bright), [9], reason: 'still at step 14');
      await until(t, ms * 50 * 15);
      expect(columnsIn(t, bright), [9, 10], reason: 'the middle at 10');
      expect(t.lines.single, '░' * 20, reason: 'the glyph stays');
      // less bright away from the middle, the glyph's color past the band
      final dimmer = t.cell(6, 0).fg;
      expect(dimmer, isNot(muted.value));
      expect(dimmer, isNot(bright.value));
      expect(t.cell(5, 0).fg, muted.value, reason: 'past the band');
      final fronts = <int>[];
      for (var s = 16; s < 26; s++) {
        await until(t, ms * 50 * s);
        fronts.add(columnsIn(t, bright).first);
      }
      expect(fronts.first, 10);
      expect(fronts.last, 19);
      for (var i = 1; i < fronts.length; i++) {
        expect(fronts[i], greaterThanOrEqualTo(fronts[i - 1]));
      }
      await until(t, ms * 50 * 26);
      expect(
        columnsIn(t, bright),
        isEmpty,
        reason: 'leaving at the right edge',
      );
      await until(t, ms * 50 * 30);
      expect(columnsIn(t, muted), hasLength(20), reason: 'the period again');
      await until(t, ms * 50 * 44);
      expect(columnsIn(t, bright), [9]);
    });

    testTwk('every skeleton moves in the same frames on one timer, one '
        'shown later too', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(Skeletonize(enabled: true, child: Text('x' * 20))),
        ),
        size: (20, 2),
      );
      expect(t.clock.pendingTimers, 1);
      expect(t.clock.nextTimerDue, ms * 50);
      await until(t, ms * 520);
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(
            Column(
              children: [
                Skeletonize(enabled: true, child: Text('x' * 20)),
                const Skeleton(width: 20),
              ],
            ),
          ),
        ),
      );
      expect(columnsIn(t, bright, y: 1), columnsIn(t, bright));
      expect(t.clock.pendingTimers, 1);
      final written = t.frames.length;
      await until(t, ms * 1000);
      expect(t.frames, hasLength(written + 10), reason: 'a frame a step');
      expect(columnsIn(t, bright), isNotEmpty);
      expect(columnsIn(t, bright, y: 1), columnsIn(t, bright));
    });

    testTwk('a step repaints the skeleton and builds nothing below it', (
      t,
    ) async {
      var builds = 0;
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(
            Skeletonize(
              enabled: true,
              child: Builder(
                builder: (context) {
                  builds++;
                  return Text('x' * 20);
                },
              ),
            ),
          ),
        ),
        size: (20, 1),
      );
      final built = builds;
      await until(t, ms * 500);
      expect(builds, built);
      expect(columnsIn(t, bright), isNotEmpty);
    });

    testTwk('disabled, it asks for no frame and leaves no timer, and the '
        'child shows; enabled again, it shimmers again', (t) async {
      Widget app(bool enabled) =>
          rgb(Skeletonize(enabled: enabled, child: Text('x' * 20)));
      await t.pumpWidget(Theme.terminal(child: app(true)), size: (20, 1));
      await until(t, ms * 100);
      await t.pumpWidget(Theme.terminal(child: app(false)));
      expect(t.lines, ['x' * 20]);
      await expectIdle(t);
      await t.pumpWidget(Theme.terminal(child: app(true)));
      expect(t.clock.pendingTimers, 1);
      await t.pumpWidget(const Theme.terminal(child: Text('done')));
      await expectIdle(t);
    });

    testTwk('without shimmer, or on a theme of palette colors, the glyph '
        'alone and no frame asked for', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(
            Skeletonize(enabled: true, shimmer: false, child: Text('x' * 20)),
          ),
        ),
        size: (20, 1),
      );
      expect(columnsIn(t, muted), hasLength(20));
      await expectIdle(t);
      await t.pumpWidget(
        Theme.terminal(
          child: palette(Skeletonize(enabled: true, child: Text('x' * 20))),
        ),
      );
      expect(t.lines, ['░' * 20]);
      await expectIdle(t);
      // a highlight that is not RGB is as much
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(
            SkeletonTheme(
              highlight: const Style(fg: Color.white),
              child: Skeletonize(enabled: true, child: Text('x' * 20)),
            ),
          ),
        ),
      );
      await expectIdle(t);
    });

    testTwk('in the screen-reader mode it stops at its next step, and goes '
        'on once the mode is off', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(Skeletonize(enabled: true, child: Text('x' * 20))),
        ),
        size: (20, 1),
      );
      t.binding.screenReader = true;
      await until(t, ms * 100);
      expect(t.clock.pendingTimers, 0);
      expect(t.binding.semantics.lines, ['loading']);
      await expectIdle(t);
      t.binding.screenReader = false;
      await t.pump();
      expect(t.clock.pendingTimers, 1);
      expect(t.lines, ['░' * 20]);
    });

    testTwk('a skeleton inside an enabled one is drawn by it, on its timer '
        'alone; once it is disabled, by itself', (t) async {
      Widget app(bool enabled) => rgb(
        Skeletonize(
          enabled: enabled,
          child: const Row(
            gap: 1,
            children: [
              Text('name'),
              Skeleton(width: 3),
            ],
          ),
        ),
      );
      await t.pumpWidget(Theme.terminal(child: app(true)), size: (20, 1));
      expect(t.lines, ['░░░░ ░░░']);
      expect(t.clock.pendingTimers, 1);
      await t.pumpWidget(Theme.terminal(child: app(false)));
      expect(t.lines, ['name ░░░']);
      expect(t.clock.pendingTimers, 1);
      expect(t.binding.semantics.lines, ['name', 'loading']);
    });
  });

  group('Skeleton', () {
    testTwk('a block of the width and height given, or as wide as it may '
        'be; read as loading', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: palette(
            const SizedBox(
              width: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 3, height: 2),
                  Skeleton(),
                ],
              ),
            ),
          ),
        ),
        size: (10, 4),
      );
      expect(t.lines, ['░░░', '░░░', '░░░░░░░░', '']);
      expect(t.binding.semantics.lines, ['loading', 'loading']);
      expect(t.rect(find.byType(Skeleton).first).height, 2);
    });

    testTwk('text: its lines as wide as they may be, the last of them '
        'shorter; one line whole', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: palette(
            const SizedBox(
              width: 10,
              child: Column(
                children: [
                  Skeleton.text(lines: 3),
                  Skeleton.text(),
                  Skeleton.text(lines: 2, lastLine: 0),
                ],
              ),
            ),
          ),
        ),
        size: (12, 6),
      );
      expect(t.lines, [
        '░' * 10,
        '░' * 10,
        '░' * 6,
        '░' * 10,
        '░' * 10,
        '░',
      ]);
    });

    testTwk('shimmers on its own, in its own style over the theme', (
      t,
    ) async {
      const red = Color.rgb(200, 0, 0);
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(const Skeleton(width: 20, style: Style(fg: red))),
        ),
        size: (20, 1),
      );
      expect(columnsIn(t, red), hasLength(20));
      await until(t, ms * 750);
      expect(columnsIn(t, bright), [9, 10]);
      await t.pumpWidget(const Theme.terminal(child: Text('loaded')));
      await expectIdle(t);
    });

    testTwk("the theme's glyph, style, highlight, band and period", (
      t,
    ) async {
      const blue = Color.rgb(0, 0, 200);
      const white = Color.rgb(255, 255, 255);
      await t.pumpWidget(
        Theme.terminal(
          child: rgb(
            const SkeletonTheme(
              glyph: '#',
              style: Style(fg: blue),
              highlight: Style(fg: white),
              band: 2,
              period: Duration(milliseconds: 500),
              child: Skeleton(width: 20),
            ),
          ),
        ),
        size: (20, 1),
      );
      expect(t.lines, ['#' * 20]);
      expect(columnsIn(t, blue), hasLength(20));
      // 10 steps of a period; the middle at step 3 is 3 / 10 of the way
      // from a cell before the left edge to one after the right: at 5.6
      await until(t, ms * 150);
      expect(columnsIn(t, white), [5]);
      expect(columnsIn(t, blue), hasLength(19), reason: 'a band of 2');
      await until(t, ms * 500);
      expect(columnsIn(t, blue), hasLength(20), reason: 'the period again');
    });

    testTwk('a glyph that is not a column wide is a blank in reverse '
        'video', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: palette(
            const SkeletonTheme(glyph: '漢', child: Skeleton(width: 4)),
          ),
        ),
        size: (6, 1),
      );
      expect(t.lines, ['']);
      expect(t, styleAt(0, 0, hasAttr(Attr.reverse)));
      expect(t, styleAt(3, 0, hasAttr(Attr.reverse)));
      expect(t, styleAt(4, 0, isNot(hasAttr(Attr.reverse))));
    });
  });

  test(
    'on plain output the glyph alone, and no frame after the first',
    () async {
      late AppBinding binding;
      final lines = await plainLines(
        onRun: (b) => binding = b,
        rgb(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Profile'),
              Skeletonize(enabled: true, child: Text('User: Alice')),
              Skeleton.text(lines: 2),
            ],
          ),
        ),
        width: 12,
      );
      expect(lines, ['Profile', '░░░░░ ░░░░░', '░' * 12, '░' * 7]);
      // a step would have run a frame 50 ms in
      expect(binding.frameTime, lessThan(ms * 50));
    },
  );
}
