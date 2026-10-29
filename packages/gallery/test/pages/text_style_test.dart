import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] (the clock stopped at [ms]) in a
/// terminal of [size], a frame for the route's focus after the first.
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = (120, 36),
  int ms = 2000,
}) async {
  final at = route.contains('?') ? '$route&t=$ms' : '$route?t=$ms';
  await t.pumpWidget(galleryApp(route: GalleryRoute.parse(at)), size: size);
  await t.pump();
}

/// Presses [keys] (apart by commas), a frame after each.
Future<void> keys(TwkTester t, String keys) async {
  for (final k in keys.split(',')) {
    await t.press(k);
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 100));
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

/// The cell [text] starts at on the screen.
(int, int) find(TwkTester t, String text) {
  for (final (y, line) in t.lines.indexed) {
    final i = line.indexOf(text);
    if (i >= 0) {
      return (stringWidth(line.substring(0, i)), y);
    }
  }
  throw StateError('$text is not on the screen');
}

/// The row [text] is on.
String rowOf(TwkTester t, String text) =>
    t.lines.firstWhere((l) => l.contains(text));

/// Each page of the two groups, and what its stage shows as it opens.
const _pages = {
  'text/text': 'Terminals draw text',
  'text/rich-text': 'overline',
  'text/defaulttextstyle': 'This one merges yellow over it.',
  'text/right-to-left': 'text order: visual',
  'text/ansi': 'read: 613 characters at once, 7 lines',
  'style/theme': 'catppuccinMocha',
  'style/terminalbrightness': 'The terminal is dark.',
  'style/gradientbackground': 'a box over a gradient',
  'style/gradientforeground': 'Span.gradient, glyph by glyph',
};

