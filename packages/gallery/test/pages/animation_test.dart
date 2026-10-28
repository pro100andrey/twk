import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] in a terminal of [size], the gallery's
/// clock stopped at 2 s and the app's run on to it, as the comparison with
/// the design runs it: what runs on twk's own tickers is where it would
/// be at 2 s.
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = (120, 36),
}) async {
  final at = route.contains('?') ? '$route&t=2000' : '$route?t=2000';
  await t.pumpWidget(galleryApp(route: GalleryRoute.parse(at)), size: size);
  await t.pump(const Duration(milliseconds: 2000));
}

/// Presses [keys] (apart by commas), a frame after each, and lets what
/// they started run its 600 ms.
Future<void> keys(TwkTester t, String keys) async {
  for (final k in keys.split(',')) {
    await t.press(k);
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 700));
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// The line of the screen [text] is on.
String lineOf(TwkTester t, String text) =>
    t.lines.firstWhere((l) => l.contains(text), orElse: () => '');

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

/// Each page of the group, and what its stage shows at 2 s.
const _pages = {
  'spinner': 'Running 214 tests…',
  'progressbar': '33%',
  'animationcontroller': 'curved 1.00',
  'animatedalign-animatedpadding': '◆ aligned',
  'animatedpositioned': '▣ pinned',
  'animatedbox': 'a box',
  'animatedopacity-opacity': 'AnimatedOpacity',
  'animateddefaulttextstyle': 'and a second Text, in step.',
  'animatedsize': 'a second, longer line',
  // the cycle's tick at 1.2 s: the next value
  'tweenanimationbuilder': '75%',
  'animatedswitcher': 'and now the second one',
  'dissolve-fractionaltranslation': 'FractionalTranslation(x: -0.50)',
  'effect': 'repainting underneath',
};

