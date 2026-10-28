import 'package:gallery/gallery.dart';
import 'package:gallery/src/paint.dart' show cut;
import 'package:gallery/src/shell/stage.dart' show Stage;
import 'package:gallery/src/shell/tokens.dart' show galleryThemes, sidebarWidth;
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Opens the gallery at [route] in a terminal of [size], a frame for the
/// route's focus after the first.
Future<void> open(
  TwkTester t,
  String route, {
  (int, int) size = (120, 36),
}) async {
  await t.pumpWidget(galleryApp(route: GalleryRoute.parse(route)), size: size);
  await t.pump();
}

/// Presses [keys] (apart by commas), a frame after each.
Future<void> keys(TwkTester t, String keys) async {
  for (final k in keys.split(',')) {
    await t.press(k);
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 500));
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

/// The row of the last rule across the page at [x]: the top of the
/// options under a narrow stage.
int lastRule(TwkTester t, int x) => t.lines.lastIndexWhere(
  (l) => l.length > x + 8 && l.substring(x).startsWith('─' * 8),
);

void main() {
  test('a title is cut to its columns by clusters, at either end, the '
      'blanks before the "…" left out', () {
    // a family emoji: one cluster two columns wide, of five code points
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}';
    expect(cut('${family}xy', 3), '$family…');
    expect(cut('xy$family', 3, start: true), '…$family');
    expect(cut('${family}xy', 2), '…');
    expect(cut('AnimatedAlign, AnimatedPadding', 16), 'AnimatedAlign,…');
    expect(cut('AnimatedAlign', 13), 'AnimatedAlign');
    expect(cut('a filter', 5, start: true), '…lter');
    expect(cut('a filter', 0), '');
  });

  testTwk("a page row lit under the mouse on the terminal's own colors, "
      "where the design's mix of a default color has none: the theme's "
      'hover', (t) async {
    await open(t, '#/controls/button?theme=terminal');
    // the first page row the sidebar shows, not the page open
    final y = t.lines.indexWhere((l) => l.contains('Badge'));
    expect(y, isNonNegative);
    final before = t.cell(2, y).bg;
    await t.mouse(MouseKind.move, 2, y);
    await t.pump();
    expect(t.cell(2, y).bg, isNot(before));
    expect(
      t,
      styleAt(2, y, hasBg(const ThemeData.terminal(Brightness.dark).hover.bg!)),
    );
  });

  group('a frame', () {
    for (final size in const [(120, 36), (80, 24), (160, 48), (100, 30)]) {
      testTwk('of the Text page at ${size.$1}x${size.$2}', (t) async {
        await open(t, '#/text/text?t=2000', size: size);
        final s = screen(t);
        expect(s, contains('twk gallery'));
        expect(s, contains('Preview'));
        expect(s, contains('Terminals draw text'));
        expect(problems(t), isEmpty);
        for (final line in t.lines) {
          expect(stringWidth(line), lessThanOrEqualTo(size.$1));
        }
      });
    }
  });

  // a test of its own for each page, with its own timeout and its own
  // failure naming the page
  group('a frame of every page at 80x24 and 120x36, without a problem', () {
    for (final g in catalog) {
      for (final p in g.pages) {
        final route = '#/${slug(g.title)}/${slug(p.title)}?t=2000';
        final title = p.title.length > 12 ? p.title.substring(0, 12) : p.title;
        testTwk(route, (t) async {
          // what the page logged at warning or worse; App › ErrorWidget's
          // own failed build is what that page shows
          List<String> found() => [
            for (final r in t.logs.records)
              if (r.level.index >= LogLevel.warning.index &&
                  !(route.startsWith('#/app/errorwidget') &&
                      r.level == LogLevel.error))
                '${r.level}: ${r.message.split('\n').first}',
          ];

          await open(t, route, size: (80, 24));
          expect(screen(t), contains(title), reason: '80x24');
          expect(found(), isEmpty, reason: '80x24');
          await t.resize(120, 36);
          await t.pump();
          expect(screen(t), contains(title), reason: '120x36');
          expect(found(), isEmpty, reason: '120x36');
        });
      }
    }
  });

  group('the list', () {
    testTwk('down and up choose the page; the header names it', (t) async {
      await open(t, '#/text/text?t=2000');
      await keys(t, 'down');
      expect(t.lines[0], contains('Text  ›  Rich text'));
      expect(t.lines[2], contains('2 of 4'));
      await keys(t, 'up,up');
      expect(t.lines[0], contains('Text  ›  Text'));
      await keys(t, 'end');
      expect(t.lines[0], contains('Terminal  ›  TerminalView'));
    });

    testTwk('tab goes into the page, escape back to the list', (t) async {
      await open(t, '#/controls/button?t=2000');
      expect(t.lines.last, contains('tab into the page'));
      await keys(t, 'tab');
      expect(t.lines.last, contains('enter press'));
      expect(t.lines.last, contains('esc pages'));
      await keys(t, 'enter');
      expect(screen(t), contains('saved: 1'));
      await keys(t, 'escape');
      expect(t.lines.last, contains('tab into the page'));
    });

    testTwk('a KeyHintsBar on the stage lists the keys of the list and '
        'the page', (t) async {
      await open(t, '#/controls/keyhintsbar?t=2000');
      // the stage's bar, not the shell's (the last row)
      final bar = t.lines.sublist(0, t.lines.length - 1).join('\n');
      // as the shell's bar names them: KeyHintsBar's default names the
      // arrows by their signs and joins those that share a hint
      expect(bar, contains('↑↓ pages   tab into'));
      await keys(t, 'tab');
      final inside = t.lines.sublist(0, t.lines.length - 1).join('\n');
      // the page's keys alone: the shell binds no Tab of its own there
      expect(inside, contains('ctrl+s save   ctrl+x ctrl+o open '));
      expect(inside, isNot(contains('tab next')));
      expect(t.lines.last, contains('ctrl+s save'));
      expect(t.lines.last, contains('shift+tab back'));
      expect(t.lines.last, contains('esc pages'));
      await keys(t, 'shift+tab,escape');
      expect(t.lines.last, contains('tab into the page'));
    });

    testTwk('/ filters the list, the matched letters lit', (t) async {
      await open(t, '#/text/text?t=2000');
      await keys(t, '/');
      expect(t.lines.last, contains('type to filter'));
      await t.type('spark');
      await t.pump();
      final s = screen(t);
      expect(s, contains('DATA'));
      expect(s, contains('Sparkline'));
      expect(s, isNot(contains('LAYOUT')));
      expect(t.lines[0], contains('Data  ›  Sparkline'));
      await keys(t, 'enter');
      expect(t.lines.last, contains('tab into the page'));
      await keys(t, 'escape');
      expect(screen(t), contains('SCROLLING'));
    });
  });

  group('the gallery keys', () {
    testTwk('c shows the Code, its lines numbered', (t) async {
      await open(t, '#/text/text?t=2000');
      await keys(t, 'c');
      final s = screen(t);
      expect(s, contains('final theme = Theme.of(context);'));
      expect(s, contains('⧉ copy'));
      await keys(t, 'c');
      expect(screen(t), contains('Terminals draw text'));
    });

    testTwk("the Code's comments are in the theme's muted colour", (t) async {
      await open(t, '#/editing/textfield?t=2000&tab=code');
      final y = t.lines.indexWhere((l) => l.contains('// '));
      expect(y, isNonNegative);
      final x = t.lines[y].indexOf('// ');
      final theme = galleryThemes['dark']!.$2;
      expect(t, styleAt(x, y, hasFg(theme.muted.fg!)));
      expect(t, styleAt(x, y, hasAttr(Attr.italic)));
    });

    testTwk('the hint bar names an arrow after a modifier', (t) async {
      await open(t, '#/controls/datepicker?t=2000');
      await keys(t, 'tab,up,up');
      expect(t.lines.last, contains('alt+↓'));
    });

    testTwk('t changes the theme and says so', (t) async {
      await open(t, '#/text/text?t=2000');
      await keys(t, 't');
      expect(t.lines[0], contains('◐ Light'));
      expect(screen(t), contains('Theme: Light'));
      // back past the first, to the last: the terminal's own colors
      await keys(t, 'T,T');
      expect(t.lines[0], contains('◐ Terminal'));
      await keys(t, 'T');
      expect(t.lines[0], contains('◐ Catppuccin Latte'));
    });

    testTwk('ctrl+p opens the palette, which finds and runs', (t) async {
      await open(t, '#/text/text?t=2000');
      await keys(t, 'ctrl+p');
      expect(screen(t), contains('Search pages, themes and actions'));
      expect(t.lines.last, contains('enter run'));
      await t.type('dialog');
      await t.pump();
      expect(screen(t), contains('Dialog'));
      await keys(t, 'enter');
      expect(t.lines[0], contains('Overlays  ›  Dialog'));
      expect(screen(t), isNot(contains('Search pages')));
    });

    testTwk('ctrl+p alone opens and closes it: ctrl+k is left to the '
        'widgets', (t) async {
      await open(t, '#/text/text?t=2000');
      await keys(t, 'ctrl+k');
      expect(screen(t), isNot(contains('Search pages')));
      await keys(t, 'ctrl+p');
      expect(screen(t), contains('Search pages, themes and actions'));
      await keys(t, 'ctrl+k');
      expect(screen(t), contains('Search pages, themes and actions'));
      await keys(t, 'ctrl+p');
      expect(screen(t), isNot(contains('Search pages')));
    });

    testTwk('on the CommandPalette page ctrl+k on the button opens the '
        "demo's palette, and nowhere else the gallery's", (t) async {
      await open(t, '#/overlays/commandpalette?t=2000');
      await keys(t, 'ctrl+k');
      expect(screen(t), isNot(contains('Search pages')));
      expect(screen(t), isNot(contains('Run tests')));
      await keys(t, 'tab,ctrl+k');
      expect(screen(t), contains('Run tests'));
      expect(screen(t), isNot(contains('Search pages')));
    });
  });

  group('the inspector', () {
    testTwk('an option steps with the arrows, and the Code follows', (t) async {
      await open(t, '#/text/text?t=2000&focus=o:wrap');
      expect(t.lines.last, contains('← previous'));
      await keys(t, 'right,right');
      await keys(t, 'c');
      expect(screen(t), contains('wrap: .none,'));
    });

    testTwk('up and down go from option to option', (t) async {
      await open(t, '#/text/text?t=2000&focus=o:wrap');
      await keys(t, 'down,down,down,down');
      expect(t.lines.last, contains('← decrease'));
      await keys(t, 'right');
      expect(screen(t), contains('33 cells'));
    });

    testTwk('at 80x24 a choice counts its rows as the design does', (t) async {
      // the step choice fits beside its label, not beside 14 columns: two
      // rows of the options, the stage a row less
      await open(t, '#/data/tasklist?t=2000', size: (80, 24));
      expect(lastRule(t, sidebarWidth(80)), 14);
    });

    testTwk('the route sets options', (t) async {
      await open(t, '#/text/text?t=2000&o=width:20;lines:1');
      expect(screen(t), contains('20 cells'));
      expect(screen(t), contains('20 × 3'));
    });

    testTwk('at 80x24 the options go under the stage and scroll', (t) async {
      await open(t, '#/text/text?t=2000&focus=o:width', size: (80, 24));
      expect(screen(t), contains('width'));
      expect(screen(t), contains('cells'));
      expect(problems(t), isEmpty);
    });
  });

  testTwk('on the app clock the motions run and end', (t) async {
    // down opens Gauge, which has a Code tab: c shows it and c again the
    // Preview, so that the palette opens Button on its Preview
    await open(t, '#/data/sparkline');
    await keys(t, 'down,t,c,c,ctrl+p');
    await t.type('button');
    await keys(t, 'enter,tab,enter');
    await t.pump(const Duration(seconds: 3));
    final s = screen(t);
    expect(t.lines[0], contains('Controls  ›  Button'));
    expect(t.lines[0], contains('◐ Light'));
    expect(s, contains('saved: 1'));
    expect(s, isNot(contains('Theme: Light')));
    expect(problems(t), isEmpty);
  });

  for (final size in const [(120, 36), (80, 24)]) {
    testTwk('codeIn writes the room the stage gives the widget at '
        '${size.$1}x${size.$2}', (t) async {
      final page = GalleryPage(
        group: 'Data',
        title: 'Table',
        options: const [SwitchOption('on', 'on')],
        build: (context, o) => LayoutBuilder(
          builder: (context, c) => Text('stage ${c.maxW} x ${c.maxH}'),
        ),
        codeIn: (o, room) => '// code ${room.width} x ${room.height}',
      );
      final route = GalleryRoute.parse('#/data/table?t=2000');
      await t.pumpWidget(
        GalleryShell(
          pages: [page],
          route: route,
          clock: Clock.frozen(route.t!),
        ),
        size: size,
      );
      await t.pump();
      final stage = RegExp(r'stage (\d+ x \d+)').firstMatch(screen(t));
      expect(stage, isNotNull);
      await keys(t, 'c');
      expect(screen(t), contains('// code ${stage!.group(1)}'));
      expect(problems(t), isEmpty);
    });
  }

  /// [page] alone in the gallery, at [route], in a terminal of [size].
  Future<void> openPage(
    TwkTester t,
    GalleryPage page,
    String route, {
    (int, int) size = (80, 24),
  }) async {
    final r = GalleryRoute.parse(route);
    await t.pumpWidget(
      GalleryShell(
        key: ValueKey(identityHashCode(page)),
        pages: [page],
        route: r,
        clock: Clock.frozen(r.t!),
      ),
      size: size,
    );
    await t.pump();
  }

  testTwk('a choice the options scrolled half away shows its rows left', (
    t,
  ) async {
    // sixteen sliders under a choice of two rows: the focus on the twelfth
    // scrolls the choice's first row away
    final page = GalleryPage(
      group: 'Data',
      title: 'Table',
      options: [
        ChoiceOption(
          'pick',
          'pick',
          values: [
            for (var i = 0; i < 12; i++) 'name${i.toString().padLeft(2, '0')}',
          ],
        ),
        for (var i = 0; i < 16; i++) SliderOption('s$i', 's$i', min: 0, max: 9),
      ],
      build: (context, o) => const Text('stage'),
    );
    await openPage(t, page, '#/data/table?t=2000&focus=o:s11');
    expect(screen(t), isNot(contains('name00')));
    expect(screen(t), contains('name11'));
    expect(problems(t), isEmpty);
  });

  testTwk('heightIn sizes a widget that fits itself to the room', (t) async {
    GalleryPage page({required bool fits}) => GalleryPage(
      group: 'Data',
      title: 'Table',
      options: [
        for (var i = 0; i < 6; i++)
          SliderOption('s$i', 'option $i', min: 0, max: 9),
      ],
      build: (context, o) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (var i = 0; i < 30; i++) Text('line $i')],
        ),
      ),
      heightIn: fits ? (o, room) => room.height < 30 ? room.height : 30 : null,
    );
    // asked uncapped, the scroll view wants its 30 lines: the options get
    // the least rows
    await openPage(t, page(fits: false), '#/data/table?t=2000');
    expect(screen(t), isNot(contains('option 5')));
    // in the room the whole options leave it, it takes that room
    await openPage(t, page(fits: true), '#/data/table?t=2000');
    expect(screen(t), contains('option 5'));
    expect(problems(t), isEmpty);
  });

  testTwk('at 80x24 the stage keeps the rows its widget asks for, the '
      'options under it scrolled', (t) async {
    // 13 rows and the marks' two leave the options two of the page's 17:
    // the rule and one, not the three that would cut the widget's last;
    // a new page for each route, so a new shell
    GalleryPage page() => GalleryPage(
      group: 'Data',
      title: 'Table',
      options: [
        for (var i = 0; i < 6; i++)
          SliderOption('s$i', 'option $i', min: 0, max: 9),
      ],
      build: (context, o) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < 13; i++) Text('row $i')],
      ),
    );
    await openPage(t, page(), '#/data/table?t=2000');
    expect(screen(t), contains('row 12'));
    expect(screen(t), contains('option 0'));
    expect(screen(t), isNot(contains('option 1')));
    expect(problems(t), isEmpty);
    // the focus scrolls them: the last in view, the widget still whole
    await openPage(t, page(), '#/data/table?t=2000&focus=o:s5');
    expect(screen(t), contains('option 5'));
    expect(screen(t), contains('row 12'));
    expect(problems(t), isEmpty);
  });

  testTwk('a widget that fits itself to the room is offered half of it '
      'where the whole options would leave it less', (t) async {
    // sixteen options take more than the 17 rows: the room they leave is
    // none, so the widget is offered 8 rows less its marks' two
    final page = GalleryPage(
      group: 'Data',
      title: 'Table',
      options: [
        for (var i = 0; i < 16; i++)
          SliderOption('s$i', 'option $i', min: 0, max: 9),
      ],
      build: (context, o) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (var i = 0; i < 30; i++) Text('line $i')],
        ),
      ),
      heightIn: (o, room) => room.height,
    );
    await openPage(t, page, '#/data/table?t=2000');
    expect(screen(t), contains('line 5'));
    expect(screen(t), isNot(contains('line 6')));
    expect(screen(t), contains('option 0'));
    expect(problems(t), isEmpty);
  });

  testTwk('a widget that needs more columns than the inspector beside the '
      'stage leaves it has the options under the stage', (t) async {
    GalleryPage page({int? minWidth}) => GalleryPage(
      group: 'Data',
      title: 'Table',
      options: const [SwitchOption('on', 'on')],
      minWidth: minWidth,
      build: (context, o) => LayoutBuilder(
        builder: (context, c) => Text('stage ${c.maxW} wide'),
      ),
    );
    // 120 columns: the page 92, the inspector beside the stage leaves the
    // widget 56; under it, the page's 92 less the marks' six
    await openPage(t, page(), '#/data/table?t=2000', size: (120, 36));
    expect(screen(t), contains('OPTIONS'));
    expect(screen(t), contains('stage 56 wide'));
    await openPage(
      t,
      page(minWidth: 82),
      '#/data/table?t=2000',
      size: (120, 36),
    );
    expect(screen(t), isNot(contains('OPTIONS')));
    expect(screen(t), contains('stage 86 wide'));
    expect(problems(t), isEmpty);
    // where the inspector leaves it enough, beside it
    await openPage(
      t,
      page(minWidth: 82),
      '#/data/table?t=2000',
      size: (160, 48),
    );
    expect(screen(t), contains('OPTIONS'));
    expect(problems(t), isEmpty);
  });

  testTwk("the stage's marks stay lit while the page's dialog or the "
      'palette has the focus', (t) async {
    bool lit() => t.widget<Stage>(find.byType(Stage)).focused;
    await open(t, '#/overlays/dialog?t=2000');
    await keys(t, 'tab');
    expect(lit(), isTrue);
    await keys(t, 'enter');
    expect(screen(t), contains('Delete 3 files?'));
    expect(lit(), isTrue);
    await keys(t, 'escape,ctrl+p');
    expect(screen(t), contains('Search pages'));
    expect(lit(), isTrue);
    await keys(t, 'escape,escape');
    expect(t.lines.last, contains('tab into the page'));
    expect(lit(), isFalse);
  });

  testTwk('while a layer holds a sequence, the bar lists what can follow', (
    t,
  ) async {
    final page = GalleryPage(
      group: 'Data',
      title: 'Table',
      build: (context, o) => KeyBindings(
        {'g g': () {}, 'x': () {}},
        hints: const {'g g': 'reset', 'x': 'cut'},
        child: Button('ok', onPressed: () {}),
      ),
    );
    await openPage(t, page, '#/data/table?t=2000&focus=page', size: (120, 36));
    expect(t.lines.last, contains('g g reset   x cut   tab next'));
    await keys(t, 'g');
    expect(t.lines.last.trim(), 'g reset');
  });

  for (final modalTab in const [true, false]) {
    testTwk('a modal of the page says tab next only where Tab moves '
        '(modalTab: $modalTab)', (t) async {
      final page = GalleryPage(
        group: 'Data',
        title: 'Table',
        modalTab: modalTab,
        build: (context, o) => Builder(
          builder: (context) => Button(
            'ask',
            onPressed: () => showDialog<void>(
              context,
              (context) => Dialog(
                title: 'Q',
                child: Button('ok', autofocus: true, onPressed: () {}),
              ),
            ),
          ),
        ),
      );
      await openPage(
        t,
        page,
        '#/data/table?t=2000&focus=page',
        size: (120, 36),
      );
      await keys(t, 'enter');
      expect(t.lines.last, contains('esc close'));
      expect(
        t.lines.last,
        modalTab ? contains('tab next') : isNot(contains('tab')),
      );
    });
  }

  testTwk("Tab in the page reaches the page's InputListener", (t) async {
    final heard = <String>[];
    final page = GalleryPage(
      group: 'Data',
      title: 'Table',
      build: (context, o) => InputListener(
        onEvent: (e) {
          if (e is KeyEvent && e.kind != KeyKind.release) {
            heard.add(GalleryShellState.keyName(e));
          }
          return false;
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          gap: 1,
          children: [
            Button('a', onPressed: () {}),
            Button('b', onPressed: () {}),
          ],
        ),
      ),
    );
    await openPage(t, page, '#/data/table?t=2000&focus=page', size: (120, 36));
    await keys(t, 'tab');
    expect(heard, contains('tab'));
    expect(t.lines.last, contains('esc pages'));
  });

  testTwk('PageHints lead the bar while the focus is in them', (t) async {
    final page = GalleryPage(
      group: 'Data',
      title: 'Table',
      build: (context, o) => const _Hinted(),
    );
    await openPage(t, page, '#/data/table?t=2000&focus=page', size: (120, 36));
    expect(
      t.lines.last,
      contains('type take over   enter press   x cut   tab next'),
    );
    // new hints, the focus where it was
    await keys(t, 'enter');
    expect(
      t.lines.last,
      contains('type take over   wheel scroll back   enter press   x cut'),
    );
    await keys(t, 'escape');
    expect(t.lines.last, isNot(contains('take over')));
  });

  testTwk("a page's state stays while the gallery runs", (t) async {
    await open(t, '#/controls/button?t=2000&focus=page');
    await keys(t, 'enter,enter');
    expect(screen(t), contains('saved: 2'));
    await keys(t, 'escape,down,up');
    expect(screen(t), contains('saved: 2'));
  });

  testTwk('a dialog opens over the page; its hints are its own', (t) async {
    await open(t, '#/overlays/dialog?t=2000');
    await keys(t, 'tab,enter');
    expect(screen(t), contains('Delete 3 files?'));
    expect(t.lines.last, contains('esc close'));
    await keys(t, 'escape');
    expect(screen(t), contains('answer: dismissed'));
  });

  testTwk('the route opens a toast, a filter and the palette', (t) async {
    await open(t, '#/text/text?t=2000&toast=Hello&kind=success&filter=box');
    expect(screen(t), contains('✓ Hello'));
    expect(screen(t), contains('SizedBox'));
    await open(t, '#/text/text?t=2000&palette=nord');
    expect(screen(t), contains('Theme: Nord'));
  });
}

/// A button under hints of its own, which press gives one more, in a layer
/// that binds x.
final class _Hinted extends StatefulWidget {
  const _Hinted();

  @override
  State<_Hinted> createState() => _HintedState();
}

final class _HintedState extends State<_Hinted> {
  var _more = false;

  @override
  Widget build(BuildContext context) => KeyBindings(
    {'x': () {}},
    hints: const {'x': 'cut'},
    child: PageHints(
      hints: [('type', 'take over'), if (_more) ('wheel', 'scroll back')],
      child: Button('more', onPressed: () => setState(() => _more = true)),
    ),
  );
}
