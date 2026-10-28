// The pages that show twk's controllers: the Tooltip's, the
// CommandPalette's, the menus', CodeView's, MarkdownView's and the
// pickers'. Each opens what its controller opens, by a button or a route,
// as the design's page does.
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

/// Presses [keys] (apart by commas), a frame after each, then lets
/// [after] go by.
Future<void> keys(
  TwkTester t,
  String keys, {
  Duration after = const Duration(milliseconds: 500),
}) async {
  for (final k in keys.split(',')) {
    await t.press(k);
    await t.pump();
  }
  await t.pump(after);
}

/// The screen as text.
String screen(TwkTester t) => t.lines.join('\n');

/// What the app logged at warning or worse: an overflow, an error.
List<String> problems(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level.index >= LogLevel.warning.index) '${r.level}: ${r.message}',
];

void main() {
  group('the Tooltip page', () {
    for (final size in const [(120, 36), (80, 24)]) {
      testTwk('the focus on Share shows its message after the wait, Escape '
          'hides it, at ${size.$1}x${size.$2}', (t) async {
        await open(t, '#/overlays/tooltip', size: size);
        await keys(t, 'tab,tab,tab', after: Duration.zero);
        expect(screen(t), isNot(contains('Copies a link to it')));
        await t.pump(const Duration(milliseconds: 600));
        expect(screen(t), contains('Copies a link to it'));
        expect(screen(t), contains('Hide the tip'));
        await keys(t, 'escape');
        expect(screen(t), isNot(contains('Copies a link to it')));
        // Escape stopped at the tooltip: the focus is still on the page
        expect(screen(t), contains('Show the tip'));
        expect(screen(t), contains('enter press'));
        expect(problems(t), isEmpty);
      });
    }

    testTwk('the button shows the Share message at once until pressed '
        'again, whatever the focus does', (t) async {
      await open(t, '#/overlays/tooltip');
      // at once: no wait, only the fade in
      await keys(
        t,
        'tab,tab,tab,tab,enter',
        after: const Duration(milliseconds: 150),
      );
      expect(screen(t), contains('Copies a link to it'));
      expect(screen(t), contains('Hide the tip'));
      await keys(
        t,
        'shift+tab,shift+tab,shift+tab',
        after: const Duration(milliseconds: 700),
      );
      // on Save: its own message too, over the pinned one, which stays
      expect(screen(t), contains('Saves the file'));
      expect(screen(t), contains('a link to it'));
      await keys(t, 'tab,tab,tab,enter');
      expect(screen(t), isNot(contains('Copies a link to it')));
      expect(screen(t), contains('Show the tip'));
      expect(problems(t), isEmpty);
    });

    testTwk('on focus off: the focus shows no message; the Code says so', (
      t,
    ) async {
      await open(t, '#/overlays/tooltip?o=focus:false');
      await keys(t, 'tab,tab,tab', after: const Duration(seconds: 1));
      expect(screen(t), isNot(contains('Copies a link to it')));
      await open(
        t,
        '#/overlays/tooltip?o=focus:false;hover:false&tab=code',
        size: (120, 60),
      );
      expect(screen(t), contains('showOnFocus: false,'));
      expect(screen(t), contains('showOnHover: false,'));
      expect(problems(t), isEmpty);
    });
  });

  group('the CommandPalette page', () {
    for (final size in const [(120, 36), (80, 24)]) {
      testTwk('Dart files opens the palette with dart typed, the files '
          'commandsFor finds listed; one runs, at ${size.$1}x${size.$2}', (
        t,
      ) async {
        await open(t, '#/overlays/commandpalette', size: size);
        await keys(t, 'tab,tab,enter');
        expect(screen(t), contains('> dart'));
        expect(screen(t), contains('4 of 10'));
        expect(screen(t), contains('lib/src/theme.dart'));
        await keys(t, 'down,down,enter');
        expect(screen(t), isNot(contains('> dart')));
        expect(screen(t), contains('ran: open lib/src/theme.dart'));
        expect(problems(t), isEmpty);
      });
    }

    testTwk('the files come after the commands that match; off, only the '
        'commands', (t) async {
      await open(t, '#/overlays/commandpalette');
      await keys(t, 'tab,ctrl+k');
      await t.type('te');
      await t.pump(const Duration(milliseconds: 300));
      final rows = t.lines;
      final tests = rows.indexWhere((l) => l.contains('Run tests'));
      final theme = rows.indexWhere((l) => l.contains('lib/src/theme.dart'));
      expect(tests, greaterThan(0));
      expect(theme, greaterThan(tests));
      await keys(t, 'escape');
      await open(t, '#/overlays/commandpalette?o=files:false');
      await keys(t, 'tab,tab,enter');
      expect(screen(t), contains('no command matches'));
      expect(problems(t), isEmpty);
    });
  });

  group('the menu pages', () {
    for (final size in const [(120, 36), (80, 24)]) {
      testTwk('Recent files opens File › Open recent by the MenuController, '
          'its first entry highlighted, at ${size.$1}x${size.$2}', (t) async {
        await open(t, '#/overlays/menubar', size: size);
        await keys(t, 'tab,tab,enter');
        expect(screen(t), contains('overlay.dart'));
        expect(screen(t), contains('enter select'));
        await keys(t, 'down,enter');
        expect(screen(t), isNot(contains('overlay.dart')));
        expect(screen(t), contains('chosen: page.dart'));
        expect(problems(t), isEmpty);
      });

      testTwk('Open the menu opens the context menu at a cell of the box, '
          'at ${size.$1}x${size.$2}', (t) async {
        await open(t, '#/overlays/contextmenu', size: size);
        await keys(t, 'tab,tab,enter');
        final y = t.lines.indexWhere((l) => l.contains('Right click in here.'));
        final x = t.lines[y].indexOf('Right click in here.');
        // its top left at (22, 1) of the box, the panel's room before Cut
        expect(t.lines[y + 1].indexOf('Cut'), x + 22);
        await keys(t, 'down,enter');
        expect(screen(t), contains('chosen: Copy'));
        expect(problems(t), isEmpty);
      });
    }
  });

  group('the CodeView page', () {
    for (final size in const [(120, 36), (80, 24)]) {
      testTwk('to line 18 scrolls the ten rows to it, at '
          '${size.$1}x${size.$2}', (t) async {
        await open(t, '#/rich/codeview?o=rows:10;goto:least', size: size);
        await t.pump();
        expect(screen(t), contains('_count++'));
        expect(screen(t), isNot(contains("import 'package:twk/twk.dart';")));
        expect(problems(t), isEmpty);
      });
    }

    testTwk('find: n and N go round the matches, hinted while the view has '
        'the focus', (t) async {
      await open(t, '#/rich/codeview?o=find:true;rows:10');
      await keys(t, 'tab');
      expect(screen(t), contains('n next match'));
      expect(screen(t), contains('N previous match'));
      // from the first in the window on, the ninth on line 18: the view
      // scrolls to it
      await keys(t, 'n,n,n,n,n,n,n,n');
      expect(screen(t), isNot(contains('_count++')));
      await keys(t, 'n');
      expect(screen(t), contains('_count++'));
      expect(problems(t), isEmpty);
    });

    testTwk('the Code asks the controller what the options say', (t) async {
      await open(
        t,
        '#/rich/codeview?o=goto:%C2%BD;lit:13%E2%80%9316;find:true&tab=code',
        size: (120, 80),
      );
      expect(screen(t), contains("CodeViewController(query: 'count')"));
      expect(screen(t), contains('..scrollToLine(18, alignment: 0.5)'));
      expect(screen(t), contains('..highlightRange(13, 16);'));
      expect(screen(t), contains('controller: _code,'));
      expect(screen(t), isNot(contains('SingleChildScrollView')));
      expect(problems(t), isEmpty);
    });
  });

  group('the MarkdownView page', () {
    for (final size in const [(120, 36), (80, 24)]) {
      testTwk(
        'links go to the app: a click on the link to a heading scrolls to '
        'it by the controller and says what was tapped, at '
        '${size.$1}x${size.$2}',
        (t) async {
          await open(t, '#/rich/markdownview?o=links:the%20app', size: size);
          expect(screen(t), contains('tapped: nothing'));
          expect(screen(t), isNot(contains('Still to come')));
          final y = t.lines.indexWhere((l) => l.contains('still to come'));
          final x = t.lines[y].indexOf('still to come');
          await t.click(x + 2, y);
          await t.pump(const Duration(milliseconds: 100));
          expect(screen(t), contains('tapped: #still-to-come'));
          expect(screen(t), contains('Still to come'));
          expect(problems(t), isEmpty);
        },
      );
    }

    testTwk('links go to the terminal: a click taps nothing', (t) async {
      await open(t, '#/rich/markdownview');
      final y = t.lines.indexWhere((l) => l.contains('still to come'));
      final x = t.lines[y].indexOf('still to come');
      await t.click(x + 2, y);
      await t.pump(const Duration(milliseconds: 100));
      expect(screen(t), isNot(contains('tapped:')));
      expect(screen(t), isNot(contains('Still to come')));
      expect(problems(t), isEmpty);
    });
  });

  group('the picker pages', () {
    for (final size in const [(120, 36), (80, 24)]) {
      testTwk('Choose a fruit opens the Select by its PopupController, the '
          'focus in it, at ${size.$1}x${size.$2}', (t) async {
        await open(t, '#/controls/select-multiselect', size: size);
        await keys(t, 'tab,tab,tab,enter');
        expect(screen(t), contains('blueberry'));
        await keys(t, 'down,enter');
        expect(screen(t), isNot(contains('blueberry')));
        expect(screen(t), contains('apricot'));
        expect(problems(t), isEmpty);
      });

      testTwk('Calendar opens the calendar of the DatePicker, Enter picks the '
          'day, at ${size.$1}x${size.$2}', (t) async {
        await open(t, '#/controls/datepicker', size: size);
        await keys(t, 'tab,tab,enter');
        expect(screen(t), contains('October 2026'));
        await keys(t, 'right,enter');
        expect(screen(t), isNot(contains('October 2026')));
        expect(screen(t), contains('picked: Tuesday, 20 October'));
        expect(problems(t), isEmpty);
      });

      testTwk('lib/src takes the FilePicker there by its controller, at '
          '${size.$1}x${size.$2}', (t) async {
        await open(t, '#/controls/filepicker', size: size);
        await keys(t, 'tab,tab,tab,tab,tab,tab,tab,enter');
        expect(screen(t), contains('/home/user/twk/lib/src/'));
        expect(screen(t), contains('controls/'));
        expect(problems(t), isEmpty);
      });
    }
  });
}
