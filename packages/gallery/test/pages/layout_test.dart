// The Layout pages: each builds at both sizes, its options apply and its
// keys do what the design's do.
import 'package:gallery/gallery.dart';
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

/// Each page's route and a text its stage shows.
const _pages = {
  'layout/box': '2 warnings',
  'layout/coloredbox-decoratedbox': '3 commits, 2 fixes',
  'layout/container': 'deploy to staging',
  'layout/limitedbox-overflowbox': 'der than the box, cut off at',
  'layout/transform': 'moved',
  'layout/visibility-offstage': 'below the child',
  'layout/custompaint': 'cells of its own',
  'layout/scaffold': 'New note',
  'layout/divider': 'wheel scroll',
  'layout/shadow': 'a box with a shadow',
  'layout/padding': 'padded from the box',
  'layout/align-center': 'centred',
  'layout/sizedbox': '16 × 3',
  'layout/constrainedbox': 'within the bounds',
  'layout/fractionallysizedbox': '0.5 × 0.5',
  'layout/intrinsicwidth-height': 'Close window',
  'layout/row-column-flex': 'three',
  'layout/expanded-spacer': 'Expanded 1',
  'layout/stack-positioned': 'not positioned',
  'layout/grid-gridplacement': 'header · columnSpan: 3',
  'layout/wrap': '日本語',
  'layout/splitview': 'outline',
  'layout/dockarea': 'Dock them as they were',
};

