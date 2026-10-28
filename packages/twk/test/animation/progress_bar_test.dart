// Progress bars filled in eighths of a cell, in braille halves where block
// elements are two columns wide; without a value, a block going back and
// forth a cell each step of the app's clock, in step with the others, and
// no timer once a value comes.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../data/shot.dart';

const ms = Duration(milliseconds: 1);

/// Pumps until the clock reads [at].
Future<void> until(TwkTester t, Duration at) => t.pump(at - t.clock.elapsed);

/// The row of a bar [width] cells wide filled to [value].
String bar(double value, {int width = 10, int ambiguousWidth = 1}) {
  final shot = Shot.render(
    RenderProgressBar(value: value),
    width,
    1,
    ambiguousWidth: ambiguousWidth,
  );
  expect(shot.vt.errors, isEmpty);
  return shot.rows.single;
}

void main() {
  test('fills to the nearest eighth of a cell; a value beyond 0 and 1 '
      'counts as the nearest, one that is not a number as 0', () {
    expect(bar(0.55), '█████▌');
    expect(bar(0.0125), '▏');
    expect(bar(0.99), '█████████▉');
    expect(bar(1.5), '██████████');
    expect(bar(-1), '');
    expect(bar(double.nan), '');
  });

  test('fills in braille halves where block elements are two columns', () {
    expect(bar(0.55, ambiguousWidth: 2), '⣿⣿⣿⣿⣿⡇');
  });

  testTwk('as wide as it may be, every row it is given filled, in the '
      "theme's primary color", (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: Column(
          children: [
            SizedBox(height: 2, child: ProgressBar(value: 0.5)),
            ProgressBar(value: 1, style: Style(fg: Color.red)),
          ],
        ),
      ),
      size: (4, 4),
    );
    expect(t.lines, ['██', '██', '████', '']);
    expect(
      t,
      styleAt(
        0,
        0,
        hasFg(const ThemeData.terminal(Brightness.dark).primary.fg!),
      ),
    );
    expect(t, styleAt(0, 2, hasFg(Color.red)));
  });

  testTwk('a screen reader reads how much is done in whole percent, cut: '
      '100% only once it is all done', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: Column(
          children: [
            ProgressBar(value: 0.996, semanticsLabel: 'Upload'),
            ProgressBar(value: 1),
            ProgressBar(semanticsLabel: 'Build'),
          ],
        ),
      ),
      size: (4, 3),
    );
    expect(t.binding.semantics.lines, [
      'progressbar Upload: 99%',
      'progressbar 100%',
      'progressbar Build',
    ]);
  });

  testTwk('in the inline mode the region gives each bar its row', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('above'),
            ProgressBar(value: 0.5),
            ProgressBar(),
            Text('below'),
          ],
        ),
      ),
      size: (8, 6),
      mode: ScreenMode.inline,
    );
    expect(t.lines.take(4), ['above', '████', '██', 'below']);
  });

  testTwk('without a value, a block a quarter of its width goes from one '
      'end to the other and back, a cell each step, repainting nothing '
      'else', (t) async {
    final count = PaintCount();
    await t.pumpWidget(
      Theme.terminal(
        child: Column(children: [const ProgressBar(), Counted(count)]),
      ),
      size: (8, 2),
    );
    expect(ProgressBar.step, ms * 50);
    final painted = count.paints;
    final shown = [t.lines.first];
    for (var i = 1; i <= 13; i++) {
      await until(t, ProgressBar.step * i);
      shown.add(t.lines.first);
    }
    expect(count.paints, painted);
    expect(shown, [
      '██',
      ' ██',
      '  ██',
      '   ██',
      '    ██',
      '     ██',
      '      ██',
      '     ██',
      '    ██',
      '   ██',
      '  ██',
      ' ██',
      '██',
      ' ██',
    ]);
  });

  testTwk('bars without a value move together, on one timer; given a '
      'value, the block stops and no timer is left', (t) async {
    await t.pumpWidget(
      const Theme.terminal(
        child: Column(children: [ProgressBar(), ProgressBar()]),
      ),
      size: (8, 2),
    );
    await until(t, ms * 100);
    expect(t.lines, ['  ██', '  ██']);
    expect(t.clock.pendingTimers, 1);
    await t.pumpWidget(
      const Theme.terminal(
        child: Column(
          children: [ProgressBar(value: 0.5), ProgressBar(value: 1)],
        ),
      ),
    );
    expect(t.lines, ['████', '████████']);
    expect(t.clock.pendingTimers, 0);
    await t.pumpWidget(
      const Theme.terminal(
        child: Column(children: [ProgressBar(), ProgressBar(value: 1)]),
      ),
    );
    expect(t.clock.pendingTimers, 1);
    await t.pumpWidget(const Theme.terminal(child: Text('done')));
    expect(t.clock.pendingTimers, 0);
  });

  testTwk('built with another style it paints in the new color, the fill '
      'as it was', (t) async {
    await t.pumpWidget(
      const Theme.terminal(child: ProgressBar(value: 0.5)),
      size: (4, 1),
    );
    await t.pumpWidget(
      const Theme.terminal(
        child: ProgressBar(value: 0.5, style: Style(fg: Color.green)),
      ),
    );
    expect(t.lines, ['██']);
    expect(t, styleAt(0, 0, hasFg(Color.green)));
    final bar = t.renderObject<RenderProgressBar>(find.byType(ProgressBar));
    expect(bar.value, 0.5);
    expect(bar.style.fg, Color.green);
  });
}
