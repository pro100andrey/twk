// The code view: lines with and without numbers, an app's signs in the
// gutter, in the colors of the theme on dark and light terminals or of a
// syntax theme set above it, tabs, wrapping, and new code or a new
// language.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

import 'painted.dart';

const red = Color.rgb(255, 0, 0);

void main() {
  test('shows the lines, none after a final line break', () {
    final view = Painted(
      const CodeView('final x = 1;\n  var y;\n', language: dartLanguage),
      20,
      3,
    );
    expect(view.rows, ['final x = 1;', '  var y;', '']);
    expect(Painted(const CodeView('a\n\nb'), 5, 4).rows, ['a', '', 'b', '']);
  });

  test('numbers the lines in a gutter', () {
    expect(
      Painted(
        const CodeView('a\n\nb', lineNumbers: true, firstLineNumber: 9),
        10,
        4,
      ).rows,
      [' 9 a', '10', '11 b', ''],
    );
    expect(
      Painted(const CodeView('', lineNumbers: true), 10, 2).rows,
      ['1', ''],
    );
    expect(
      Painted(const CodeView('a\n', lineNumbers: true), 10, 2).rows,
      ['1 a', ''],
    );
  });

  group('signs', () {
    const blue = Color.rgb(0, 0, 255);
    const breakpoint = CodeSign('●', style: Style(fg: red));
    const error = CodeSign(
      'E',
      style: Style(fg: blue, attrs: Attr.bold),
    );

    test('in a column before the numbers, by line number', () {
      final view = Painted(
        const CodeView(
          'a\nb\nc',
          lineNumbers: true,
          firstLineNumber: 9,
          signs: {9: breakpoint, 11: error, 12: error, 3: breakpoint},
        ),
        12,
        4,
      );
      expect(view.rows, ['●  9 a', '  10 b', 'E 11 c', '']);
      expect(view.fg(0, 0), red);
      expect(view.fg(0, 2), blue);
      expect(view.attrs(0, 2) & Attr.bold, Attr.bold);
    });

    test('before the code without numbers', () {
      expect(
        Painted(
          const CodeView('a\nb', signs: {2: CodeSign('▎')}),
          6,
          2,
        ).rows,
        ['  a', '▎ b'],
      );
    });

    test('a column even when empty, none without signs', () {
      expect(Painted(const CodeView('a', signs: {}), 6, 1).rows, ['  a']);
      expect(
        Painted(const CodeView('a', lineNumbers: true, signs: {}), 6, 1).rows,
        ['  1 a'],
      );
      expect(Painted(const CodeView('a'), 6, 1).rows, ['a']);
    });

    test('as wide as the widest, as the canvas draws it', () {
      expect(
        Painted(
          const CodeView(
            'a\nb\nc',
            signs: {1: CodeSign('W'), 2: CodeSign('E2'), 3: CodeSign('日')},
          ),
          8,
          3,
        ).rows,
        ['W  a', 'E2 b', '日 c'],
      );
      // ● is ambiguous: two columns where the canvas draws it so
      expect(
        Painted(
          const CodeView('a\nb', signs: {1: breakpoint}),
          8,
          2,
          ambiguousWidth: 2,
        ).rows,
        ['● a', '   b'],
      );
    });

    test('on the first row of a wrapped line', () {
      expect(
        Painted(
          const CodeView(
            'abcdefgh\nij',
            lineNumbers: true,
            wrap: TextWrap.grapheme,
            signs: {1: breakpoint},
          ),
          8,
          3,
        ).rows,
        ['● 1 abcd', '    efgh', '  2 ij'],
      );
    });

    test('shows signs added, moved and taken away', () {
      Widget view(Map<int, CodeSign> signs) =>
          CodeView('a\nb\nc', lineNumbers: true, signs: signs);
      final painted = Painted(view({1: breakpoint}), 8, 3);
      expect(painted.rows, ['● 1 a', '  2 b', '  3 c']);
      painted.pump(view({2: breakpoint}));
      expect(painted.rows, ['  1 a', '● 2 b', '  3 c']);
      painted.pump(view({3: error, 2: breakpoint}));
      expect(painted.rows, ['  1 a', '● 2 b', 'E 3 c']);
      expect(painted.fg(0, 1), red);
      expect(painted.fg(0, 2), blue);
      painted.pump(view({2: const CodeSign('●', style: Style(fg: blue))}));
      expect(painted.rows, ['  1 a', '● 2 b', '  3 c']);
      expect(painted.fg(0, 1), blue);
      painted.pump(view({2: error, 3: breakpoint}));
      expect(painted.rows, ['  1 a', 'E 2 b', '● 3 c']);
      painted.pump(view({3: const CodeSign('W1')}));
      expect(painted.rows, ['   1 a', '   2 b', 'W1 3 c']);
      painted.pump(view({}));
      expect(painted.rows, ['  1 a', '  2 b', '  3 c']);
    });

    test('are equal by glyph and style, and show their glyph', () {
      expect(const CodeSign('●', style: Style(fg: red)), breakpoint);
      expect(
        const CodeSign('●', style: Style(fg: red)).hashCode,
        breakpoint.hashCode,
      );
      expect(const CodeSign('●'), isNot(breakpoint));
      expect(const CodeSign('○', style: Style(fg: red)), isNot(breakpoint));
      expect('$breakpoint', 'CodeSign(●)');
    });

    testTwk('are not selected with the code', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: const CodeView('one\ntwo', signs: {1: breakpoint, 2: error}),
          ),
        ),
        size: (10, 3),
      );
      expect(t.lines.take(2), ['● one', 'E two']);
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 5, 1);
      await t.mouse(MouseKind.up, 5, 1);
      expect(copies, ['one\ntwo']);
    });
  });

  test('takes its colors from the theme, dark or light', () {
    const code = "if (a) return 'b'; // c";
    for (final brightness in Brightness.values) {
      final theme = brightness == Brightness.dark
          ? ThemeData.dark
          : ThemeData.light;
      for (final numbers in [false, true]) {
        final reason = '$brightness, line numbers: $numbers';
        final view = Painted(
          TerminalBrightness(
            brightness: brightness,
            child: Theme.adaptive(
              child: CodeView(
                code,
                language: dartLanguage,
                lineNumbers: numbers,
              ),
            ),
          ),
          30,
          2,
        );
        final x = numbers ? 2 : 0;
        expect(view.rows.first, '${numbers ? '1 ' : ''}$code', reason: reason);
        expect(view.fg(x, 0), theme.accent.fg, reason: reason);
        expect(view.fg(x + 4, 0), Color.defaultColor, reason: reason);
        expect(view.fg(x + 7, 0), theme.accent.fg, reason: reason);
        expect(view.fg(x + 14, 0), theme.success.fg, reason: reason);
        expect(view.fg(x + 19, 0), theme.muted.fg, reason: reason);
        expect(view.attrs(x + 19, 0) & Attr.italic, Attr.italic);
        if (numbers) {
          expect(view.fg(0, 0), theme.muted.fg, reason: reason);
        }
      }
    }
  });

  test("takes the terminal's colors under Theme.terminal", () {
    final view = Painted(
      const Theme.terminal(
        child: CodeView('if x // y', language: dartLanguage),
      ),
      20,
      1,
    );
    expect(view.fg(0, 0), Color.magenta);
    expect(view.fg(5, 0), const Color.indexed(245));
    expect(view.attrs(5, 0) & Attr.italic, Attr.italic);
  });

  test("takes the app's theme's colors without a syntax theme: twk's dark "
      'one without a Theme, on a terminal that says it is dark', () {
    final view = Painted(
      const TerminalBrightness(
        brightness: Brightness.dark,
        child: CodeView('if x // y', language: dartLanguage),
      ),
      20,
      1,
    );
    expect(view.fg(0, 0), ThemeData.dark.accent.fg);
  });

  test('takes the syntax theme set above it', () {
    final view = Painted(
      const SyntaxThemeScope(
        theme: SyntaxTheme(keyword: Style(fg: red)),
        child: CodeView('if x // y', language: dartLanguage),
      ),
      20,
      1,
    );
    expect(view.fg(0, 0), red);
    expect(view.fg(5, 0), Color.defaultColor);
  });

  test('moves a tab to the next multiple of the tab width', () {
    expect(
      Painted(const CodeView('\tx\nabc\td\n\t\ty\n日\tz'), 20, 4).rows,
      ['    x', 'abc d', '        y', '日  z'],
    );
    expect(
      Painted(
        const CodeView('abc\td', tabWidth: 8, language: dartLanguage),
        20,
        1,
      ).rows,
      ['abc     d'],
    );
  });

  test('cuts long lines off, or wraps them', () {
    expect(
      Painted(const CodeView('abcdefgh\nij', lineNumbers: true), 6, 3).rows,
      ['1 abcd', '2 ij', ''],
    );
    expect(
      Painted(
        const CodeView(
          'abcdefgh\nij',
          lineNumbers: true,
          wrap: TextWrap.grapheme,
        ),
        6,
        3,
      ).rows,
      ['1 abcd', '  efgh', '2 ij'],
    );
  });

  test('shows new code and a new language', () {
    final view =
        Painted(
          const Theme.terminal(child: CodeView('a', language: dartLanguage)),
          10,
          3,
        )..pump(
          const Theme.terminal(
            child: CodeView('a\nif', language: dartLanguage),
          ),
        );
    expect(view.rows, ['a', 'if', '']);
    expect(view.fg(0, 1), Color.magenta);
    view.pump(
      const Theme.terminal(child: CodeView('if\na', language: dartLanguage)),
    );
    expect(view.rows, ['if', 'a', '']);
    expect(view.fg(0, 0), Color.magenta);
    expect(view.fg(0, 1), Color.defaultColor);
    view.pump(const CodeView('if\na'));
    expect(view.fg(0, 0), Color.defaultColor);
  });

  test('shows a new theme and new settings on the lines it keeps', () {
    const green = Color.rgb(0, 255, 0);
    Widget view(Color keyword, {int tabWidth = 4, bool numbers = false}) =>
        SyntaxThemeScope(
          theme: SyntaxTheme(keyword: Style(fg: keyword)),
          child: CodeView(
            'if\n\tx',
            language: dartLanguage,
            tabWidth: tabWidth,
            lineNumbers: numbers,
          ),
        );
    final painted = Painted(view(red), 10, 2);
    expect(painted.fg(0, 0), red);
    painted.pump(view(green));
    expect(painted.fg(0, 0), green);
    painted.pump(view(green, tabWidth: 2));
    expect(painted.rows, ['if', '  x']);
    painted.pump(view(green, tabWidth: 2, numbers: true));
    expect(painted.rows, ['1 if', '2   x']);
  });
}