void main() {
  group('every Animation page', () {
    for (final size in const [(120, 36), (80, 24)]) {
      for (final MapEntry(key: page, value: shows) in _pages.entries) {
        testTwk('$page at ${size.$1}x${size.$2}', (t) async {
          await open(t, '#/animation/$page', size: size);
          final s = screen(t);
          expect(s, isNot(contains('drawn in the next part')));
          expect(s, contains(shows));
          expect(problems(t), isEmpty);
        });
      }
    }
  });

  group('the options apply', () {
    testTwk('Spinner: the arc', (t) async {
      await open(t, '#/animation/spinner?o=frames:arc');
      expect(lineOf(t, 'Compiling…'), matches(RegExp('[◜◠◝◞◡◟] Compiling…')));
    });

    testTwk('ProgressBar: no value known, no percentage', (t) async {
      await open(t, '#/animation/progressbar?o=known:false');
      expect(screen(t), contains('40 × 1'));
    });

    testTwk('AnimationController: its duration, in the Code', (t) async {
      await open(t, '#/animation/animationcontroller?o=duration:4 s&tab=code');
      expect(screen(t), contains('duration: const Duration(seconds: 4)'));
    });

    testTwk('AnimatedAlign: at the right, padded to it', (t) async {
      await open(
        t,
        '#/animation/animatedalign-animatedpadding'
        '?o=alignment:centerRight;cycle:false',
      );
      expect(lineOf(t, '◆ aligned'), contains('◆ aligned│'));
      expect(lineOf(t, '◇ padded'), contains('│${' ' * 20}◇ padded'));
    });

    testTwk('AnimatedPositioned: pinned at the bottom right', (t) async {
      await open(
        t,
        '#/animation/animatedpositioned?o=pin:bottomRight;cycle:false',
      );
      final at = t.lines.indexWhere((l) => l.contains('▣ pinned'));
      expect(t.lines[at + 1], contains('╰'));
      expect(t.lines[at], contains('▣ pinned  │'));
    });

    testTwk('AnimatedBox: big, in a double border', (t) async {
      await open(t, '#/animation/animatedbox?o=big:true;cycle:false');
      expect(screen(t), contains('╔'));
      await open(t, '#/animation/animatedbox?o=cycle:false');
      expect(screen(t), isNot(contains('╔')));
    });

    testTwk('AnimatedOpacity: none of the child at 0', (t) async {
      await open(
        t,
        '#/animation/animatedopacity-opacity?o=opacity:0;cycle:false',
      );
      expect(screen(t), contains('under it, under it'));
      expect(screen(t), isNot(contains('the child')));
    });

    testTwk('AnimatedDefaultTextStyle: bold', (t) async {
      await open(
        t,
        '#/animation/animateddefaulttextstyle?o=bold:true;cycle:false',
      );
      final y = t.lines.indexWhere((l) => l.contains('Text in the style'));
      final x = t.lines[y].indexOf('Text in the style');
      expect(t.cell(x, y).attrs & Attr.bold, isNot(0));
    });

    testTwk('AnimatedSize: all five lines', (t) async {
      await open(t, '#/animation/animatedsize?o=lines:5;cycle:false');
      expect(screen(t), contains('and a fifth'));
    });

    testTwk('TweenAnimationBuilder: run up to 1', (t) async {
      await open(t, '#/animation/tweenanimationbuilder?o=value:1;cycle:false');
      expect(screen(t), contains('100%'));
    });

    testTwk('AnimatedSwitcher: the third child', (t) async {
      await open(t, '#/animation/animatedswitcher?o=child:third;cycle:false');
      expect(screen(t), contains('a third'));
    });

    testTwk('Dissolve: all of it shown, standing still', (t) async {
      await open(
        t,
        '#/animation/dissolve-fractionaltranslation?o=share:1;run:false',
      );
      expect(screen(t), contains('Dissolve(shown: 1.00)'));
      expect(screen(t), contains(' a child, its cells shown or moved '));
    });

    testTwk('Effect: the one chosen, in the Code', (t) async {
      await open(
        t,
        '#/animation/effect?o=effect:scanlines;cycle:false&tab=code',
      );
      expect(screen(t), contains('effect: const CellEffect.scanlines(),'));
    });
  });

  group('the keys do what the design says', () {
    testTwk('Spinner: the next frames, the colour back', (t) async {
      await open(t, '#/animation/spinner');
      await keys(t, 'tab,right,tab,left');
      expect(lineOf(t, 'Compiling…'), matches(RegExp(r'[-\\|/] Compiling…')));
      expect(problems(t), isEmpty);
    });

    testTwk('ProgressBar: value not known, then at the end', (t) async {
      await open(t, '#/animation/progressbar');
      await keys(t, 'tab,space');
      expect(screen(t), contains('40 × 1'));
      await keys(t, 'space');
      expect(screen(t), contains('45 × 1'));
    });

    testTwk('AnimationController: Stop, then Run', (t) async {
      await open(t, '#/animation/animationcontroller');
      expect(screen(t), contains(' Stop '));
      await keys(t, 'tab,enter');
      expect(screen(t), contains(' Run '));
      final stopped = lineOf(t, 'value  ');
      await t.pump(const Duration(milliseconds: 500));
      expect(lineOf(t, 'value  '), stopped);
      await keys(t, 'enter');
      expect(screen(t), contains(' Stop '));
      expect(lineOf(t, 'value  '), isNot(stopped));
    });

    testTwk('Effect: its spinner repaints under a toast', (t) async {
      await open(t, '#/animation/effect?toast=Saved&kind=success');
      await t.pump(const Duration(milliseconds: 1000));
      expect(screen(t), contains('Saved'));
      expect(problems(t), isEmpty);
    });

    testTwk('Effect: Again runs it from its start', (t) async {
      await open(t, '#/animation/effect?o=effect:typewriter;cycle:false');
      expect(screen(t), contains('the cells it paints, filtered'));
      await t.press('tab');
      await t.press('enter');
      await t.pump(const Duration(milliseconds: 100));
      expect(screen(t), isNot(contains('the cells it paints, filtered')));
      await t.pump(const Duration(milliseconds: 700));
      expect(screen(t), contains('the cells it paints, filtered'));
      expect(problems(t), isEmpty);
    });
  });

  group('the cycle', () {
    testTwk('a value every 1.2 s; one picked by hand stays', (t) async {
      await t.pumpWidget(
        galleryApp(route: GalleryRoute.parse('#/animation/animatedswitcher')),
        size: (120, 36),
      );
      await t.pump(const Duration(milliseconds: 100));
      expect(screen(t), contains('the first child'));
      await t.pump(const Duration(milliseconds: 1900));
      expect(screen(t), contains('and now the second one'));
      // the child option, moved along with it, and on by hand
      await keys(t, 'tab,right');
      expect(screen(t), contains('a third'));
      await t.pump(const Duration(milliseconds: 2500));
      expect(screen(t), contains('a third'));
      expect(problems(t), isEmpty);
    });
  });
}
