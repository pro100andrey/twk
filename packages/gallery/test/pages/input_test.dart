// The Scrolling, Mouse and Focus and keys pages: each builds at both
// sizes, its options apply, and its keys and the mouse do what the
// design's do; the hint bar over the Scrolling and Editing widgets, the
// hints they give themselves.
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
    await t.press(k == 'comma' ? ',' : k);
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 500));
}

/// Delivers the mouse report [kind] at ([x], [y]), then a frame.
Future<void> mouse(TwkTester t, MouseKind kind, int x, int y) async {
  await t.mouse(kind, x, y);
  await t.pump();
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// Where [text] starts on the screen, the first time it does.
(int, int) at(TwkTester t, String text) {
  for (final (y, line) in t.lines.indexed) {
    final x = line.indexOf(text);
    if (x >= 0) {
      return (x, y);
    }
  }
  throw StateError('"$text" is not on the screen:\n${screen(t)}');
}

/// The offset the line under a scrolling box says.
int offset(TwkTester t) =>
    int.parse(RegExp(r'offset (\d+) of').firstMatch(screen(t))!.group(1)!);

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

/// Each page's route and a text its stage shows.
const _pages = {
  'scrolling/singlechildscrollview': 'offset 0 of',
  'scrolling/scrollable': 'offset 0 of 94',
  'scrolling/listview': 'offset 0 of 94',
  'scrolling/scrollbar': 'row 8',
  'mouse/gesturedetector': 'tap, hold or drag me',
  'mouse/listener-mouseregion': 'nothing yet',
  'mouse/selectionarea': 'copied: nothing',
  'mouse/draggable-dragtarget': 'dropped: nothing',
  'focus-and-keys/focus-focusscope': 'focus: none',
  'focus-and-keys/keybindings-leaderkey': 'count: 0',
  'focus-and-keys/shortcuts-actions': 'did: nothing',
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
    // in the Code: what it says, and what it no longer does
    const routes = {
      'scrolling/singlechildscrollview?o=axis:horizontal': (
        ['scrollDirection: .horizontal', 'SizedBox(width: 24, child:'],
        <String>[],
      ),
      'scrolling/listview?o=items:growing;heights:different': (
        [
          'stickToBottom: true',
          '_reason(i) case final reason?',
          'Timer.periodic(',
        ],
        ['const _count'],
      ),
      'scrolling/scrollbar?o=visibility:onScroll;axes:both;color:primary': (
        ['visibility: .onScroll', 'style: theme.primary', 'axis: .horizontal'],
        <String>[],
      ),
      'mouse/gesturedetector?o=double:false;long:1 s': (
        ['longPressDuration: const Duration(seconds: 1)'],
        ['onDoubleTap'],
      ),
      'mouse/listener-mouseregion?o=cursor:crosshair': (
        ['cursor: .crosshair'],
        <String>[],
      ),
      'mouse/listener-mouseregion?o=cursor:none': (<String>[], ['cursor:']),
      'mouse/selectionarea?o=copy:false;style:reverse': (
        ['copyOnRelease: false', 'style: const Style(attrs: Attr.reverse)'],
        <String>[],
      ),
      'mouse/draggable-dragtarget?o=ghost:false': (
        ["'red only': <String>[],"],
        ['childWhenDragging'],
      ),
      'focus-and-keys/focus-focusscope?o=scope:false;two:unfocusable': (
        ['_Focusable(two, canRequestFocus: false)'],
        ['FocusScopeNode'],
      ),
      'focus-and-keys/keybindings-leaderkey'
          '?o=leader:space;timeout:none;unmatched:replay': (
        [
          'no LeaderKey above',
          'sequenceTimeout: null',
          'unmatched: .replay',
        ],
        ['return LeaderKey('],
      ),
      r'focus-and-keys/keybindings-leaderkey?o=leader:\': (
        [r"    r'\',"],
        <String>[],
      ),
      'focus-and-keys/shortcuts-actions?o=actions:false': (
        ['enabled: false,'],
        <String>[],
      ),
    };
    for (final MapEntry(key: route, value: (has, hasNot)) in routes.entries) {
      testTwk('$route, in the Code', (t) async {
        await open(t, '#/$route&tab=code&t=2000', size: (160, 90));
        for (final c in has) {
          expect(screen(t), contains(c), reason: route);
        }
        for (final c in hasNot) {
          expect(screen(t), isNot(contains(c)), reason: route);
        }
        expect(problems(t), isEmpty);
      });
    }

    testTwk('the stage follows them', (t) async {
      await open(t, '#/scrolling/singlechildscrollview?o=axis:horizontal');
      expect(screen(t), contains('offset 0 of 122'));
      await open(t, '#/scrolling/listview?o=items:1 000 000');
      expect(screen(t), contains('offset 0 of 999994'));
      await open(t, '#/scrolling/listview?o=heights:different');
      expect(screen(t), contains('│ row 2 of 4'));
      await open(t, '#/scrolling/scrollbar?o=axes:both');
      expect(screen(t), contains('2026-10-19 12:00:00'));
      await open(t, '#/focus-and-keys/focus-focusscope?o=scope:false');
      expect(screen(t), contains('│ three │ │ four │'));
      await open(t, '#/focus-and-keys/focus-focusscope');
      expect(screen(t), contains('│ three ││ four │'));
      expect(problems(t), isEmpty);
    });

    testTwk('the log grows on the gallery clock, and stands at t=', (t) async {
      await open(t, '#/scrolling/listview?o=items:growing&t=2000');
      expect(screen(t), contains('GET /items/12'));
      await t.pump(const Duration(seconds: 2));
      expect(screen(t), isNot(contains('GET /items/13')));
      await open(t, '#/scrolling/listview?o=items:growing');
      await t.pump(const Duration(milliseconds: 1300));
      expect(screen(t), contains('GET /items/14'));
    });
  });

  group('Scrolling', () {
    testTwk('the arrows, PageDown and End scroll the ruler', (t) async {
      await open(t, '#/scrolling/scrollable');
      await keys(t, 'tab,down,down');
      expect(screen(t), contains('offset 2 of 94'));
      await keys(t, 'pagedown');
      expect(screen(t), contains('offset 8 of 94'));
      await keys(t, 'end');
      expect(screen(t), contains('offset 94 of 94'));
      expect(screen(t), contains('100 ├─────────'));
    });

    testTwk('a notch of the wheel scrolls three cells', (t) async {
      await open(t, '#/scrolling/scrollable');
      final (x, y) = at(t, '  3 ├─');
      await mouse(t, MouseKind.wheelDown, x + 2, y);
      expect(offset(t), 3);
      await mouse(t, MouseKind.wheelUp, x + 2, y);
      expect(offset(t), 0);
    });

    testTwk('the button scrolls the next paragraph into view', (t) async {
      await open(t, '#/scrolling/singlechildscrollview');
      await keys(t, 'tab,pagedown');
      expect(offset(t), 6);
      await keys(t, 'home,tab');
      expect(offset(t), 0);
      for (var i = 0; i < 3; i++) {
        await keys(t, 'enter');
      }
      expect(offset(t), greaterThan(0));
      expect(screen(t), contains('A notch of the wheel'));
    });

    testTwk("the list's buttons move it to an item", (t) async {
      await open(t, '#/scrolling/listview');
      await keys(t, 'tab,tab,tab,enter');
      expect(screen(t), contains('item 40'));
      expect(screen(t), isNot(contains('item 41')));
      await keys(t, 'tab,enter');
      expect(screen(t), contains('item 51'));
      await keys(t, 'shift+tab,shift+tab,enter');
      expect(screen(t), contains('offset 0 of 94'));
    });

    testTwk('the Scrollbar list scrolls by keys and the wheel', (t) async {
      await open(t, '#/scrolling/scrollbar');
      await keys(t, 'tab,pagedown');
      expect(screen(t), contains('row 9 '));
      expect(screen(t), isNot(contains('row 1 ')));
      final (x, y) = at(t, 'row 9 ');
      await mouse(t, MouseKind.wheelDown, x, y);
      expect(screen(t), contains('row 12 '));
      expect(screen(t), isNot(contains('row 11 ')));
    });
  });

  group('the hints the widgets give', () {
    testTwk('a scroll view: the keys that would move it, from where it is', (
      t,
    ) async {
      await open(t, '#/scrolling/scrollable');
      await keys(t, 'tab');
      expect(t.lines.last, startsWith('  ↓ scroll   pgdn a window   end the'));
      await keys(t, 'down');
      expect(
        t.lines.last,
        startsWith('  ↑↓ scroll   pgup pgdn a window   home end the ends'),
      );
      await keys(t, 'end');
      expect(t.lines.last, startsWith('  ↑ scroll   pgup a window   home the'));
    });

    testTwk('a TextField: Enter submits, Ctrl+Z once there is a change', (
      t,
    ) async {
      await open(t, '#/editing/textfield');
      await keys(t, 'tab');
      expect(t.lines.last, startsWith('  enter submit   tab next'));
      await t.type('a');
      await t.pump();
      expect(t.lines.last, startsWith('  enter submit   ctrl+z undo'));
    });

    testTwk('a TextArea: Enter a new line, or submits', (t) async {
      await open(t, '#/editing/textarea');
      await keys(t, 'tab');
      expect(t.lines.last, startsWith('  enter new line   tab next'));
      await open(t, '#/editing/textarea?o=enter:submits');
      await keys(t, 'tab');
      expect(
        t.lines.last,
        startsWith('  enter submit   alt+enter new line   tab next'),
      );
    });

    testTwk("an Autocomplete: its keys while it suggests, the popover's "
        'Escape', (t) async {
      await open(t, '#/editing/autocomplete');
      await keys(t, 'tab');
      await t.type('/');
      await t.pump();
      expect(
        t.lines.last,
        startsWith(
          '  ↑↓ choose   enter put in   tab complete   ctrl+z undo   '
          'esc close',
        ),
      );
    });
  });

  group('Mouse', () {
    testTwk('a tap, a double tap and a long press', (t) async {
      await open(t, '#/mouse/gesturedetector');
      final (x, y) = at(t, 'tap, hold or drag me');
      await t.click(x, y);
      await t.pump(const Duration(milliseconds: 400));
      expect(screen(t), contains('taps 1, double 0, long 0'));
      expect(screen(t), contains('tap at '));
      await t.click(x, y);
      await t.pump();
      await t.click(x, y);
      await t.pump(const Duration(milliseconds: 400));
      expect(screen(t), contains('taps 1, double 1, long 0'));
      await mouse(t, MouseKind.down, x, y);
      await t.pump(const Duration(milliseconds: 600));
      await mouse(t, MouseKind.up, x, y);
      await t.pump(const Duration(milliseconds: 400));
      expect(screen(t), contains('taps 1, double 1, long 1'));
      expect(problems(t), isEmpty);
    });

    testTwk('without double taps a tap is told at once', (t) async {
      await open(t, '#/mouse/gesturedetector?o=double:false');
      final (x, y) = at(t, 'tap, hold or drag me');
      await t.click(x, y);
      await t.pump();
      await t.click(x, y);
      await t.pump();
      expect(screen(t), contains('taps 2, double 0'));
    });

    testTwk('a drag is told as it goes and where it ends', (t) async {
      await open(t, '#/mouse/gesturedetector');
      final (x, y) = at(t, 'tap, hold or drag me');
      await mouse(t, MouseKind.down, x, y);
      await mouse(t, MouseKind.drag, x + 2, y);
      await mouse(t, MouseKind.drag, x + 3, y + 1);
      expect(screen(t), contains('●'));
      expect(screen(t), contains('○'));
      await mouse(t, MouseKind.up, x + 3, y + 1);
      await t.pump(const Duration(milliseconds: 400));
      expect(screen(t), contains('dragged 3 across, 1 down'));
      expect(screen(t), contains('drag ended at '));
      expect(screen(t), contains('taps 0'));
    });

    testTwk('the Listener and the region hear the mouse', (t) async {
      await open(t, '#/mouse/listener-mouseregion');
      final (x, y) = at(t, 'move over me');
      await mouse(t, MouseKind.move, x, y);
      expect(screen(t), contains('the mouse is over me'));
      expect(screen(t), contains('enter at '));
      await mouse(t, MouseKind.down, x, y);
      await mouse(t, MouseKind.up, x, y);
      await mouse(t, MouseKind.wheelDown, x, y);
      expect(screen(t), contains('wheelDown at '));
      expect(screen(t), contains('release at '));
      expect(screen(t), contains('press of button 0 at '));
      await mouse(t, MouseKind.move, 1, 1);
      expect(screen(t), contains('move over me'));
      expect(screen(t), contains('exit at '));
      expect(problems(t), isEmpty);
    });

    testTwk('a drag selects text and copies it on release', (t) async {
      await open(t, '#/mouse/selectionarea');
      final (x, y) = at(t, 'An app that');
      await mouse(t, MouseKind.down, x, y);
      await mouse(t, MouseKind.drag, x + 5, y);
      await mouse(t, MouseKind.up, x + 5, y);
      await t.pump(const Duration(milliseconds: 500));
      expect(screen(t), contains('copied: An app'));
    });

    testTwk('without copy on release nothing is copied', (t) async {
      await open(t, '#/mouse/selectionarea?o=copy:false');
      final (x, y) = at(t, 'An app that');
      await mouse(t, MouseKind.down, x, y);
      await mouse(t, MouseKind.drag, x + 5, y);
      await mouse(t, MouseKind.up, x + 5, y);
      await t.pump(const Duration(milliseconds: 500));
      expect(screen(t), contains('copied: nothing'));
    });

    testTwk('fruit dropped in a box, and refused by the red one', (t) async {
      await open(t, '#/mouse/draggable-dragtarget');
      var (x, y) = at(t, 'apple');
      final (bx, by) = at(t, 'drop here');
      await mouse(t, MouseKind.down, x, y);
      await mouse(t, MouseKind.drag, x + 1, y);
      // the chip follows the mouse: below the rows the box shows
      await mouse(t, MouseKind.drag, bx, by + 2);
      expect(screen(t), contains('+ apple'));
      await mouse(t, MouseKind.up, bx, by + 2);
      await t.pump(const Duration(milliseconds: 500));
      expect(screen(t), contains('dropped: apple → basket'));
      (x, y) = at(t, 'banana');
      final (rx, ry) = at(t, 'red only ');
      await mouse(t, MouseKind.down, x, y);
      await mouse(t, MouseKind.drag, x + 1, y);
      await mouse(t, MouseKind.drag, rx, ry + 3);
      expect(screen(t), contains('✗ red only'));
      await mouse(t, MouseKind.up, rx, ry + 3);
      await t.pump(const Duration(milliseconds: 500));
      expect(screen(t), contains('dropped: banana, back to the bowl'));
      expect(problems(t), isEmpty);
    });
  });

  group('Focus and keys', () {
    testTwk('Tab goes through the nodes and round the scope', (t) async {
      await open(t, '#/focus-and-keys/focus-focusscope');
      await keys(t, 'tab');
      expect(screen(t), contains('focus: one'));
      await keys(t, 'tab,tab');
      expect(screen(t), contains('focus: three'));
      await keys(t, 'tab');
      expect(screen(t), contains('focus: four'));
      await keys(t, 'tab');
      expect(screen(t), contains('focus: three'));
    });

    testTwk('a node that skips Tab, and a click that focuses it', (t) async {
      await open(t, '#/focus-and-keys/focus-focusscope?o=two:skips Tab');
      await keys(t, 'tab,tab');
      expect(screen(t), contains('focus: three'));
      final (x, y) = at(t, ' two ');
      await t.click(x + 1, y);
      await t.pump();
      expect(screen(t), contains('focus: two'));
    });

    testTwk('an unfocusable node takes no click', (t) async {
      await open(t, '#/focus-and-keys/focus-focusscope?o=two:unfocusable');
      final (x, y) = at(t, ' two ');
      await t.click(x + 1, y);
      await t.pump();
      expect(screen(t), contains('focus: none'));
      await keys(t, 'tab,tab');
      expect(screen(t), contains('focus: three'));
    });

    testTwk('keys and sequences step the count', (t) async {
      await open(t, '#/focus-and-keys/keybindings-leaderkey');
      expect(screen(t), isNot(contains('+ more')));
      await keys(t, 'tab');
      expect(screen(t), contains('+ more   - less   g g reset   , r reset'));
      await keys(t, '+,+,+,-');
      expect(screen(t), contains('count: 2'));
      await keys(t, 'g,g');
      expect(screen(t), contains('count: 0'));
      await keys(t, '+,comma,r');
      expect(screen(t), contains('count: 0'));
    });

    testTwk('a held sequence shows what can follow', (t) async {
      await open(t, '#/focus-and-keys/keybindings-leaderkey?o=timeout:none');
      await keys(t, 'tab,g');
      expect(screen(t), contains('g reset'));
      expect(screen(t), isNot(contains('+ more')));
      await keys(t, 'x');
      expect(screen(t), contains('+ more'));
    });

    testTwk('Space as the leader', (t) async {
      await open(t, '#/focus-and-keys/keybindings-leaderkey?o=leader:space');
      await keys(t, 'tab,+,space,r');
      expect(screen(t), contains('count: 0'));
    });

    testTwk('the arrows go to the actions, or past them', (t) async {
      await open(t, '#/focus-and-keys/shortcuts-actions');
      await keys(t, 'tab');
      expect(screen(t), contains('↑ step up   ↓ step down'));
      await keys(t, 'up,up,down');
      expect(screen(t), contains('count: 1'));
      expect(screen(t), contains('did: ↓ _Down → its action stepped down'));
      await open(t, '#/focus-and-keys/shortcuts-actions?o=actions:false');
      await keys(t, 'tab,up');
      // the two keys, apart or joined as the bar puts those of one hint
      expect(
        screen(t),
        anyOf(contains('↑ passed on   ↓ passed on'), contains('↑↓ passed on')),
      );
      expect(screen(t), contains('count: 0'));
      expect(screen(t), contains('did: ↑ _Up → passed on to the KeyBindings'));
    });
  });
}
