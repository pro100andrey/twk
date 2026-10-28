// The pages of round 3's widgets in the Navigation, Animation, Overlays,
// Screen readers and Debugging groups: each builds at both sizes, its
// options apply and its keys do what the design's do.
import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] in a terminal of [size], the gallery's
/// clock stopped at 2 s and the app's run on to it, as the comparison with
/// the design runs it.
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = (120, 36),
  int ms = 2000,
}) async {
  final at = route.contains('?') ? '$route&t=$ms' : '$route?t=$ms';
  await t.pumpWidget(galleryApp(route: GalleryRoute.parse(at)), size: size);
  await t.pump(Duration(milliseconds: ms));
}

/// The Code of page [title] with the options [raw] (raw values by key:
/// a bool, an index), the others as they start.
String codeOf(String title, [Map<String, Object> raw = const {}]) {
  final page = galleryPages.firstWhere((p) => p.title == title);
  return page.codeOf(Options(page, raw))!;
}

/// Where [text] starts on the screen.
(int, int) whereIs(TwkTester t, String text) {
  final y = t.lines.indexWhere((l) => l.contains(text));
  return (t.lines[y].indexOf(text), y);
}

/// Presses [keys] (apart by commas), a frame after each, and lets what
/// they started run.
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

/// Each new page, and what its stage shows at 2 s.
const _pages = {
  'animation/animatedbuilder': ' twk ',
  'debugging/repaintboundary': 'painted: 1',
  'navigation/popscope-navigatorobserver': 'heard: pushed /',
};

