// The diff view: a fixed diff unified and side by side, the gutter, the
// words changed marked over the syntax colors, rows for files and for the
// lines left out, each side lexed as one source, the colors of the theme
// on dark and light terminals, and a diff of fifty thousand lines building
// and lexing only what it shows.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

const source = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,4 +1,4 @@
 void main() {
-  print('hello');
+  print('hi');
   return;
 }
@@ -10,4 +10,3 @@ void other() {
 a();
-b(1);
-c(2);
+b(3);
 d();
''';

const theme = DiffTheme(
  added: Style(bg: Color.rgb(0, 64, 0)),
  removed: Style(bg: Color.rgb(64, 0, 0)),
  addedWords: Style(bg: Color.rgb(0, 128, 0)),
  removedWords: Style(bg: Color.rgb(128, 0, 0)),
  addedSign: Style(fg: Color.rgb(0, 255, 0)),
  removedSign: Style(fg: Color.rgb(255, 0, 0)),
  lineNumbers: Style(fg: Color.rgb(100, 100, 100)),
  collapsed: Style(fg: Color.rgb(1, 1, 1), bg: Color.rgb(2, 2, 2)),
  file: Style(fg: Color.rgb(3, 3, 3), attrs: Attr.bold),
  divider: Style(fg: Color.rgb(4, 4, 4)),
);

const syntax = SyntaxTheme(
  keyword: Style(fg: Color.rgb(10, 10, 10)),
  function: Style(fg: Color.rgb(11, 11, 11)),
  string: Style(fg: Color.rgb(12, 12, 12)),
  comment: Style(fg: Color.rgb(13, 13, 13)),
);

/// [diff] in [layout], in [theme] and [syntax].
Widget view(Diff diff, [DiffLayout layout = DiffLayout.unified]) =>
    SyntaxThemeScope(
      theme: syntax,
      child: DiffView(diff, layout: layout, theme: theme),
    );

/// Counts the lines it lexes, each a plain token.
final class CountingLexer extends Lexer {
  CountingLexer(this.lexed);

  final List<int> lexed;

  @override
  Object? lexLine(TokenScanner s, Object? state) {
    lexed[0]++;
    return null;
  }
}

void main() {
  testTwk('shows a diff unified: a gutter of both numbers and the sign, '
      'a row for the file and one for the lines left out', (t) async {
    await t.pumpWidget(view(Diff.parse(source)), size: (42, 12));
    expect(t.lines, [
      'lib/a.dart',
      ' 1  1   void main() {',
      " 2    -   print('hello');",
      "    2 +   print('hi');",
      ' 3  3     return;',
      ' 4  4   }',
      '      ⋯ 5 unchanged lines  void other() {',
      '10 10   a();',
      '11    - b(1);',
      '12    - c(2);',
      '   11 + b(3);',
      '13 12   d();',
    ]);
  });

  testTwk('shows a diff side by side: the old side on the left, the new on '
      'the right, a removed line beside the line added in its place', (
    t,
  ) async {
    await t.pumpWidget(
      view(Diff.parse(source), DiffLayout.sideBySide),
      size: (49, 11),
    );
    expect(t.lines, [
      'lib/a.dart',
      ' 1   void main() {      │ 1   void main() {',
      " 2 -   print('hello');  │ 2 +   print('hi');",
      ' 3     return;          │ 3     return;',
      ' 4   }                  │ 4   }',
      '   ⋯ 5 unchanged lines  void other() {',
      '10   a();               │10   a();',
      '11 - b(1);              │11 + b(3);',
      '12 - c(2);              │',
      '13   d();               │12   d();',
      '',
    ]);
    expect(t, styleAt(24, 1, hasFg(const Color.rgb(4, 4, 4))));
  });

  testTwk('colors the rows of lines removed and added, their numbers and '
      'signs, and marks the words they changed over the syntax colors', (
    t,
  ) async {
    await t.pumpWidget(view(Diff.parse(source)), size: (42, 12));
    const removed = Color.rgb(64, 0, 0);
    const added = Color.rgb(0, 64, 0);
    // the row of -  print('hello');
    expect(t, styleAt(1, 2, hasFg(const Color.rgb(100, 100, 100))));
    expect(t, styleAt(1, 2, hasBg(removed)));
    expect(t, styleAt(6, 2, hasFg(const Color.rgb(255, 0, 0))));
    expect(t, styleAt(10, 2, hasFg(const Color.rgb(11, 11, 11))));
    expect(t, styleAt(10, 2, hasBg(removed)));
    expect(t, styleAt(16, 2, hasFg(const Color.rgb(12, 12, 12))));
    expect(t, styleAt(16, 2, hasBg(removed)));
    for (var x = 17; x < 22; x++) {
      expect(t, styleAt(x, 2, hasFg(const Color.rgb(12, 12, 12))));
      expect(t, styleAt(x, 2, hasBg(const Color.rgb(128, 0, 0))));
    }
    expect(t, styleAt(22, 2, hasBg(removed)));
    expect(t, styleAt(41, 2, hasBg(removed)));
    // the row of +  print('hi');
    expect(t, styleAt(6, 3, hasFg(const Color.rgb(0, 255, 0))));
    expect(t, styleAt(16, 3, hasBg(added)));
    expect(t, styleAt(17, 3, hasBg(const Color.rgb(0, 128, 0))));
    expect(t, styleAt(18, 3, hasBg(const Color.rgb(0, 128, 0))));
    expect(t, styleAt(19, 3, hasBg(added)));
    expect(t, styleAt(41, 3, hasBg(added)));
    // a line of context: its syntax colors alone
    expect(t, styleAt(10, 4, hasFg(const Color.rgb(10, 10, 10))));
    for (final bg in [removed, added]) {
      expect(t, styleAt(10, 4, isNot(hasBg(bg))));
    }
    // b(1) and c(2) removed, b(3) added: b(1) beside b(3)
    expect(t, styleAt(10, 8, hasBg(const Color.rgb(128, 0, 0))));
    expect(t, styleAt(10, 10, hasBg(const Color.rgb(0, 128, 0))));
    expect(t, styleAt(8, 9, hasBg(removed)));
    expect(t, styleAt(10, 9, hasBg(removed)));
    // the file and the lines left out
    expect(t, styleAt(0, 0, hasFg(const Color.rgb(3, 3, 3))));
    expect(t, styleAt(0, 0, hasAttr(Attr.bold)));
    expect(t, styleAt(6, 6, hasFg(const Color.rgb(1, 1, 1))));
    expect(t, styleAt(41, 6, hasBg(const Color.rgb(2, 2, 2))));
  });

  testTwk('side by side, colors and marks each side, the side without a '
      'line beside one left blank', (t) async {
    await t.pumpWidget(
      view(Diff.parse(source), DiffLayout.sideBySide),
      size: (49, 11),
    );
    expect(t, styleAt(10, 2, hasBg(const Color.rgb(64, 0, 0))));
    expect(t, styleAt(14, 2, hasBg(const Color.rgb(128, 0, 0))));
    expect(t, styleAt(23, 2, hasBg(const Color.rgb(64, 0, 0))));
    expect(t, styleAt(34, 2, hasBg(const Color.rgb(0, 64, 0))));
    expect(t, styleAt(39, 2, hasBg(const Color.rgb(0, 128, 0))));
    expect(t, styleAt(40, 2, hasBg(const Color.rgb(0, 128, 0))));
    expect(t, styleAt(48, 2, hasBg(const Color.rgb(0, 64, 0))));
    expect(t, styleAt(28, 2, hasFg(const Color.rgb(0, 255, 0))));
    expect(t, styleAt(3, 8, hasFg(const Color.rgb(255, 0, 0))));
    for (final bg in [const Color.rgb(0, 64, 0), const Color.rgb(64, 0, 0)]) {
      expect(t, styleAt(30, 8, isNot(hasBg(bg))));
    }
  });

  testTwk('collapses the unchanged lines before, between and after the '
      'hunks of a diff between two texts', (t) async {
    final before = [for (var i = 1; i <= 30; i++) 'line $i\n'].join();
    final after = before
        .replaceFirst('line 10\n', 'line ten\n')
        .replaceFirst('line 25\n', 'line twenty-five\n');
    await t.pumpWidget(
      view(Diff.between(before, after, context: 2)),
      size: (40, 18),
    );
    expect(t.lines, [
      '      ⋯ 7 unchanged lines',
      ' 8  8   line 8',
      ' 9  9   line 9',
      '10    - line 10',
      '   10 + line ten',
      '11 11   line 11',
      '12 12   line 12',
      '      ⋯ 10 unchanged lines',
      '23 23   line 23',
      '24 24   line 24',
      '25    - line 25',
      '   25 + line twenty-five',
      '26 26   line 26',
      '27 27   line 27',
      '      ⋯ 3 unchanged lines',
      '',
      '',
      '',
    ]);
    await t.pumpWidget(
      view(Diff.between('a\nb\n', 'a\nc\n', context: 0)),
      size: (40, 18),
    );
    expect(t.lines.take(4), [
      '    ⋯ 1 unchanged line',
      '2   - b',
      '  2 + c',
      '',
    ]);
  });

  testTwk('lexes each side as one source: the whole file where the diff '
      'was found from it, its lines in the hunks otherwise', (t) async {
    final between = Diff.between(
      '/*\na\nb\n*/\nx;\n',
      '/*\na\nc\n*/\nx;\n',
      context: 0,
      path: 'a.dart',
    );
    await t.pumpWidget(view(between), size: (30, 5));
    expect(t.lines.take(4), [
      'a.dart',
      '    ⋯ 2 unchanged lines',
      '3   - b',
      '  3 + c',
    ]);
    expect(t, styleAt(6, 2, hasFg(const Color.rgb(13, 13, 13))));
    expect(t, styleAt(6, 3, hasFg(const Color.rgb(13, 13, 13))));

    final parsed = Diff.parse('''
--- a/a.dart
+++ b/a.dart
@@ -1,2 +1,2 @@
-/*
+x;
 y
''');
    await t.pumpWidget(view(parsed), size: (30, 5));
    expect(t.lines.take(4), ['a.dart', '1   - /*', '  1 + x;', '2 2   y']);
    expect(t, styleAt(6, 3, isNot(hasFg(const Color.rgb(13, 13, 13)))));
    await t.pumpWidget(view(parsed, DiffLayout.sideBySide), size: (29, 5));
    expect(t.lines.take(4), [
      'a.dart',
      '1 - /*        │1 + x;',
      '2   y         │2   y',
      '',
    ]);
    expect(t, styleAt(4, 2, hasFg(const Color.rgb(13, 13, 13))));
    expect(t, styleAt(19, 2, isNot(hasFg(const Color.rgb(13, 13, 13)))));
  });

  testTwk('takes the language of each file from its path, or the one it '
      'is given', (t) async {
    final diff = Diff.parse('''
--- a/a.dart
+++ b/a.dart
@@ -1 +1 @@
-return 1;
+return 2;
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-return 1;
+return 2;
''');
    await t.pumpWidget(view(diff), size: (30, 6));
    expect(t, styleAt(6, 1, hasFg(const Color.rgb(10, 10, 10))));
    expect(t, styleAt(6, 4, isNot(hasFg(const Color.rgb(10, 10, 10)))));
    await t.pumpWidget(
      SyntaxThemeScope(
        theme: syntax,
        child: DiffView(diff, theme: theme, language: dartLanguage),
      ),
    );
    expect(t, styleAt(6, 4, hasFg(const Color.rgb(10, 10, 10))));
  });

  testTwk('expands tabs to the next tab stop', (t) async {
    await t.pumpWidget(
      SyntaxThemeScope(
        theme: syntax,
        child: DiffView(
          Diff.between('a\tb\n', 'ab\tc\n'),
          theme: theme,
          tabWidth: 3,
        ),
      ),
      size: (30, 3),
    );
    expect(t.lines.take(2), ['1   - a  b', '  1 + ab c']);
  });

  testTwk('takes its colors from the theme, dark or light', (t) async {
    for (final brightness in Brightness.values) {
      final data = brightness == Brightness.dark
          ? ThemeData.dark
          : ThemeData.light;
      expect(
        DiffTheme.from(data).removed,
        Style(bg: data.error.fg, bgAlpha: 0x30),
      );
      await t.pumpWidget(
        TerminalBrightness(
          brightness: brightness,
          child: Theme.adaptive(child: DiffView(Diff.parse(source))),
        ),
        size: (40, 12),
      );
      final reason = '$brightness';
      final context = t.cell(30, 1).bg;
      final removed = t.cell(30, 2).bg;
      final word = t.cell(17, 2).bg;
      expect(removed, isNot(context), reason: reason);
      expect(word, isNot(removed), reason: reason);
      expect(t.cell(30, 3).bg, isNot(anyOf(context, removed)), reason: reason);
      expect(t, styleAt(6, 2, hasFg(data.error.fg!)), reason: reason);
      expect(t, styleAt(6, 3, hasFg(data.success.fg!)), reason: reason);
      expect(t, styleAt(1, 1, hasFg(data.muted.fg!)), reason: reason);
    }
  });

  testTwk('of a diff of fifty thousand lines, builds the rows in view and '
      'lexes the lines they need', (t) async {
    final before = [for (var i = 0; i < 50000; i++) 'line $i\n'].join();
    final after = [
      for (var i = 0; i < 50000; i++)
        if (i % 5 == 2) 'new $i\n' else 'line $i\n',
    ].join();
    final lexed = [0];
    final language = Language(name: 'count', lexer: CountingLexer(lexed));
    final controller = ScrollController();
    await t.pumpWidget(
      DiffView(
        Diff.between(before, after, path: 'big.txt'),
        language: language,
        controller: controller,
      ),
      size: (40, 20),
    );
    expect(t.lines.take(5), [
      'big.txt',
      '    1     1   line 0',
      '    2     2   line 1',
      '    3       - line 2',
      '          3 + new 2',
    ]);
    // a row for the file, one for each line of the old text and each line
    // added
    expect(controller.position.maxOffset, 1 + 50000 + 10000 - 20);
    expect(find.byType(Text).evaluate(), hasLength(lessThanOrEqualTo(26)));
    expect(lexed.single, lessThan(1000));

    controller.jumpTo(controller.position.maxOffset);
    await t.pump();
    expect(t.lines.last, '50000 50000   line 49999');
    expect(find.byType(Text).evaluate(), hasLength(lessThanOrEqualTo(26)));
    expect(lexed.single, lessThan(100000 + 1000));
  });
}
