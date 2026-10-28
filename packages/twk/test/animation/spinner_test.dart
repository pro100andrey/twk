// Spinners on the fake clock: a frame each interval of the app's clock,
// all of them in step on one timer, repainting nothing else and building
// nothing, and no timer once gone; on the background of the box they sit
// in; the frame sets, their width, and the first frame outside an app.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../data/shot.dart';

const ms = Duration(milliseconds: 1);

/// Pumps until the clock reads [at].
Future<void> until(TwkTester t, Duration at) => t.pump(at - t.clock.elapsed);

/// How many times [Built] was built.
var builds = 0;

/// Text that counts its builds.
final class Built extends StatelessWidget {
  const Built(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    builds++;
    return Text(text);
  }
}

void main() {
  testTwk('shows its frames in turn, a frame each interval of the '
      "app's clock, in the theme's primary color", (t) async {
    await t.pumpWidget(const Theme.terminal(child: Spinner()), size: (3, 1));
    const frames = SpinnerFrames.dots;
    expect(frames.interval, ms * 80);
    final shown = [t.lines.single];
    for (var i = 1; i <= 10; i++) {
      await until(t, ms * 80 * i - ms);
      expect(t.lines.single, shown.last, reason: 'not before ${80 * i} ms');
      await until(t, ms * 80 * i);
      shown.add(t.lines.single);
    }
    expect(shown, [...frames.frames, frames.frames.first]);
    expect(
      t,
      styleAt(
        0,
        0,
        hasFg(const ThemeData.terminal(Brightness.dark).primary.fg!),
      ),
    );
  });

  testTwk("on the theme's background, in its primary color or over its "
      'text', (t) async {
    const theme = ThemeData.light;
    await t.pumpWidget(
      const Theme.terminal(
        child: Theme(
          data: theme,
          child: Row(
            children: [
              Spinner(),
              Spinner(style: Style(attrs: Attr.bold)),
            ],
          ),
        ),
      ),
      size: (3, 1),
    );
    final background = theme.background.bg!;
    expect(
      t,
      styleAt(0, 0, allOf(hasFg(theme.primary.fg!), hasBg(background))),
    );
    expect(t, styleAt(1, 0, allOf(hasFg(theme.text.fg!), hasBg(background))));
  });

  testTwk('in a Box it takes the background of the box, as it steps and '
      'as the box changes; its own background, where its style has one, '
      'over that', (t) async {
    const theme = ThemeData.dark;
    Widget boxed(Color bg) => Theme(
      data: theme,
      child: Box(
        style: Style(bg: bg),
        child: const Row(
          children: [
            // a box without a background is passed by
            Box(child: Spinner()),
            Spinner(style: Style(bg: Color.rgb(1, 2, 3))),
          ],
        ),
      ),
    );
    final surface = theme.surface.bg!;
    await t.pumpWidget(Theme.terminal(child: boxed(surface)), size: (3, 1));
    expect(
      t,
      styleAt(0, 0, allOf(hasFg(theme.primary.fg!), hasBg(surface))),
    );
    expect(t, styleAt(1, 0, hasBg(const Color.rgb(1, 2, 3))));
    await until(t, ms * 80);
    expect(t, styleAt(0, 0, hasBg(surface)), reason: 'a step on its own');
    const other = Color.rgb(90, 0, 0);
    await t.pumpWidget(Theme.terminal(child: boxed(other)));
    expect(t, styleAt(0, 0, hasBg(other)));
  });

  testTwk('two spinners share one ticker: they show the same frame, a '
      'spinner shown later too, and step in the same frames on one timer', (
    t,
  ) async {
    await t.pumpWidget(const Theme.terminal(child: Spinner()), size: (5, 1));
    await until(t, ms * 50);
    await t.pumpWidget(
      const Theme.terminal(
        child: Row(gap: 1, children: [Spinner(), Spinner()]),
      ),
    );
    expect(t.lines, ['⠋ ⠋']);
    expect(t.clock.pendingTimers, 1);
    final written = t.frames.length;
    await until(t, ms * 80);
    expect(t.lines, ['⠙ ⠙']);
    expect(t.frames, hasLength(written + 1));
    expect(t.clock.pendingTimers, 1);
    expect(t.clock.nextTimerDue, ms * 160);
    await until(t, ms * 800);
    expect(t.lines, ['⠋ ⠋']);
    expect(t.frames, hasLength(written + 10), reason: 'a frame a step');
  });

  testTwk('a step repaints the spinner alone and builds nothing', (t) async {
    final count = PaintCount();
    await t.pumpWidget(
      Theme.terminal(
        child: Column(
          children: [
            const Row(gap: 1, children: [Spinner(), Built('working')]),
            Counted(count),
          ],
        ),
      ),
      size: (12, 2),
    );
    final (built, painted) = (builds, count.paints);
    await until(t, ms * 80);
    expect(t.lines, ['⠙ working', '']);
    expect(t.binding.twkApp.stats.lastRepaints, 1);
    expect((builds, count.paints), (built, painted));
  });

  testTwk('a spinner removed leaves no timer, and the app goes idle', (
    t,
  ) async {
    await t.pumpWidget(const Theme.terminal(child: Spinner()), size: (3, 1));
    expect(t.clock.pendingTimers, 1);
    await t.pumpWidget(const Theme.terminal(child: Text('done')));
    expect(t.clock.pendingTimers, 0);
    await t.pumpUntilIdle();
  });

  testTwk('the line and arc frames; as wide as the widest frame, and a '
      'new set steps at its own interval', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: Row(
          children: [
            Spinner(frames: SpinnerFrames.line),
            Text('|'),
          ],
        ),
      ),
      size: (6, 1),
    );
    final line = [t.lines.single];
    for (var i = 1; i <= 3; i++) {
      await until(t, ms * 130 * i);
      line.add(t.lines.single);
    }
    expect(line, ['-|', r'\|', '||', '/|']);
    await t.pumpWidget(
      const Theme.terminal(
        child: Row(
          children: [
            Spinner(
              frames: SpinnerFrames([
                'a',
                'bbb',
              ], interval: Duration(seconds: 1)),
            ),
            Text('|'),
          ],
        ),
      ),
    );
    expect(t.lines, ['a  |']);
    expect(t.clock.nextTimerDue, const Duration(seconds: 1));
    await until(t, const Duration(seconds: 1));
    expect(t.lines, ['bbb|']);
    await t.pumpWidget(
      const Theme.terminal(child: Spinner(frames: SpinnerFrames.arc)),
    );
    expect(t.clock.nextTimerDue, ms * 1100);
    await until(t, ms * 1100);
    expect(t.lines.single, '◟');
  });

  testTwk('in the inline mode the region gives it its row', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Spinner(), Text('below')],
        ),
      ),
      size: (8, 4),
      mode: ScreenMode.inline,
    );
    expect(t.lines.take(2), ['⠋', 'below']);
    await until(t, ms * 80);
    expect(t.lines.take(2), ['⠙', 'below']);
  });

  test('outside an app it shows its first frame', () {
    expect(
      renderToString(RenderSpinner(), 2, 1, styles: StyleTable()).trimRight(),
      '⠋',
    );
  });

  test('frames of the same glyphs and interval are equal, with equal '
      'hashes; another interval or glyph makes them differ', () {
    const a = SpinnerFrames(['a', 'b'], interval: Duration(seconds: 1));
    final same = SpinnerFrames(['a', 'b'].toList(), interval: ms * 1000);
    expect(same, a);
    expect(same.hashCode, a.hashCode);
    expect(const SpinnerFrames(['a', 'b'], interval: ms), isNot(a));
    expect(
      const SpinnerFrames(['a', 'c'], interval: Duration(seconds: 1)),
      isNot(a),
    );
  });

  testTwk('built with another style or under another theme, it paints in '
      'the new colors at once', (t) async {
    await t.pumpWidget(const Theme.terminal(child: Spinner()), size: (3, 1));
    await t.pumpWidget(
      const Theme.terminal(
        child: Spinner(style: Style(fg: Color.red)),
      ),
    );
    expect(t, styleAt(0, 0, hasFg(Color.red)));
    await t.pumpWidget(
      const Theme.terminal(
        child: Theme(
          data: ThemeData.light,
          child: Spinner(style: Style(fg: Color.red)),
        ),
      ),
    );
    expect(
      t,
      styleAt(
        0,
        0,
        allOf(hasFg(Color.red), hasBg(ThemeData.light.background.bg!)),
      ),
    );
    expect(t.lines.single, '⠋', reason: 'the frame it was on');
  });

  testTwk('built again with other frames, another style or under another '
      "theme, it keeps its place and shows them, on the theme's background "
      'where its style has none', (t) async {
    Widget spinner(ThemeData theme, {SpinnerFrames? frames, Style? style}) =>
        Theme(
          data: theme,
          child: Spinner(frames: frames ?? SpinnerFrames.dots, style: style),
        );
    await t.pumpWidget(
      Theme.terminal(child: spinner(ThemeData.dark)),
      size: (3, 1),
    );
    final render = t.renderObject<RenderSpinner>(find.byType(Spinner));
    expect(render.frames, SpinnerFrames.dots);
    expect(render.background, ThemeData.dark.background.bg);
    const red = Style(fg: Color.red);
    await t.pumpWidget(
      Theme.terminal(child: spinner(ThemeData.dark, style: red)),
    );
    expect(render.style.fg, Color.red);
    expect(t, styleAt(0, 0, hasFg(Color.red)));
    // the light theme's text and the dark one's are of a color each, both
    // under red: only the background differs
    await t.pumpWidget(
      Theme.terminal(child: spinner(ThemeData.light, style: red)),
    );
    expect(
      t.renderObject<RenderSpinner>(find.byType(Spinner)),
      same(render),
      reason: 'the same render object, given the new theme',
    );
    expect(render.background, ThemeData.light.background.bg);
    expect(
      t,
      styleAt(
        0,
        0,
        allOf(hasFg(Color.red), hasBg(ThemeData.light.background.bg!)),
      ),
    );
    await t.pumpWidget(
      Theme.terminal(
        child: spinner(ThemeData.light, frames: SpinnerFrames.line, style: red),
      ),
    );
    expect(render.frames, SpinnerFrames.line);
    expect(t.lines.single, SpinnerFrames.line.frames.first);
  });

  testTwk('its intrinsic width is that of its widest frame, its height a '
      'row', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicWidth(
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Spinner(
                      frames: SpinnerFrames(['ab', 'abcd'], interval: ms),
                    ),
                  ],
                ),
              ),
            ),
            Text('end'),
          ],
        ),
      ),
      size: (8, 3),
    );
    expect(t.lines, ['ab', 'end', '']);
    expect(t.rect(find.byType(Spinner)), (x: 0, y: 0, width: 4, height: 1));
    final spinner = t.renderObject<RenderSpinner>(find.byType(Spinner));
    // at least as at most: a frame is never wrapped
    expect(spinner.getMinIntrinsicWidth(1), 4);
    expect(spinner.getMinIntrinsicHeight(4), 1);
  });
}