void main() {
  group('every new page', () {
    for (final size in const [(120, 36), (80, 24)]) {
      for (final MapEntry(key: page, value: shows) in _pages.entries) {
        testTwk('$page at ${size.$1}x${size.$2}', (t) async {
          await open(t, '#/$page', size: size);
          final s = screen(t);
          expect(s, isNot(contains('drawn in the next part')));
          expect(s, contains(shows));
          expect(problems(t), isEmpty);
        });
      }
    }
  });

  group('AnimatedBuilder', () {
    /// The column of the chip in its track.
    int chipAt(TwkTester t) {
      final track = RegExp('│( *) twk  *│');
      final m = t.lines.map(track.firstMatch).nonNulls.first;
      return m.group(1)!.length;
    }

    testTwk('the chip is at the end of the track at 2 s', (t) async {
      await open(t, '#/animation/animatedbuilder');
      expect(chipAt(t), 35);
    });

    testTwk('a longer duration has it halfway', (t) async {
      await open(
        t,
        '#/animation/animatedbuilder?o=curve:linear;duration:4%20s',
      );
      expect(chipAt(t), inInclusiveRange(16, 18));
    });

    testTwk('the Code names the curve and the way round', (t) async {
      await open(
        t,
        '#/animation/animatedbuilder?o=curve:bounceOut;reverse:false&tab=code',
      );
      final s = screen(t);
      expect(s, contains('Curves.bounceOut'));
      expect(s, contains(')..repeat();'));
      expect(s, contains('AnimatedBuilder('));
    });
  });

  group('ModalBarrier', () {
    const under = 'The text under the barrier';

    test('fade: an AnimatedModalBarrier in the Code', () {
      final code = codeOf('ModalBarrier', {'fade': true});
      expect(code, contains('AnimatedModalBarrier('));
      expect(code, contains('animation: _fade,'));
      expect(code, contains('..repeat(reverse: true);'));
      expect(codeOf('ModalBarrier'), isNot(contains('AnimatedModalBarrier(')));
    });

    testTwk('fade: the shade comes in and goes with the controller', (t) async {
      Future<int> shadeAt(int ms, String o) async {
        await open(t, '#/overlays/modalbarrier?o=$o', ms: ms);
        final (x, y) = whereIs(t, under);
        return t.vt.cell(x, y).bg;
      }

      final none = await shadeAt(2000, 'barrier:false');
      final full = await shadeAt(2000, 'barrier:true');
      // 0.5 s into the second second: the shade half gone again
      final half = await shadeAt(2500, 'fade:true');
      expect(half, isNot(none));
      expect(half, isNot(full));
      // at 2 s the controller is back at its start: the shade all but gone
      expect(await shadeAt(2000, 'fade:true'), isNot(full));
    });

    test('fade does not apply without the barrier', () {
      final code = codeOf('ModalBarrier', {'barrier': false, 'fade': true});
      expect(code, isNot(contains('ModalBarrier(')));
    });
  });

  group('Semantics', () {
    /// The lines the page shows under its "A screen reader reads:".
    List<String> read(TwkTester t) {
      const over = 'A screen reader reads:';
      final (column, row) = whereIs(t, over);
      return [
        for (final line in t.lines.skip(row + 1))
          line.substring(column).split('│').first.trim(),
      ].takeWhile((l) => l.isNotEmpty).toList();
    }

    testTwk('ExcludeSemantics: the heading shows and is not read', (t) async {
      await open(t, '#/screen-readers/semantics?o=exclude:true');
      expect(screen(t), contains('Sign in'));
      expect(read(t), [
        'checkbox Remember me, not checked',
        'switch Dark mode, on',
        'progressbar Upload: 40%',
        'button More',
        'button Cancel',
        'dialog Popup',
        'the notice on top',
      ]);
      final code = codeOf('Semantics', {'exclude': true});
      expect(code, contains('ExcludeSemantics('));
      expect(codeOf('Semantics'), isNot(contains('ExcludeSemantics(')));
    });

    testTwk('without it the heading is read', (t) async {
      await open(t, '#/screen-readers/semantics');
      expect(read(t).first, 'heading Sign in');
    });
  });

  group('RepaintBoundary', () {
    testTwk('in the boundary the marker moves and the dots are painted once', (
      t,
    ) async {
      await open(t, '#/debugging/repaintboundary');
      // six steps of 300 ms in 2 s
      expect(screen(t), contains('${'·' * 6}●${'·' * 13}'));
      expect(screen(t), contains('painted: 1'));
    });

    testTwk('without it, once a step', (t) async {
      await open(t, '#/debugging/repaintboundary?o=boundary:false');
      expect(screen(t), contains('painted: 6'));
      await open(
        t,
        '#/debugging/repaintboundary?o=boundary:false;every:1%20s',
        ms: 3500,
      );
      expect(screen(t), contains('painted: 3'));
    });

    test('the Code puts the marker in a boundary, or not', () {
      expect(
        codeOf('RepaintBoundary'),
        contains('final marker = RepaintBoundary('),
      );
      final without = codeOf('RepaintBoundary', {'boundary': false});
      expect(without, contains('final marker = CustomPaint('));
      expect(codeOf('RepaintBoundary', {'every': 1}), contains('seconds: 1'));
    });
  });

  group('PopScope, NavigatorObserver', () {
    const page = '#/navigation/popscope-navigatorobserver';

    /// What the line under the box says the observer heard last.
    String heard(TwkTester t) =>
        lineOf(t, 'heard: ').split('heard: ').last.split('  ').first;

    testTwk('Back pops the note unchanged; the observer hears each', (
      t,
    ) async {
      await open(t, page);
      expect(heard(t), 'pushed /');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('Edit the note'));
      expect(heard(t), 'pushed /edit');
      await keys(t, 'enter');
      expect(screen(t), contains('Notes'));
      expect(heard(t), 'popped /edit');
    });

    testTwk('changed, the back key asks; Discard pops it', (t) async {
      await open(t, page);
      await keys(t, 'tab,enter,shift+tab,space,escape');
      expect(screen(t), contains('Discard the changes?'));
      expect(heard(t), 'pushed a dialog');
      await keys(t, 'enter');
      expect(screen(t), isNot(contains('Discard the changes?')));
      expect(screen(t), contains('Notes'));
      expect(heard(t), 'popped /edit');
    });

    testTwk('Keep removes the dialog and stays', (t) async {
      await open(t, page);
      await keys(t, 'tab,enter,shift+tab,space,escape,tab,enter');
      expect(screen(t), isNot(contains('Discard the changes?')));
      expect(screen(t), contains('[x] changed'));
      expect(heard(t), 'removed a dialog');
    });

    testTwk('Escape closes the dialog', (t) async {
      await open(t, page);
      await keys(t, 'tab,enter,shift+tab,space,escape,escape');
      expect(screen(t), isNot(contains('Discard the changes?')));
      expect(heard(t), 'popped a dialog');
    });

    testTwk('a PopScope in the dialog keeps it against Escape', (t) async {
      await open(t, '$page?o=dialog:is%20kept');
      await keys(t, 'tab,enter,shift+tab,space,escape,escape');
      expect(screen(t), contains('Discard the changes?'));
      expect(heard(t), 'pushed a dialog');
    });

    testTwk('without the PopScope the back key pops it changed', (t) async {
      await open(t, '$page?o=scope:false');
      await keys(t, 'tab,enter,shift+tab,space,escape');
      expect(screen(t), contains('Notes'));
      expect(heard(t), 'popped /edit');
      expect(
        codeOf('PopScope, NavigatorObserver', {'scope': false}),
        isNot(contains('PopScope<')),
      );
      expect(
        codeOf('PopScope, NavigatorObserver', {'dialog': 1}),
        contains('(context) => PopScope<bool>('),
      );
    });
  });
}
