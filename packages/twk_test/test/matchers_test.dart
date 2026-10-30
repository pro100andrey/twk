// The matchers of the screen: what each matches, and the message each
// fails with.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// The lines of the message [matcher] fails with on [actual], without the
/// blanks that end them.
List<String> failure(Object? actual, Matcher matcher) {
  try {
    expect(actual, matcher);
  } on TestFailure catch (e) {
    return [for (final line in e.message!.split('\n')) line.trimRight()];
  }
  fail('it matched');
}

/// A bold word and plain text, then text in color on an RGB background
/// with a `[` and a wide glyph.
Widget form() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text.rich(['sent:'.bold, const Span(' привет')]),
    const Text(
      '[x] 界',
      style: Style(fg: Color.red, bg: Color.rgb(1, 2, 3)),
    ),
  ],
);

/// The screen of [form] on 20 × 4 and its widget tree, as a failure
/// message shows them; the render tree follows.
const formScreen = <String>[
  '          screen 20×4:',
  '          0│[bold]sent:[/] привет',
  '          1│[red on #010203][[x] 界[/]',
  '          (rows 2–3 blank)',
  '',
  ...formWidgets,
  '',
  '          render tree:',
];

/// The widget tree of [form] on 20 × 4, as a failure message shows it.
const formWidgets = [
  '          widget tree:',
  '          Column ‹vertical, crossAxisAlignment: start› 20×4',
  '          ├─ Text ‹"sent: привет", spans: 2›           12×1',
  '          └─ Text ‹"[x] 界", pen: red on #010203›       6×1',
];

