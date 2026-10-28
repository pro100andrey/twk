// The Overlays and Navigation pages: each builds at both sizes, its options
// apply and its keys do what the design's do.
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

/// Types [text], then a frame.
Future<void> type(TwkTester t, String text) async {
  await t.type(text);
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
  'overlays/overlay': 'entries: 0 of the overlay',
  'overlays/dialog': 'answer: nothing',
  'overlays/toast': 'Show a toast',
  'overlays/tooltip': 'Share',
  'overlays/popover': 'Open',
  'overlays/menubar': 'chosen: nothing',
  'overlays/contextmenu': 'Right click in here.',
  'overlays/commandpalette': 'ran: nothing',
  'overlays/modalbarrier': 'pressed 0, the barrier 0',
  'overlays/windowlayer': 'The app, under its windows.',
  'navigation/navigator': 'Open item 7',
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

  // the Code tab's stage is as tall as the layer, as the design's
  // size(ctx).h says: the options under a narrow stage take the rest
  testTwk('WindowLayer: the Code tab is as tall as the layer at 80x24', (
    t,
  ) async {
    await open(t, '#/overlays/windowlayer?tab=code&t=2000', size: (80, 24));
    expect(screen(t), contains('super.dispose();'));
    expect(screen(t), contains('shadow'));
    expect(problems(t), isEmpty);
  });

  group('the options apply', () {
    final routes = <String, List<String>>{
      'overlays/overlay?o=position:bottomLeft;shadow:false': [
        'bottom: 7 - 2 * n',
        'shadow: false',
      ],
      'overlays/dialog?o=alignment:bottomRight;shadow:true': [
        'alignment: .bottomRight',
        'Panel.shadowOf',
      ],
      'overlays/toast?o=alignment:topRight;duration:5 s': [
        'alignment: .topRight',
        'Duration(seconds: 5)',
      ],
      'overlays/tooltip?o=wait:1 s': ['Duration(milliseconds: 1000)'],
      'overlays/popover?o=dismissible:false': ['Only the button closes it.'],
      'overlays/menubar?o=keys:false': ["() => _choose('Open')"],
      'overlays/commandpalette?o=width:60;rows:3': ['width: 60', 'rows: 3'],
      'overlays/modalbarrier?o=alpha:¾': ['alpha: 0xc0, // ¾'],
      'overlays/windowlayer?o=shadow:false;resizable:false': [
        'resizable: false',
      ],
      'navigation/navigator?o=backKey:none': ['backKey: null'],
      // the look every page of panels offers
      for (final page in const [
        'overlay',
        'dialog',
        'toast',
        'tooltip',
        'popover',
        'menubar',
        'contextmenu',
        'commandpalette',
      ])
        'overlays/$page?o=look:bordered': ['look: .bordered'],
      'overlays/dialog?o=dismissible:false': ['dismissible: false'],
      'overlays/windowlayer?o=frame:bordered;minimisable:false;'
          'maximisable:false': [
        'frame: .bordered',
        'minimisable: false',
        'maximisable: false',
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
      await open(t, '#/overlays/popover?o=dismissible:false&t=2000');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('Only the button closes it.'));
      await open(t, '#/overlays/windowlayer?o=shadow:false&t=2000');
      expect(screen(t), contains('Counter'));
      expect(problems(t), isEmpty);
    });

    testTwk('a bordered look draws the panels in a border', (t) async {
      await open(t, '#/overlays/popover?o=look:bordered&t=2000');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('│ The popover, by the button.'));
      await open(t, '#/overlays/dialog?o=look:bordered&t=2000');
      await keys(t, 'tab,enter');
      expect(screen(t), contains(' Delete ─'));
      expect(problems(t), isEmpty);
    });

    testTwk('a dialog that is not dismissible stays on Escape', (t) async {
      await open(t, '#/overlays/dialog?o=dismissible:false&t=2000');
      await keys(t, 'tab,enter,escape');
      expect(screen(t), contains('Delete 3 files?'));
      expect(t.lines.last, isNot(contains('esc')));
      await keys(t, 'tab,enter');
      expect(screen(t), contains('answer: kept'));
    });

    testTwk("the windows' frame and buttons follow them", (t) async {
      await open(t, '#/overlays/windowlayer?t=2000');
      expect(screen(t), contains('─ □ ×'));
      await open(t, '#/overlays/windowlayer?o=frame:bordered&t=2000');
      expect(screen(t), contains('_ □ ×'));
      await open(
        t,
        '#/overlays/windowlayer?o=minimisable:false;maximisable:false&t=2000',
      );
      expect(screen(t), isNot(contains('□')));
      expect(screen(t), contains('×'));
      expect(problems(t), isEmpty);
    });
  });

  group('the keys', () {
    testTwk('the buttons insert entries into the overlay and remove them', (
      t,
    ) async {
      await open(t, '#/overlays/overlay?t=2000');
      await keys(t, 'tab,enter,enter');
      expect(screen(t), contains('entries: 2 of the overlay'));
      expect(screen(t), contains('Entry 2 of the overlay'));
      await keys(t, 'tab,enter');
      expect(screen(t), contains('entries: 1 of the overlay'));
      expect(screen(t), isNot(contains('Entry 2')));
    });

    testTwk('a dialog asks, and Escape dismisses it', (t) async {
      await open(t, '#/overlays/dialog?t=2000');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('Delete 3 files?'));
      await keys(t, 'tab,enter');
      expect(screen(t), contains('answer: kept'));
      await keys(t, 'enter,escape');
      expect(screen(t), contains('answer: dismissed'));
    });

    testTwk('a toast shows, the next of four each time', (t) async {
      await open(t, '#/overlays/toast?t=2000');
      await keys(t, 'tab,enter,enter');
      expect(screen(t), contains('Saved 3 files.'));
      expect(screen(t), contains('Copied the path.'));
    });

    testTwk('a button with a tooltip shows a toast', (t) async {
      await open(t, '#/overlays/tooltip?t=2000');
      await keys(t, 'tab,tab,enter');
      expect(screen(t), contains('Opened'));
    });

    testTwk('Enter opens the popover, Escape closes it', (t) async {
      await open(t, '#/overlays/popover?t=2000');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('The popover, by the button.'));
      expect(screen(t), contains('Close'));
      await keys(t, 'escape');
      expect(screen(t), isNot(contains('The popover, by the button.')));
    });

    testTwk('F10 opens the menus; the arrows and Enter choose', (t) async {
      await open(t, '#/overlays/menubar?t=2000');
      await keys(t, 'tab,f10');
      expect(screen(t), contains('Open recent'));
      expect(screen(t), contains('ctrl+o'));
      // Edit opens on Undo; Down passes Redo, which cannot be chosen
      await keys(t, 'right,down,enter');
      expect(screen(t), contains('chosen: Cut'));
      await keys(t, 'ctrl+s');
      expect(screen(t), contains('chosen: Save'));
    });

    testTwk('View › Wrap lines flips the checkbox', (t) async {
      await open(t, '#/overlays/menubar?t=2000');
      expect(screen(t), contains('[x] wrap lines'));
      await keys(t, 'tab,alt+v,enter');
      expect(screen(t), contains('chosen: Wrap lines'));
      expect(screen(t), contains('[ ] wrap lines'));
    });

    testTwk('Shift+F10 opens the context menu; Paste waits for a copy', (
      t,
    ) async {
      await open(t, '#/overlays/contextmenu?t=2000');
      await keys(t, 'tab,shift+f10');
      expect(screen(t), contains('Select all'));
      await keys(t, 'down,enter');
      expect(screen(t), contains('chosen: Copy'));
      await keys(t, 'shift+f10,p');
      expect(screen(t), contains('chosen: Paste'));
    });

    testTwk('Ctrl+K opens the palette; typing finds, Enter runs', (t) async {
      await open(t, '#/overlays/commandpalette?t=2000');
      await keys(t, 'tab,ctrl+k');
      expect(screen(t), contains('Run tests'));
      await type(t, 'dep');
      await keys(t, 'enter');
      expect(screen(t), contains('ran: Deploy'));
      await keys(t, 'f8');
      expect(screen(t), contains('ran: Run tests'));
    });

    testTwk('the button under the barrier takes keys', (t) async {
      await open(t, '#/overlays/modalbarrier?t=2000');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('pressed 1, the barrier 0'));
    });

    testTwk('a window minimises to a chip, and closes', (t) async {
      await open(t, '#/overlays/windowlayer?t=2000');
      await keys(t, 'tab,m');
      expect(t.lines.last, contains('restore'));
      await keys(t, 'enter');
      expect(screen(t), contains('Drag me by the title bar'));
      await keys(t, 'x');
      expect(screen(t), isNot(contains('Notes')));
      await keys(t, 'tab,enter');
      expect(screen(t), contains('count: 1'));
    });

    // the design's shell takes the focus back to the list when the page's
    // focused stop goes and no stop is after it (shell.js, "the focus
    // moved past what is there"); twk leaves it on no node then
    for (final close in ['tab,x,x', 'tab,tab,x']) {
      testTwk('closing the last window takes the focus to the list: $close', (
        t,
      ) async {
        await open(t, '#/overlays/windowlayer?t=2000');
        await keys(t, close);
        final shell = t.state<GalleryShellState>(find.byType(GalleryShell));
        expect(shell.zone, Zone.list);
        expect(t.binding.focusManager.primaryFocus, isNotNull);
        expect(t.lines.last, contains('pages'));
        // Tab goes into the page again: the button that opens them
        await keys(t, 'tab,enter');
        expect(screen(t), contains('Drag me by the title bar'));
        expect(problems(t), isEmpty);
      });
    }

    testTwk('the navigator pushes routes; Escape pops them', (t) async {
      await open(t, '#/navigation/navigator?t=2000');
      await keys(t, 'tab,enter');
      expect(screen(t), contains('Item 7'));
      await keys(t, 'tab,enter');
      expect(screen(t), contains('Item 8'));
      await keys(t, 'escape');
      expect(screen(t), contains('Item 7'));
      await keys(t, 'escape');
      expect(screen(t), contains('Open /settings'));
    });

    testTwk('Open /settings pushes the named route', (t) async {
      await open(t, '#/navigation/navigator?o=backKey:backspace&t=2000');
      await keys(t, 'tab,tab,enter');
      expect(screen(t), contains('Settings'));
      await keys(t, 'backspace');
      expect(screen(t), contains('Open item 7'));
    });
  });
}
