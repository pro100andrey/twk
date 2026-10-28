// The pages and options round 3 gave the Editing, Mouse and Focus and keys
// groups: each new page builds at both sizes, its options apply, and its
// keys and the mouse do what the design's do.
import 'dart:convert';

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

/// A click at ([x], [y]): a press and a release.
Future<void> click(TwkTester t, int x, int y) async {
  await mouse(t, MouseKind.down, x, y);
  await mouse(t, MouseKind.up, x, y);
}

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

/// The texts the app put on the clipboard (OSC 52), in order.
List<String> clips(TwkTester t) => [
  for (final m in RegExp(r'\x1b\]52;c;([A-Za-z0-9+/=]*)').allMatches(
    utf8.decode([
      for (final f in t.terminal.frames) ...f,
    ], allowMalformed: true),
  ))
    utf8.decode(base64.decode(m.group(1)!)),
];

/// The row of the screen [text] is on, between the box's sides.
String fieldRow(TwkTester t, String text) {
  final (x, y) = at(t, text);
  final line = t.lines[y];
  final left = line.lastIndexOf('│', x);
  return line.substring(left + 1, line.indexOf('│', x));
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

/// Each new page's route and a text its stage shows.
const _pages = {
  'focus-and-keys/excludefocus': 'focus: none',
  'mouse/ignorepointer-absorbpointer': 'heard: nothing',
};

/// The page titled [title].
GalleryPage _page(String title) =>
    galleryPages.firstWhere((p) => p.title == title);

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

  group('ExcludeFocus', () {
    testTwk('Tab passes the excluded nodes by', (t) async {
      await open(t, '#/focus-and-keys/excludefocus?t=2000&keys=tab');
      await keys(t, 'tab');
      expect(screen(t), contains('focus: one'));
      await keys(t, 'tab');
      expect(screen(t), contains('focus: four'));
    });

    testTwk('not excluding, Tab goes through them', (t) async {
      await open(t, '#/focus-and-keys/excludefocus?o=excluding:false&t=2000');
      await keys(t, 'tab,tab');
      expect(screen(t), contains('focus: two'));
      await keys(t, 'tab');
      expect(screen(t), contains('focus: three'));
      await keys(t, 'tab');
      expect(screen(t), contains('focus: four'));
    });

    test('the Code follows the option', () {
      final page = _page('ExcludeFocus');
      final o = Options.initial(page);
      expect(page.codeOf(o), contains('excluding: true,'));
      expect(page.codeOf(o), contains('_Focusable(two, muted: true),'));
      final off = o.withRaw('excluding', false);
      expect(page.codeOf(off), contains('excluding: false,'));
      expect(page.codeOf(off), contains('_Focusable(two),'));
    });
  });

  group('IgnorePointer, AbsorbPointer', () {
    const route = '#/mouse/ignorepointer-absorbpointer?t=2000';

    /// A click on the button, then on the backdrop beside it: what heard
    /// each.
    Future<List<String>> clicks(TwkTester t, String gate) async {
      await open(t, '$route&o=gate:$gate');
      final (x, y) = at(t, 'click me');
      final heard = <String>[];
      String line() =>
          RegExp('heard: (nothing|the [a-z]+)')
              .firstMatch(screen(t))!
              .group(1)!;
      await click(t, x + 2, y);
      heard.add(line());
      final (bx, by) = at(t, 'backdrop');
      await click(t, bx, by + 1);
      heard.add(line());
      return heard;
    }

    testTwk('none: the button hears its click', (t) async {
      expect(await clicks(t, 'none'), ['the button', 'the backdrop']);
    });

    testTwk('IgnorePointer: the click goes on to the backdrop', (t) async {
      final heard = await clicks(t, 'IgnorePointer');
      expect(heard, ['the backdrop', 'the backdrop']);
    });

    testTwk('AbsorbPointer: the click stops at the button', (t) async {
      expect(await clicks(t, 'AbsorbPointer'), ['nothing', 'the backdrop']);
    });

    testTwk('the mouse over the button lights it, but ignored', (t) async {
      for (final gate in ['none', 'IgnorePointer']) {
        await open(t, '$route&o=gate:$gate');
        final (x, y) = at(t, 'click me');
        expect(t.cell(x - 3, y).text, '│');
        final before = t.cell(x - 3, y).fg;
        await mouse(t, MouseKind.move, x, y);
        expect(t.cell(x - 3, y).fg != before, gate == 'none', reason: gate);
      }
    });

    test('the Code wraps the button as the option says', () {
      final page = _page('IgnorePointer, AbsorbPointer');
      final o = Options.initial(page);
      expect(page.codeOf(o), contains('child: IgnorePointer('));
      expect(
        page.codeOf(o.withRaw('gate', 2)),
        contains('child: AbsorbPointer('),
      );
      final none = page.codeOf(o.withRaw('gate', 0))!;
      expect(none, contains('child: MouseRegion('));
      expect(none, isNot(contains('Pointer(')));
    });
  });

  group('TextField', () {
    const route = '#/editing/textfield?t=2000';

    testTwk('read only, typing changes nothing; the keys still select and '
        'Ctrl+C copies, Ctrl+X does not cut', (t) async {
      await open(t, '$route&o=readOnly:true');
      await keys(t, 'tab');
      await t.type('hi');
      await t.pump();
      expect(screen(t), contains('type here'));
      await t.paste('pasted');
      await t.pump();
      expect(screen(t), isNot(contains('pasted ')));
      expect(screen(t), contains('heard: a paste of 6 characters'));
    });

    testTwk('Ctrl+C copies the selection, Ctrl+X cuts it; hinted while '
        'something is selected', (t) async {
      await open(t, route);
      await keys(t, 'tab');
      await t.type('hello');
      await t.pump();
      expect(t.lines.last, isNot(contains('ctrl+c')));
      await keys(t, 'shift+left,shift+left');
      expect(t.lines.last, contains('ctrl+c copy'));
      expect(t.lines.last, contains('ctrl+x cut'));
      await keys(t, 'ctrl+c');
      expect(clips(t), ['lo']);
      await keys(t, 'ctrl+x');
      expect(clips(t), ['lo', 'lo']);
      expect(fieldRow(t, 'hel').trim(), 'hel');
    });

    testTwk('disabled, Tab passes it by and nothing is typed', (t) async {
      await open(t, '$route&o=enabled:false');
      await keys(t, 'tab');
      await t.type('zz');
      await t.pump();
      expect(screen(t), contains('type here'));
      expect(screen(t), isNot(contains('zz')));
    });

    testTwk('textAlign puts a short text at the right', (t) async {
      await open(t, '$route&o=align:right');
      await keys(t, 'tab');
      await t.type('hello');
      await t.pump();
      // the field is 28 columns: the text, then the caret's column
      expect(fieldRow(t, 'hello'), '${' ' * 22}hello ');
    });

    testTwk('a paste taken by onPaste does not go in', (t) async {
      await open(t, '$route&o=paste:taken');
      await keys(t, 'tab');
      await t.paste('abc');
      await t.pump();
      expect(screen(t), contains('heard: a paste of 3 characters'));
      expect(screen(t), contains('type here'));
    });

    testTwk('onEditingComplete as the focus leaves after a change', (t) async {
      await open(t, route);
      await keys(t, 'tab');
      await t.type('x');
      await t.pump();
      expect(screen(t), contains('heard: nothing'));
      await keys(t, 'tab');
      expect(screen(t), contains('heard: editing complete'));
    });

    test('the Code follows the options', () {
      final page = _page('TextField');
      final o = Options.initial(page);
      final code = page.codeOf(o)!;
      expect(code, isNot(contains('textAlign')));
      expect(code, contains('return false;'));
      final all = o
          .withRaw('align', 1)
          .withRaw('readOnly', true)
          .withRaw('enabled', false)
          .withRaw('paste', 1);
      expect(
        page.codeOf(all),
        allOf([
          contains('textAlign: .center,'),
          contains('readOnly: true,'),
          contains('enabled: false,'),
          contains('return true;'),
        ]),
      );
    });
  });

  group('TextArea', () {
    const route = '#/editing/textarea?t=2000';

    testTwk('read only, Enter and typing change nothing', (t) async {
      await open(t, '$route&o=readOnly:true');
      await keys(t, 'tab,enter');
      await t.type('q');
      await t.pump();
      expect(screen(t), contains('line 2 of 2'));
      expect(screen(t), isNot(contains('q')));
    });

    testTwk('Ctrl+C copies the selection with its line break', (t) async {
      await open(t, route);
      await keys(t, 'tab,shift+up,ctrl+c');
      expect(clips(t).single, contains('\n'));
    });

    test('the Code follows the options', () {
      final page = _page('TextArea');
      final o = Options.initial(page);
      expect(page.codeOf(o), isNot(contains('readOnly')));
      final off = o.withRaw('readOnly', true).withRaw('enabled', false);
      expect(page.codeOf(off), contains('readOnly: true,'));
      expect(page.codeOf(off), contains('enabled: false,'));
    });
  });

  group('SelectionArea over a painted log', () {
    const route = '#/mouse/selectionarea?t=2000&o=view:a%20painted%20log';

    testTwk('a drag selects across its lines, the numbers left out, and '
        'copies on release', (t) async {
      await open(t, route);
      final (x, y) = at(t, '12:00:01');
      await mouse(t, MouseKind.down, x, y);
      await mouse(t, MouseKind.drag, x + 4, y + 1);
      await mouse(t, MouseKind.up, x + 4, y + 1);
      expect(clips(t), ['12:00:01 GET /files/1 200\n12:00']);
      expect(screen(t), contains('copied: 12:00:01 GET /files/1 200 12:00'));
    });

    testTwk('a drag past its bottom scrolls it, every 50 ms while the '
        'mouse stays there', (t) async {
      await open(t, route);
      final (x, y) = at(t, '12:00:01');
      await mouse(t, MouseKind.down, x, y);
      // two rows past the last of the five
      await mouse(t, MouseKind.drag, x, y + 6);
      expect(screen(t), contains('12:00:03'));
      expect(screen(t), isNot(contains('12:00:01')));
      await t.pump(const Duration(milliseconds: 50));
      expect(screen(t), contains('12:00:05'));
      await t.pump(const Duration(milliseconds: 500));
      expect(screen(t), contains('12:00:20'));
      await mouse(t, MouseKind.up, x, y + 6);
      expect(clips(t).single, startsWith('12:00:01'));
      expect(clips(t).single, endsWith('12:00:20 GET /files/20 200\n'));
    });

    testTwk('with the focus in it, Escape clears the selection, hinted', (
      t,
    ) async {
      await open(t, route);
      await keys(t, 'tab');
      final (x, y) = at(t, '12:00:01');
      await mouse(t, MouseKind.down, x, y);
      await mouse(t, MouseKind.drag, x + 3, y);
      await mouse(t, MouseKind.up, x + 3, y);
      final selected = t.cell(x, y).bg;
      expect(t.lines.last, contains('esc clear'));
      await keys(t, 'escape');
      expect(t.cell(x, y).bg, isNot(selected));
      expect(t.lines.last, isNot(contains('esc clear')));
      // still on the page
      expect(screen(t), contains('12:00:01'));
    });

    test('the Code builds the Selectable', () {
      final page = _page('SelectionArea');
      final code = page.codeOf(Options.initial(page).withRaw('view', 1))!;
      expect(code, contains('with Selectable'));
      expect(code, contains('bool scrollSelectionBy(int rows)'));
    });
  });
}