void main() {
  testTwk('containsLine matches a screen with a row that is the line, '
      'trailing blanks aside, or one a matcher matches', (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    expect(t, containsLine('sent: привет'));
    expect(t, containsLine('sent: привет  '));
    expect(t, containsLine(startsWith('[x]')));
    expect(t, isNot(containsLine('sent')));
    expect(t, isNot(containsLine(contains('\n'))));
  });

  testTwk('a matcher that fails shows the screen, styles marked and blank '
      "rows at the end summed up, the app's widget tree and the render tree", (
    t,
  ) async {
    await t.pumpWidget(form(), size: (20, 4));
    final lines = failure(t, containsLine('sent'));
    expect(lines.take(15), [
      "Expected: a line of the screen: 'sent'",
      '  Actual: TwkTester:<fullscreen, 20×4>',
      '   Which: has none',
      '',
      ...formScreen,
    ]);
    expect(lines[15], startsWith('          _RenderView'));
    expect(lines, contains(contains('RenderParagraph')));
    expect(
      failure(t, containsLine(startsWith('sent '))).first,
      "Expected: a line of the screen: a string starting with 'sent '",
    );
  });

  testTwk('hasTextAt matches the text the cells from a column on show, a '
      'wide glyph once', (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    expect(t, hasTextAt(0, 0, 'sent'));
    expect(t, hasTextAt(6, 0, 'привет'));
    expect(t, hasTextAt(4, 1, '界'));
    expect(t, hasTextAt(16, 3, '    '));
    expect(t, isNot(hasTextAt(1, 0, 'sent')));
    expect(t, isNot(hasTextAt(18, 0, 'abc')), reason: 'past the edge');
  });

  testTwk('hasTextAt fails with what the cells show there', (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    expect(failure(t, hasTextAt(1, 0, 'sent')).take(3), [
      "Expected: 'sent' at column 1, row 0",
      '  Actual: TwkTester:<fullscreen, 20×4>',
      "   Which: has 'ent:' there",
    ]);
    expect(
      failure(t, hasTextAt(18, 1, 'abc')).elementAt(2),
      "   Which: has '  ' there, at the end of the row",
    );
    expect(
      failure(t, hasTextAt(0, 4, 'a')).elementAt(2),
      '   Which: has no row 4: the screen has 4 rows',
    );
    expect(
      failure(t, hasTextAt(0, 1, 'x')).sublist(4, 15),
      formScreen,
    );
  });

  testTwk('styleAt matches the style of a cell, by hasAttr, hasFg and '
      'hasBg', (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    expect(t, styleAt(0, 0, hasAttr(Attr.bold)));
    expect(t, styleAt(0, 0, hasFg(Color.defaultColor)));
    expect(t, styleAt(6, 0, isNot(hasAttr(Attr.bold))));
    expect(
      t,
      styleAt(0, 1, allOf(hasFg(Color.red), hasBg(const Color.rgb(1, 2, 3)))),
    );
    expect(t, styleAt(0, 1, isNot(hasBg(Color.red))));
    expect(t.cell(0, 0), hasAttr(Attr.bold));
    expect(t.cell(0, 0), isNot(hasAttr(Attr.bold | Attr.italic)));
  });

  testTwk('hasAttr tells the kinds of underline apart', (t) async {
    await t.pumpWidget(
      Text.rich(['a'.curlyUnderline, 'b'.underline.bold]),
      size: (4, 1),
    );
    expect(t.cell(0, 0), hasAttr(Attr.curlyUnderline));
    expect(t.cell(0, 0), isNot(hasAttr(Attr.underline)));
    expect(t.cell(1, 0), hasAttr(Attr.underline | Attr.bold));
    expect(t.cell(1, 0), isNot(hasAttr(Attr.doubleUnderline)));
  });

  test('hasAttr names a kind of underline by its number when it has no '
      'name', () {
    String described(Matcher m) => m.describe(StringDescription()).toString();
    expect(described(hasAttr(Attr.dashedUnderline)), 'dashedUnderline');
    expect(described(hasAttr(6 << 3 | Attr.bold)), 'bold and underline(6)');
  });

  testTwk('styleAt fails with the cell and its style, as hasAttr, hasFg '
      'and hasBg do on a cell', (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    expect(
      failure(t, styleAt(1, 1, hasAttr(Attr.bold | Attr.italic))).take(15),
      [
        'Expected: the cell at column 1, row 1: bold and italic',
        '  Actual: TwkTester:<fullscreen, 20×4>',
        "   Which: has 'x' there, which is red on #010203",
        '',
        ...formScreen,
      ],
    );
    expect(
      failure(t, styleAt(6, 0, hasFg(const Color.indexed(200)))).take(3),
      [
        'Expected: the cell at column 6, row 0: fg indexed(200)',
        '  Actual: TwkTester:<fullscreen, 20×4>',
        "   Which: has 'п' there, which is unstyled",
      ],
    );
    expect(
      failure(
        t,
        styleAt(0, 1, allOf(hasFg(Color.red), hasBg(Color.blue))),
      ).elementAt(2),
      "   Which: has '[' there, which is red on #010203",
    );
    expect(
      failure(t, styleAt(20, 0, hasAttr(Attr.bold))).elementAt(2),
      '   Which: has no column 20: the screen has 20 columns',
    );
    expect(failure(t.cell(0, 0), hasBg(const Color.indexed(9))), [
      'Expected: bg brightRed',
      '  Actual: VtCell:<[bold]s[/]>',
      '   Which: is bold',
      '',
    ]);
    expect(failure(t.cell(0, 1), hasAttr(Attr.dashedUnderline)), [
      'Expected: dashedUnderline',
      '  Actual: VtCell:<[red on #010203][[[/]>',
      '   Which: is red on #010203',
      '',
    ]);
  });

  testTwk('cursorAt matches a screen that shows the cursor there', (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    expect(t, isNot(cursorAt(0, 0)), reason: 'hidden');
    t.binding.twkApp.screen.presenter
      ..cursorVisible = true
      ..cursorX = 4
      ..cursorY = 2;
    t.binding.twkApp.requestFrame();
    await t.pump();
    expect(t, cursorAt(4, 2));
    expect(t, isNot(cursorAt(2, 4)));
    expect(failure(t, cursorAt(3, 2)).take(3), [
      'Expected: the cursor at column 3, row 2',
      '  Actual: TwkTester:<fullscreen, 20×4>',
      '   Which: has it at column 4, row 2',
    ]);
    t.binding.twkApp.screen.presenter.cursorVisible = false;
    t.binding.twkApp.requestFrame();
    await t.pump();
    // hidden, it rests where the binding puts it: with nothing focused, at
    // home
    expect(
      failure(t, cursorAt(4, 2)).elementAt(2),
      '   Which: has it hidden, at column 0, row 0',
    );
  });

  testTwk('matchesScreen matches the rows of the screen as text, blanks '
      'that end a row and rows that end the screen aside', (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    expect(
      t,
      matchesScreen('''
sent: привет
[x] 界
'''),
    );
    expect(t, matchesScreen('sent: привет   \n[x] 界\n\n\n'));
    expect(t, isNot(matchesScreen('sent: привет')));
    expect(t, isNot(matchesScreen(' sent: привет\n[x] 界')));
    expect(t, isNot(matchesScreen('sent: привет\n[x] 界\nmore')));
  });

  testTwk('matchesScreen with styles marks each run of cells of one style '
      'as [style]…[/], a [ doubled', (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    expect(
      t,
      matchesScreen(styles: true, '''
[bold]sent:[/] привет
[red on #010203][[x] 界[/]
'''),
    );
    expect(t, isNot(matchesScreen(styles: true, 'sent: привет\n[x] 界')));
  });

  testTwk('with styles a blank between cells of one style is in their run, '
      'elsewhere it shows its background alone, and the row keeps blanks '
      'that show one', (t) async {
    await t.pumpWidget(
      Text.rich([
        'a'.bold,
        const Span(' '),
        'b'.bold,
        const Span(' '),
        'c'.underline,
        ' '.underline,
        const Span('d  ', Style(bg: Color.blue)),
      ], wrap: TextWrap.none),
      size: (10, 1),
    );
    expect(
      t,
      matchesScreen(
        '[bold]a b[/] [underline]c [/][on blue]d  [/]',
        styles: true,
      ),
    );
    await t.pumpWidget(Text.rich(['a'.bold, ' '.bg(Color.red), 'b'.bold]));
    expect(t, matchesScreen('[bold]a[/][on red] [/][bold]b[/]', styles: true));
  });

  testTwk("matchesScreen fails with the rows that differ, the snapshot's "
      "and the screen's", (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    expect(failure(t, matchesScreen('sent: привет\n[y] 界\n\nmore')).take(21), [
      'Expected: the screen of the snapshot',
      '  Actual: TwkTester:<fullscreen, 20×4>',
      '   Which: differs in rows 1 and 3 (- the snapshot, + the screen):',
      '            0│sent: привет',
      '          - 1│[y] 界',
      '          + 1│[x] 界',
      '            2│',
      '          - 3│more',
      '          + 3│',
      '',
      ...formScreen,
    ]);
    final styled = failure(t, matchesScreen(styles: true, 'sent: привет'));
    expect(styled.take(7), [
      'Expected: the screen of the snapshot, styles marked',
      '  Actual: TwkTester:<fullscreen, 20×4>',
      '   Which: differs in rows 0 and 1 (- the snapshot, + the screen):',
      '          - 0│sent: привет',
      '          + 0│[bold]sent:[/] привет',
      '          - 1│',
      '          + 1│[red on #010203][[x] 界[/]',
    ]);
    expect(
      styled.sublist(7, 15),
      [
        '',
        ...formWidgets,
        '',
        '          render tree:',
        startsWith('          _RenderView'),
      ],
      reason: 'the diff shows the screen with its styles already',
    );
  });

  testTwk('in the inline mode the screen is the history the app started '
      'below and its region', (t) async {
    await t.pumpWidget(
      const Text('hi'),
      mode: ScreenMode.inline,
      size: (10, 3),
      history: [r'$ app'],
    );
    expect(t, matchesScreen('\$ app\nhi'));
    expect(t, containsLine(r'$ app'));
    expect(failure(t, containsLine('x')).take(13), [
      "Expected: a line of the screen: 'x'",
      '  Actual: TwkTester:<inline, 10×3>',
      '   Which: has none',
      '',
      '          screen 10×3:',
      r'          0│$ app',
      '          1│hi',
      '          (row 2 blank)',
      '',
      '          widget tree:',
      '          Text ‹"hi"› 10×1',
      '',
      '          render tree:',
    ]);
  });

  testTwk('once the app ended a matcher that fails shows no widget '
      'tree', (t) async {
    await t.pumpWidget(form(), size: (20, 4));
    await t.quit();
    expect(failure(t, containsLine('x')).sublist(8, 12), [
      '',
      '          widget tree:',
      '          none',
      '',
    ]);
  });

  testTwk('the tester names the mode and size of its app, and whether it '
      'ended', (t) async {
    expect('$t', 'no app');
    await t.pumpWidget(const Text('hi'), size: (10, 3));
    expect('$t', 'fullscreen, 10×3');
    await t.quit();
    expect('$t', 'fullscreen, 10×3, ended');
  });

  test('hasAttr wants an attribute', () {
    expect(() => hasAttr(0), throwsArgumentError);
  });

  test('a matcher of the screen fails on what is not a tester', () {
    expect(
      failure('text', containsLine('text')).elementAt(2),
      '   Which: is not a TwkTester',
    );
  });
}