void main() {
  group('each page builds', () {
    for (final size in const [(120, 36), (80, 24)]) {
      for (final MapEntry(key: page, value: shows) in _pages.entries) {
        testTwk('$page at ${size.$1}x${size.$2}', (t) async {
          await open(t, '#/$page?t=2000', size: size);
          expect(screen(t), contains(shows));
          expect(screen(t), isNot(contains('drawn in the next part')));
          expect(problems(t), isEmpty);
        });
      }
    }
  });

  group('the options apply', () {
    const routes = {
      'layout/box?o=border:double;sides:top bottom;at:topCenter;padding:0': [
        'type: .double',
        'top: theme.border',
        'bottom: theme.border',
        'alignment: .topCenter',
      ],
      'layout/box?o=titles:false;surface:true': ['style: theme.surface'],
      'layout/divider?o=type:heavy;merge:false': [
        'child: Divider(type: .heavy, style: theme.border),',
      ],
      'layout/shadow?o=offset:-2, -1;alpha:¾': [
        'BoxShadow(dx: -2, dy: -1, alpha: 0xc0)',
      ],
      'layout/padding?o=insets:left 3, top 1': [
        'padding: const .only(left: 3, top: 1),',
      ],
      'layout/align-center?o=ax:left;ay:top': ['alignment: .topLeft,'],
      'layout/sizedbox?o=kind:.shrink': ['SizedBox.shrink('],
      'layout/sizedbox?o=width:30;height:5': ['width: 30,', 'height: 5,'],
      'layout/constrainedbox?o=min:0;max:48': ['BoxConstraints(0, 48, 1, 3)'],
      'layout/fractionallysizedbox?o=wf:1;hf:¼;alignment:bottomRight': [
        'alignment: .bottomRight,',
        'widthFactor: 1.0,',
        'heightFactor: 0.25,',
      ],
      'layout/intrinsicwidth-height?o=iw:false': [
        '      menu,',
        'IntrinsicHeight(child: cards)',
      ],
      'layout/row-column-flex?o=dir:column;main:end;cross:stretch;gap:0': [
        'child: Column(',
        'mainAxisAlignment: .end,',
        'crossAxisAlignment: .stretch,',
      ],
      'layout/expanded-spacer?o=flex:3;fit:tight': ['flex: 3,', 'fit: .tight,'],
      'layout/stack-positioned?o=ax:right;ay:bottom;fit:passthrough': [
        'alignment: .bottomRight,',
        'fit: .passthrough,',
      ],
      'layout/grid-gridplacement?o=third:.fr(1);cg:0;rg:1': [
        '.fixed(12), .fr(1), .fr(1)]',
        'rowGap: 1,',
      ],
      'layout/wrap?o=alignment:center;runGap:1': [
        'alignment: .center,',
        'runGap: 1,',
      ],
      'layout/wrap?o=live:true': ['Timer.periodic('],
      'layout/coloredbox-decoratedbox?o=position:foreground;titles:false': [
        'position: .foreground,',
        'color: theme.selection.bg!,',
      ],
      'layout/container?o=fill:color;alignment:none;margin:0;foreground:true': [
        'color: theme.surface.bg,',
        'foregroundDecoration: BoxDecoration(',
      ],
      'layout/limitedbox-overflowbox?o=box:SizedOverflowBox;alignment:centerLeft':
          ['size: (16, 1),', 'alignment: .centerLeft,'],
      'layout/limitedbox-overflowbox?o=box:LimitedBox': ['maxHeight: 2,'],
      'layout/transform?o=move:fixed;dx:-3;dy:2': ['offset: (-3, 2),'],
      'layout/transform?o=move:round': [
        '_round[_step % _round.length]',
        'Timer.periodic(',
      ],
      'layout/visibility-offstage?o=keep:size': [
        'visible: false,',
        'maintainState: true,',
        'maintainSize: true,',
      ],
      'layout/visibility-offstage?o=widget:Offstage;hidden:false': [
        'offstage: false,',
      ],
      'layout/custompaint?o=paints:foregroundPainter;color:accent': [
        'foregroundPainter: WavePainter(_phase, theme.accent),',
      ],
      'layout/scaffold?o=width:36;side:right;resizable:false;hints:false': [
        'width: 36,',
        'sidebarSide: .right,',
        'keyHints: false,',
        'controller: _controller,',
      ],
      'layout/splitview?o=dir:vertical;share:false': [
        'direction: .vertical,',
        'minSize: 3,',
      ],
    };
    for (final MapEntry(key: route, value: code) in routes.entries) {
      testTwk('$route, in the Code', (t) async {
        await open(t, '#/$route&tab=code&t=2000', size: (160, 90));
        for (final c in code) {
          expect(screen(t), contains(c), reason: route);
        }
        expect(problems(t), isEmpty);
      });
    }

    testTwk('the stage follows them', (t) async {
      await open(t, '#/layout/sizedbox?o=kind:.expand&t=2000');
      expect(screen(t), contains('SizedBox.expand'));
      await open(t, '#/layout/fractionallysizedbox?o=wf:1;hf:¼&t=2000');
      expect(screen(t), contains('1.0 × 0.25'));
      await open(t, '#/layout/align-center?o=ax:left;ay:top&t=2000');
      expect(screen(t), contains('.topLeft'));
      await open(t, '#/layout/grid-gridplacement?o=third:.fixed(14)&t=2000');
      expect(screen(t), contains('fixed(14)'));
      await open(t, '#/layout/expanded-spacer?o=flex:2&t=2000');
      expect(screen(t), contains('Expanded 2'));
      expect(problems(t), isEmpty);
    });

    testTwk('a hidden child takes no room, or keeps it', (t) async {
      await open(t, '#/layout/visibility-offstage?t=2000');
      expect(screen(t), isNot(contains('the child │')));
      expect(
        t.lines.indexWhere((l) => l.contains('below the child')),
        t.lines.indexWhere((l) => l.contains('above the child')) + 1,
      );
      await open(t, '#/layout/visibility-offstage?o=keep:size&t=2000');
      expect(screen(t), isNot(contains('the child │')));
      expect(
        t.lines.indexWhere((l) => l.contains('below the child')),
        t.lines.indexWhere((l) => l.contains('above the child')) + 4,
      );
      await open(t, '#/layout/visibility-offstage?o=hidden:false&t=2000');
      expect(screen(t), contains('│ the child │'));
      expect(problems(t), isEmpty);
    });

    testTwk('the overflowing child is cut off where the alignment says', (
      t,
    ) async {
      await open(
        t,
        '#/layout/limitedbox-overflowbox?o=alignment:centerLeft&t=2000',
      );
      expect(screen(t), contains('│a line wider than the box, c│'));
      await open(
        t,
        '#/layout/limitedbox-overflowbox?o=alignment:centerRight&t=2000',
      );
      expect(screen(t), contains('│he box, cut off at its edges│'));
      expect(problems(t), isEmpty);
    });

    testTwk('the moved chip goes round on the clock', (t) async {
      await open(t, '#/layout/transform?t=0');
      final first = screen(t);
      await open(t, '#/layout/transform?t=600');
      expect(screen(t), isNot(first));
      // twelve steps of 200 ms round
      await open(t, '#/layout/transform?t=2400');
      expect(screen(t), first);
      expect(problems(t), isEmpty);
    });

    testTwk('the wave moves while moving is on, and stands without', (t) async {
      await open(t, '#/layout/custompaint?t=0');
      final still = screen(t);
      await open(t, '#/layout/custompaint?t=500');
      expect(screen(t), isNot(still));
      await open(t, '#/layout/custompaint?o=moving:false&t=500');
      final off = screen(t);
      await open(t, '#/layout/custompaint?o=moving:false&t=900');
      expect(screen(t), off);
      expect(problems(t), isEmpty);
    });

    testTwk('without titles the box shows none', (t) async {
      await open(t, '#/layout/box?o=titles:false&t=2000');
      expect(screen(t), isNot(contains('build')));
      expect(screen(t), isNot(contains('2 warnings')));
      expect(problems(t), isEmpty);
    });
  });

  group('the keys', () {
    testTwk('the arrows move a SplitView divider', (t) async {
      await open(t, '#/layout/splitview?t=2000');
      expect(screen(t), contains('fractions: 0.25  0.50  0.25'));
      await keys(t, 'tab,right,right');
      expect(screen(t), isNot(contains('fractions: 0.25  0.50  0.25')));
      expect(problems(t), isEmpty);
    });

    testTwk('End collapses the last pane', (t) async {
      await open(t, '#/layout/splitview?t=2000');
      await keys(t, 'tab,tab,end');
      expect(screen(t), contains('collapsed: {2}'));
      expect(screen(t), isNot(contains('outline')));
      expect(problems(t), isEmpty);
    });

    testTwk('the panes keep their sizes over a visit elsewhere', (t) async {
      await open(t, '#/layout/splitview?t=2000');
      await keys(t, 'tab,tab,end');
      expect(screen(t), contains('collapsed: {2}'));
      await keys(t, 'escape,down,up');
      expect(screen(t), contains('collapsed: {2}'));
      expect(problems(t), isEmpty);
    });

    testTwk('the arrows choose a DockArea tab', (t) async {
      await open(t, '#/layout/dockarea?t=2000');
      expect(screen(t), contains('Drag a tab'));
      await keys(t, 'tab,right');
      expect(screen(t), contains('Find in files.'));
      expect(problems(t), isEmpty);
    });

    testTwk('Add one counts, kept over a visit elsewhere', (t) async {
      await open(t, '#/layout/dockarea?t=2000');
      expect(screen(t), contains('count: 0'));
      await keys(t, 'tab,tab,tab,tab,enter');
      expect(screen(t), contains('count: 1'));
      await keys(t, 'escape,up,down');
      expect(screen(t), contains('count: 1'));
      expect(problems(t), isEmpty);
    });

    testTwk('narrowing moves the width option with the clock', (t) async {
      await open(t, '#/layout/wrap?o=live:true&t=0');
      expect(screen(t), contains('48 cells'));
      await open(t, '#/layout/wrap?o=live:true&t=1200');
      expect(screen(t), contains('38 cells'));
      expect(problems(t), isEmpty);
    });
  });

  group('the Scaffold page', () {
    /// Clicks the first cell of [text] on the screen.
    Future<void> clickOn(TwkTester t, String text) async {
      final y = t.lines.indexWhere((l) => l.contains(text));
      await t.click(t.lines[y].indexOf(text), y);
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
    }

    testTwk('opens with the focus in the list, which the arrows move', (
      t,
    ) async {
      await open(t, '#/layout/scaffold?t=2000');
      // the scaffold's body is not focused: its keys are not in the bar
      expect(screen(t), isNot(contains('f6 next pane')));
      await keys(t, 'down');
      expect(t.lines.first, contains('Theme'));
      expect(problems(t), isEmpty);
    });

    testTwk('Tab passes the zones by; a click focuses a node, whose zone '
        'keys F6 and Ctrl+B then work', (t) async {
      await open(t, '#/layout/scaffold?t=2000');
      await keys(t, 'tab');
      expect(screen(t), isNot(contains('f6 next pane')));
      await clickOn(t, 'New note');
      expect(screen(t), contains('notes: 4'));
      expect(screen(t), contains('4 notes'));
      expect(
        screen(t),
        contains('enter press   f6 next pane   ctrl+b sidebar'),
      );
      await keys(t, 'ctrl+b');
      expect(screen(t), contains('space toggle   f6 next pane   ctrl+b back'));
      await keys(t, 'space');
      expect(screen(t), contains('[ ] inbox'));
      await keys(t, 'tab,space');
      expect(screen(t), contains('[x] archive'));
      await keys(t, 'f6,enter');
      expect(screen(t), contains('notes: 5'));
      expect(problems(t), isEmpty);
    });

    testTwk('narrow, the sidebar is collapsed; Ctrl+B shows it and its way '
        'back hides it again', (t) async {
      await open(t, '#/layout/scaffold?o=width:36&t=2000');
      expect(screen(t), isNot(contains('inbox')));
      await clickOn(t, 'New note');
      await keys(t, 'ctrl+b');
      expect(screen(t), contains('[x] inbox'));
      await keys(t, 'ctrl+b');
      expect(screen(t), isNot(contains('inbox')));
      expect(problems(t), isEmpty);
    });

    testTwk("the header's toggle hides the sidebar; Alt+. widens it", (
      t,
    ) async {
      await open(t, '#/layout/scaffold?t=2000');
      final row = t.lines.indexWhere((l) => l.contains('[x] inbox'));
      final divider = t.lines[row].indexOf('│', t.lines[row].indexOf('inbox'));
      await clickOn(t, 'inbox');
      await keys(t, 'alt+.,alt+.');
      final wider = t.lines.indexWhere((l) => l.contains('inbox'));
      expect(
        t.lines[wider].indexOf('│', t.lines[wider].indexOf('inbox')),
        divider + 2,
      );
      await clickOn(t, '≡');
      expect(screen(t), isNot(contains('inbox')));
      expect(problems(t), isEmpty);
    });
  });
}