void main() {
  group('every Text and Style page', () {
    for (final size in const [(120, 36), (80, 24)]) {
      for (final MapEntry(key: page, value: shows) in _pages.entries) {
        testTwk('$page at ${size.$1}x${size.$2}', (t) async {
          await open(t, '#/$page', size: size);
          final s = screen(t);
          expect(s, isNot(contains('drawn in the next part')));
          // the Theme page's title is its preset's: nord as it opens
          expect(s, contains(page == 'style/theme' ? ' nord ' : shows));
          expect(problems(t), isEmpty);
        });
      }
    }
  });

  group('the options apply', () {
    testTwk('ANSI: streamed a piece at a time', (t) async {
      await open(t, '#/text/ansi?o=read:AnsiStream;piece:16', ms: 200);
      expect(screen(t), contains('read: 80 of 613 characters, 16 at a time'));
      expect(screen(t), contains('piece: '));
    });

    testTwk('ANSI: ls', (t) async {
      await open(t, '#/text/ansi?o=output:ls');
      expect(screen(t), contains('CHANGELOG.md'));
      expect(screen(t), contains('ls --color'));
    });

    testTwk('Rich text: no row labels', (t) async {
      await open(t, '#/text/rich-text');
      expect(screen(t), contains('underlines'));
      await open(t, '#/text/rich-text?o=labels:false');
      expect(screen(t), isNot(contains('underlines')));
      expect(screen(t), contains('a link to dart.dev'));
      final (x, y) = find(t, 'a link to dart.dev');
      expect(t.vt.cell(x, y).link, 'https://dart.dev');
    });

    testTwk('DefaultTextStyle: on navy', (t) async {
      await open(t, '#/text/defaulttextstyle');
      final (x, y) = find(t, 'This text has');
      final plain = t.vt.cell(x, y).bg;
      await open(t, '#/text/defaulttextstyle?o=style:on navy');
      expect(t.vt.cell(x, y).bg, isNot(plain));
      await open(t, '#/text/defaulttextstyle?o=style:on navy&tab=code');
      expect(screen(t), contains('Style(fg: Color.white'));
    });

    testTwk('Right to left: logical order, as stored', (t) async {
      await open(t, '#/text/right-to-left?o=order:logical');
      expect(screen(t), contains('text order: logical'));
      expect(screen(t), contains('שלום עולם! (hello world)'));
      await open(t, '#/text/right-to-left');
      expect(screen(t), contains('(hello world) !םלוע םולש'));
    });

    testTwk('Right to left: aligned to the right', (t) async {
      await open(t, '#/text/right-to-left?o=align:right');
      final (x, _) = find(t, 'in Arabic.');
      final (bx, _) = find(t, '╮');
      // the line ends a blank of padding before the border
      expect(x + 'in Arabic.'.length, bx - 1);
    });

    testTwk('Theme: a preset by name', (t) async {
      await open(t, '#/style/theme?o=theme:latte');
      expect(screen(t), contains(' catppuccinLatte '));
      await open(t, '#/style/theme?o=theme:latte&tab=code');
      expect(screen(t), contains('final (name, data) = _themes[5];'));
    });

    testTwk('Theme: cycle steps the preset and the option', (t) async {
      // from nord, two steps in 5 s: catppuccinLatte, the option with it
      await open(t, '#/style/theme?o=cycle:true', ms: 5000);
      await t.pump();
      expect(screen(t), contains(' catppuccinLatte '));
      await keys(t, 'c');
      expect(screen(t), contains('var _i = 5;'));
    });

    testTwk('TerminalBrightness: light, and its light theme', (t) async {
      await open(
        t,
        '#/style/terminalbrightness?o=brightness:light;light:light',
      );
      expect(screen(t), contains('The terminal is light.'));
      expect(screen(t), contains('Theme.adaptive picks light'));
    });

    testTwk("TerminalBrightness: the gallery's theme stands in", (t) async {
      await open(t, '#/style/terminalbrightness?theme=light');
      expect(screen(t), contains('The terminal is light.'));
      expect(screen(t), contains('Theme.adaptive picks catppuccinLatte'));
    });

    testTwk('GradientBackground: the colours flow with time', (t) async {
      await open(t, '#/style/gradientbackground', ms: 1000);
      final (x, y) = find(t, 'a box over');
      final at1 = t.vt.cell(x - 4, y).bg;
      await open(t, '#/style/gradientbackground');
      expect(t.vt.cell(x - 4, y).bg, isNot(at1));
      await open(t, '#/style/gradientbackground?o=flow:false', ms: 1000);
      final still = t.vt.cell(x - 4, y).bg;
      await open(t, '#/style/gradientbackground?o=flow:false');
      expect(t.vt.cell(x - 4, y).bg, still);
      await open(t, '#/style/gradientbackground?o=flow:false&tab=code');
      expect(screen(t), contains('= Gradient(_colors'));
    });

    testTwk('GradientForeground: down the rows', (t) async {
      await open(t, '#/style/gradientforeground?o=direction:rows;flow:false');
      final (x, y) = find(t, '████████╗');
      // one colour along a row, another on the next
      expect(t.vt.cell(x, y).fg, t.vt.cell(x + 7, y).fg);
      expect(t.vt.cell(x, y).fg, isNot(t.vt.cell(x + 3, y + 2).fg));
    });
  });

  group('the keys', () {
    testTwk('Theme: tab to the Checkbox, space unchecks it', (t) async {
      await open(t, '#/style/theme');
      expect(screen(t), contains('[x] Checkbox'));
      await keys(t, 'tab,tab,space');
      expect(screen(t), contains('[ ] Checkbox'));
    });

    testTwk('Theme: space turns the Switch off', (t) async {
      await open(t, '#/style/theme');
      expect(rowOf(t, 'Switch'), contains('▐  ●▌'));
      await keys(t, 'tab,tab,tab,space');
      await t.pump(const Duration(milliseconds: 500));
      expect(rowOf(t, 'Switch'), contains('▐●  ▌'));
    });

    testTwk('Rich text: a click on the link says what it does', (t) async {
      await open(t, '#/text/rich-text');
      final (x, y) = find(t, 'a link to dart.dev');
      await t.click(x + 2, y);
      await t.pump();
      expect(screen(t), contains('Opens https://dart.dev'));
    });
  });
}
