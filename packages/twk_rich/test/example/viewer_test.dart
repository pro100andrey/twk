// The viewer of example/viewer.dart: a Markdown file and the output of
// `git diff --color` (fixtures/), the keys and the wheel that scroll them,
// the mouse that selects and copies Markdown, Tab switching a diff's
// layout.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/viewer.dart' show Viewer;

/// The text of the fixture [name].
String fixture(String name) =>
    File('test/example/fixtures/$name').readAsStringSync();

/// Matches a cell in the color of [style].
Matcher fg(Style style) => hasFg(style.fg!);

void main() {
  group('a Markdown file', () {
    testTwk('shows its blocks below its name, in the styles of the theme', (
      t,
    ) async {
      await t.pumpWidget(
        Viewer('guide.md', fixture('guide.md')),
        size: (60, 16),
      );
      expect(
        t,
        matchesScreen('''
 guide.md  Markdown
 Greet

 A tool that greets people by name, in English, Ukrainian
 or Japanese (こんにちは). See the Dart site for the SDK.

 Usage

 Run it with the names to greet:

  dart run lib/greet.dart Ada Linus

 Each name is greeted on a line of its own:

 1. the names are read from the arguments;
↓ scroll   pgdn a window   end the ends   q quit
'''),
      );
      const theme = ThemeData.dark;
      expect(t, styleAt(1, 0, allOf(fg(theme.primary), hasAttr(Attr.bold))));
      expect(t, styleAt(11, 0, fg(theme.muted)));
      expect(
        t,
        styleAt(
          1,
          1,
          allOf(fg(theme.primary), hasAttr(Attr.bold | Attr.underline)),
        ),
      );
      expect(t, styleAt(1, 3, hasBg(theme.background.bg!)));
      expect(t.cell(31, 4).link, 'https://dart.dev');
      expect(t, styleAt(2, 10, hasBg(theme.surface.bg!)));
    });

    testTwk('PgDn and End scroll it, the wheel too', (t) async {
      await t.pumpWidget(
        Viewer('guide.md', fixture('guide.md')),
        size: (60, 16),
      );
      await t.press('pagedown');
      await t.pump();
      expect(
        t,
        matchesScreen(r'''
 guide.md  Markdown
 2. each is greeted in language, English by default;
    ◦ uk greets in Ukrainian,
    ◦ ja in Japanese.

 Code

  String greet(String name, {String language = 'en'}) {
    final hello = switch (language) {
      'uk' => 'Привіт',
      'ja' => 'こんにちは',
      _ => 'Hello',
    };
    return '$hello, $name!';
  }
↑↓ scroll   pgup pgdn a window   home end the ends   q quit
'''),
      );

      await t.press('end');
      await t.pump();
      expect(
        t,
        matchesScreen('''
 guide.md  Markdown
 ─────┼───────────┼────────────────────────────────────────
 en   │ English   │      Hello
 uk   │ Ukrainian │     Привіт
 ja   │ Japanese  │ こんにちは

 Plans

 ☑ greet in three languages
 ☐ read the names from a file
 ☐ greet in Latin

 ──────────────────────────────────────────────────────────

 Written for the viewer of twk_rich.
↑ scroll   pgup a window   home the ends   q quit
'''),
      );

      await t.mouse(MouseKind.wheelUp, 10, 5);
      await t.pump();
      expect(t.lines.sublist(1, 4), [
        ' Languages',
        '',
        ' code │ language  │   greeting',
      ]);
    });

    testTwk('a drag selects its text and copies it', (t) async {
      await t.pumpWidget(
        Viewer('guide.md', fixture('guide.md')),
        size: (60, 16),
      );
      await t.mouse(MouseKind.down, 13, 3);
      await t.mouse(MouseKind.drag, 25, 3);
      await t.mouse(MouseKind.up, 25, 3);
      await t.pump();
      expect(t, styleAt(13, 3, hasBg(ThemeData.dark.selection.bg!)));
      expect(
        t.written(),
        contains('\x1b]52;c;${base64.encode(utf8.encode('greets people'))}'),
      );
    });
  });

  group('the output of git diff --color', () {
    testTwk('shows as a unified diff without the colors it came in, in the '
        'diff styles of the theme', (t) async {
      await t.pumpWidget(
        Viewer('changes.diff', fixture('changes.diff')),
        size: (80, 16),
      );
      expect(
        t,
        matchesScreen('''
 changes.diff  2 files  +12 -7
docs/usage.md → docs/greet.md
 1  1   # Greet
 2  2
 3    - Run it with a name:
    3 + Run it with names:
 4  4
 5  5       dart run lib/greet.dart
 6  6
lib/greet.dart
 1  1   /// Greetings in a few languages.
 2  2   library;
 3  3
 4    - /// Greets [name].
 5    - String greet(String name) {
↓ scroll   pgdn a window   end the ends   q quit   tab side by side
'''),
      );
      final diff = DiffTheme.from(ThemeData.dark);
      expect(t, styleAt(0, 1, hasAttr(Attr.bold)));
      expect(t, styleAt(6, 4, fg(diff.removedSign)));
      expect(t, styleAt(6, 5, fg(diff.addedSign)));
      // a line removed and one added tinted apart, the words they changed
      // more
      int bg(int x, int y) => t.cell(x, y).bg;
      expect({
        bg(0, 2),
        bg(0, 4),
        bg(0, 5),
        bg(20, 4),
        bg(20, 5),
      }, hasLength(5));
    });

    testTwk('Tab shows it side by side, and unified again', (t) async {
      await t.pumpWidget(
        Viewer('changes.diff', fixture('changes.diff')),
        size: (80, 16),
      );
      await t.press('tab');
      await t.pump();
      expect(
        t,
        matchesScreen('''
 changes.diff  2 files  +12 -7
docs/usage.md → docs/greet.md
 1   # Greet                            │ 1   # Greet
 2                                      │ 2
 3 - Run it with a name:                │ 3 + Run it with names:
 4                                      │ 4
 5       dart run lib/greet.dart        │ 5       dart run lib/greet.dart
 6                                      │ 6
lib/greet.dart
 1   /// Greetings in a few languages.  │ 1   /// Greetings in a few languages.
 2   library;                           │ 2   library;
 3                                      │ 3
 4 - /// Greets [name].                 │ 4 + /// Greets [name], in [language] w
 5 - String greet(String name) {        │ 5 + String greet(String name, {String
 6 -   return 'Hello, ' + name + '!';   │ 6 +   final hello = switch (language)
↓ scroll   pgdn a window   end the ends   q quit   tab unified
'''),
      );

      await t.press('tab');
      await t.pump();
      expect(t.lines[4], ' 3    - Run it with a name:');
      expect(
        t.lines.last,
        '↓ scroll   pgdn a window   end the ends   q quit   tab side by side',
      );
    });
  });

  testTwk('a tab in colored output moves to the tab stops of the code, as '
      'in output without colors', (t) async {
    const colored =
        '\x1b[1m--- a/main.go\x1b[m\n'
        '\x1b[1m+++ b/main.go\x1b[m\n'
        '\x1b[36m@@ -1 +1 @@\x1b[m\n'
        '\x1b[31m-\x1b[m\x1b[31m\treturn 1\x1b[m\n'
        '\x1b[32m+\x1b[m\x1b[32m\treturn 2\x1b[m\n';
    await t.pumpWidget(const Viewer('go.diff', colored), size: (30, 5));
    expect(t.lines.sublist(1, 4), [
      'main.go',
      '1   -     return 1',
      '  1 +     return 2',
    ]);
  });

  testTwk('a diff without colors, as diff -u writes it, shows as a diff; a '
      'file whose name ends in .md, or with no diff in it, as Markdown', (
    t,
  ) async {
    const patch =
        '--- a.txt\t2026-10-19 10:00:00\n'
        '+++ b.txt\t2026-10-19 10:05:00\n'
        '@@ -1,2 +1,2 @@\n'
        ' one\n'
        '-two\n'
        '+three\n';
    await t.pumpWidget(const Viewer('a.patch', patch), size: (40, 6));
    expect(
      t,
      matchesScreen('''
 a.patch  1 file  +1 -1
a.txt → b.txt
1 1   one
2   - two
  2 + three
q quit   tab side by side
'''),
    );

    await t.pumpWidget(const Viewer('a.md', patch));
    expect(t.lines.first, ' a.md  Markdown');
    await t.pumpWidget(const Viewer('notes.txt', 'Some *notes*.'));
    expect(t.lines.sublist(0, 2), [' notes.txt  Markdown', ' Some notes.']);
    expect(t.lines.last, 'q quit');
  });

  testTwk('q quits', (t) async {
    await t.pumpWidget(Viewer('guide.md', fixture('guide.md')));
    await t.press('q');
    expect(t.isRunning, isFalse);
  });
}
