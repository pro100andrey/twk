// Pages of the Data and Scrolling groups, and the ListView's options:
// they build at both sizes, their options apply and their keys do what
// the design's do.
import 'package:gallery/gallery.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] (the clock stopped at [at] ms) in a
/// terminal of [size], a frame for the route's focus after the first.
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = (120, 36),
  int at = 2000,
}) async {
  final r = route.contains('?') ? '$route&t=$at' : '$route?t=$at';
  await t.pumpWidget(galleryApp(route: GalleryRoute.parse(r)), size: size);
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

/// The row of the screen [text] is first on; -1 for none.
int rowOf(TwkTester t, String text) =>
    t.lines.indexWhere((l) => l.contains(text));

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

void main() {
  group('the pages build', () {
    for (final size in const [(120, 36), (80, 24)]) {
      for (final (page, shows) in const [
        ('data/treetable', 'table.dart'),
        ('scrolling/logview', 'GET /api/items'),
      ]) {
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

  group('TreeTable', () {
    testTwk('the options apply', (t) async {
      await open(t, '#/data/treetable');
      expect(screen(t), contains('├── box.dart'));
      expect(screen(t), contains('┼'));
      await open(t, '#/data/treetable?o=guides:false;border:none');
      expect(screen(t), isNot(contains('├── box.dart')));
      expect(screen(t), contains('box.dart'));
      expect(screen(t), isNot(contains('┼')));
    });

    testTwk('left selects the parent, then collapses it', (t) async {
      await open(t, '#/data/treetable');
      await keys(t, 'tab,left');
      expect(screen(t), contains('box.dart'));
      await keys(t, 'left');
      expect(screen(t), isNot(contains('box.dart')));
      expect(screen(t), contains('▸ src'));
      await keys(t, 'right');
      expect(screen(t), contains('box.dart'));
    });

    testTwk('s sorts by name, > by lines, within their parents', (t) async {
      await open(t, '#/data/treetable');
      await keys(t, 'tab,s');
      expect(screen(t), contains('name ▴'));
      expect(rowOf(t, 'README.md'), lessThan(rowOf(t, '▾ lib')));
      await keys(t, '>');
      expect(screen(t), contains('lines ▴'));
      // the roots by their lines, the files of lib/src by theirs
      expect(rowOf(t, 'pubspec.yaml'), lessThan(rowOf(t, 'README.md')));
      expect(rowOf(t, 'text.dart'), lessThan(rowOf(t, 'box.dart')));
      expect(rowOf(t, '▾ src'), greaterThan(rowOf(t, '▾ lib')));
    });

    testTwk('* expands a node and every node below it', (t) async {
      await open(t, '#/data/treetable');
      await keys(t, 'tab,end,up,up,*');
      expect(screen(t), contains('table_test.dart'));
    });

    testTwk('a click on an expander collapses its node', (t) async {
      await open(t, '#/data/treetable');
      final y = rowOf(t, '▾ src');
      final x = t.lines[y].indexOf('▾ src');
      await t.click(x, y);
      await t.pump();
      expect(screen(t), contains('▸ src'));
      expect(screen(t), isNot(contains('box.dart')));
    });
  });

  group('LogView', () {
    testTwk('the options apply', (t) async {
      await open(t, '#/scrolling/logview?o=level:warning;time:false');
      expect(screen(t), contains('WARN  slow query'));
      expect(screen(t), isNot(contains('INFO ')));
      expect(screen(t), isNot(contains('12:00:')));
      await open(t, '#/scrolling/logview?o=filter:slow;query:timeout');
      expect(screen(t), isNot(contains('GET /api')));
      expect(screen(t), contains('12:00:'));
    });

    testTwk('it follows the lines as they come, and counts them while '
        'scrolled up; end follows again', (t) async {
      await t.pumpWidget(
        galleryApp(route: GalleryRoute.parse('#/scrolling/logview')),
        size: (120, 36),
      );
      await t.pump();
      // line 30 comes at 400 ms, at the bottom of the window
      await t.pump(const Duration(milliseconds: 450));
      expect(screen(t), contains('12:00:12.000'));
      await keys(t, 'tab,up,up');
      await t.pump(const Duration(milliseconds: 800));
      expect(screen(t), contains(RegExp(r'↓ \d new lines')));
      await keys(t, 'end');
      expect(screen(t), isNot(contains(RegExp(r'↓ \d+ new line'))));
    });

    testTwk('n goes to the next match, scrolled into view', (t) async {
      await open(t, '#/scrolling/logview?o=query:timeout;live:false');
      final before = screen(t);
      await keys(t, 'tab,pageup,pageup,n');
      expect(screen(t), isNot(before));
      expect(screen(t), contains('timeout'));
      expect(screen(t), contains('next match'));
    });
  });

  group('ListView', () {
    testTwk('separated puts a line between each two items', (t) async {
      await open(t, '#/scrolling/listview?o=separated:true');
      expect(rowOf(t, 'item 2'), rowOf(t, 'item 1') + 2);
      expect(t.lines[rowOf(t, 'item 1') + 1], contains('─' * 32));
    });

    testTwk('a chat: the newest message at the bottom, its buttons', (t) async {
      await open(t, '#/scrolling/listview?o=items:chat');
      final newest = rowOf(t, ' 12 twk: no scenario slower');
      expect(newest, greaterThan(rowOf(t, ' 11 you: then tag it')));
      expect(screen(t), contains('newest'));
      expect(screen(t), contains('oldest'));
    });

    testTwk('a chat scrolled up stays on what it shows as messages come; '
        'end goes back to the newest', (t) async {
      await t.pumpWidget(
        galleryApp(
          route: GalleryRoute.parse('#/scrolling/listview?o=items:chat'),
        ),
        size: (120, 36),
      );
      await t.pump();
      await keys(t, 'tab,up,up');
      final at = rowOf(t, '  9 you: is the build green?');
      expect(at, isNonNegative);
      // two messages more
      await t.pump(const Duration(milliseconds: 1300));
      await t.pump();
      expect(screen(t), isNot(contains(' 14 ')));
      expect(rowOf(t, '  9 you: is the build green?'), at);
      await keys(t, 'end');
      expect(screen(t), contains(' 14 '));
    });

    testTwk('a log stuck by its controller follows its end', (t) async {
      await t.pumpWidget(
        galleryApp(
          route: GalleryRoute.parse(
            '#/scrolling/listview?o=items:growing;stick:stickToEnd',
          ),
        ),
        size: (120, 36),
      );
      await t.pump();
      expect(screen(t), contains('GET /items/12 '));
      await t.pump(const Duration(milliseconds: 1300));
      await t.pump();
      expect(screen(t), contains('GET /items/14 '));
    });

    testTwk('a feed scrolled down stays on what it shows as messages come '
        'above it; home goes back to the newest', (t) async {
      await t.pumpWidget(
        galleryApp(
          route: GalleryRoute.parse('#/scrolling/listview?o=items:feed'),
        ),
        size: (120, 36),
      );
      await t.pump();
      expect(screen(t), contains(' 12 twk: no scenario slower'));
      await keys(t, 'tab,down,down');
      final at = rowOf(t, '  9 you: is the build green?');
      expect(at, isNonNegative);
      // two messages more, above the window
      await t.pump(const Duration(milliseconds: 1300));
      await t.pump();
      expect(rowOf(t, '  9 you: is the build green?'), at);
      expect(screen(t), isNot(contains(' 14 ')));
      await keys(t, 'home');
      expect(screen(t), contains(' 14 '));
    });
  });
}
