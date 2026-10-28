// The code view under control: a CodeViewController scrolls it to a
// line, says which lines are in view, highlights lines and finds text in
// them, its listeners told after the build as new code changes what it
// finds; it goes over to a view built in place of its own; the keys
// scroll it while it has the focus; a SelectionArea copies its code
// without the gutter.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_rich/twk_rich.dart';
import 'package:twk_test/twk_test.dart';

/// Lines `line 1` to `line n`.
String lines(int n) => [for (var i = 1; i <= n; i++) 'line $i'].join('\n');

/// The keys with hints a KeyHintsBar would show now.
List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

Future<void> drag(TwkTester t, (int, int) from, (int, int) to) async {
  await t.mouse(MouseKind.down, from.$1, from.$2);
  await t.mouse(MouseKind.drag, to.$1, to.$2);
  await t.mouse(MouseKind.up, to.$1, to.$2);
  await t.pump();
}

const red = Color.rgb(200, 0, 0);
const blue = Color.rgb(0, 0, 200);

void main() {
  group('selected in a SelectionArea', () {
    testTwk('copies the code without its line numbers, tabs kept', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: const CodeView('one\n\ttwo\nend', lineNumbers: true),
          ),
        ),
        size: (12, 4),
      );
      expect(t.lines.take(3), ['1 one', '2     two', '3 end']);
      await drag(t, (0, 0), (4, 2));
      expect(copies, ['one\n\ttwo\nend']);
      // from within the tab's blanks, which stand for the tab
      await drag(t, (3, 1), (8, 1));
      expect(copies.last, '\ttwo');
      await drag(t, (6, 1), (8, 1));
      expect(copies.last, 'two');
    });

    testTwk('paints what is selected over the code alone', (t) async {
      await t.pumpWidget(
        const Theme.terminal(
          child: SelectionArea(child: CodeView('abc\ndef', lineNumbers: true)),
        ),
        size: (8, 3),
      );
      await t.mouse(MouseKind.down, 3, 0);
      await t.mouse(MouseKind.drag, 3, 1);
      await t.pump();
      String marked(int y) => [
        for (var x = 0; x < 6; x++)
          if (t.cell(x, y).bg == const Color.indexed(237).value) 'x' else '.',
      ].join();
      expect(marked(0), '...xx.');
      expect(marked(1), '..xx..');
    });

    testTwk('scrolled, copies the lines out of view too', (t) async {
      final copies = <String>[];
      final c = CodeViewController();
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: CodeView(lines(20), lineNumbers: true, controller: c),
          ),
        ),
        size: (12, 3),
      );
      c.scrollToLine(10, alignment: 0);
      await t.pump();
      expect(t.lines, ['10 line 10', '11 line 11', '12 line 12']);
      await drag(t, (3, 0), (9, 1));
      expect(copies, ['line 10\nline 11']);
    });
  });

  group('scrolls', () {
    testTwk('to a line, the least or as aligned', (t) async {
      final c = CodeViewController();
      await t.pumpWidget(
        Theme.terminal(
          child: CodeView(lines(50), lineNumbers: true, controller: c),
        ),
        size: (12, 5),
      );
      expect(t.lines.first, ' 1 line 1');
      expect(c.linesInView, (first: 1, last: 5));
      c.scrollToLine(30);
      await t.pump();
      expect(c.linesInView, (first: 26, last: 30));
      expect(t.lines.last, '30 line 30');
      c.scrollToLine(28);
      await t.pump();
      expect(c.linesInView, (first: 26, last: 30), reason: 'in view already');
      c.scrollToLine(30, alignment: 0);
      await t.pump();
      expect(c.linesInView, (first: 30, last: 34));
      c.scrollToLine(30, alignment: 0.5);
      await t.pump();
      expect(c.linesInView, (first: 28, last: 32));
      c.scrollToLine(30, alignment: 1);
      await t.pump();
      expect(c.linesInView, (first: 26, last: 30));
      c.scrollToLine(50, alignment: 0);
      await t.pump();
      expect(c.linesInView, (first: 46, last: 50), reason: 'no further');
      c.scrollToLine(1);
      await t.pump();
      expect(c.linesInView, (first: 1, last: 5));
    });

    testTwk('by the numbers the gutter gives the lines', (t) async {
      final c = CodeViewController();
      await t.pumpWidget(
        Theme.terminal(
          child: CodeView(
            lines(50),
            lineNumbers: true,
            firstLineNumber: 101,
            controller: c,
          ),
        ),
        size: (14, 4),
      );
      expect(c.linesInView, (first: 101, last: 104));
      c.scrollToLine(120, alignment: 0);
      await t.pump();
      expect(t.lines.first, '120 line 20');
      expect(c.linesInView, (first: 120, last: 123));
    });

    testTwk('to a line asked for before it was laid out', (t) async {
      final c = CodeViewController()..scrollToLine(40, alignment: 0.5);
      await t.pumpWidget(
        Theme.terminal(child: CodeView(lines(50), controller: c)),
        size: (12, 5),
      );
      expect(c.linesInView, (first: 38, last: 42));
      expect(t.lines[2], 'line 40');
    });

    testTwk('takes the room it is given', (t) async {
      final c = CodeViewController();
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('head'),
              Expanded(child: CodeView(lines(3), controller: c)),
              const Text('foot'),
            ],
          ),
        ),
        size: (10, 6),
      );
      expect(t.lines, ['head', 'line 1', 'line 2', 'line 3', '', 'foot']);
      expect(c.linesInView, (first: 1, last: 3));
    });

    testTwk('by the keys while it has the focus, which it hints', (t) async {
      final c = CodeViewController();
      await t.pumpWidget(
        Theme.terminal(
          child: CodeView(lines(30), controller: c, autofocus: true),
        ),
        size: (12, 4),
      );
      expect(hints(t), containsAll(['down scroll', 'pagedown a window']));
      await t.press('down');
      await t.pump();
      expect(c.linesInView, (first: 2, last: 5));
      await t.press('pagedown');
      await t.pump();
      expect(c.linesInView!.first, greaterThan(2));
      await t.press('end');
      await t.pump();
      expect(c.linesInView, (first: 27, last: 30));
      await t.press('home');
      await t.pump();
      expect(c.linesInView, (first: 1, last: 4));
    });

    testTwk('with a focus node of its own and no controller', (t) async {
      final node = FocusNode(debugLabel: 'code');
      await t.pumpWidget(
        Theme.terminal(child: CodeView(lines(30), focusNode: node)),
        size: (12, 4),
      );
      node.requestFocus();
      await t.pump();
      await t.press('down');
      await t.pump();
      expect(t.lines.first, 'line 2');
      node.dispose();
    });

    testTwk('across by Left and Right, lines not wrapped', (t) async {
      await t.pumpWidget(
        const Theme.terminal(
          child: CodeView(
            'short\nabcdefghijklmnop',
            lineNumbers: true,
            autofocus: true,
          ),
        ),
        size: (10, 2),
      );
      expect(t.lines, ['1 short', '2 abcdefgh']);
      expect(hints(t), contains('right scroll'));
      expect(hints(t), isNot(contains('left scroll')));
      await t.press('right');
      await t.pump();
      expect(t.lines, ['1 t', '2 efghijkl']);
      await t.press('right');
      await t.pump();
      expect(t.lines, ['1', '2 ijklmnop'], reason: 'as far as the widest');
      expect(hints(t), isNot(contains('right scroll')));
      await t.press('left');
      await t.press('left');
      await t.press('left');
      await t.pump();
      expect(t.lines, ['1 short', '2 abcdefgh']);
    });
  });

  group('highlights lines', () {
    testTwk("across the view, in their style or the view's", (t) async {
      final c = CodeViewController()
        ..highlightLines([2], style: const Style(bg: red))
        ..highlightRange(4, 5);
      await t.pumpWidget(
        Theme.terminal(
          child: CodeView(
            lines(6),
            lineNumbers: true,
            controller: c,
            highlightStyle: const Style(bg: blue),
          ),
        ),
        size: (12, 6),
      );
      List<int> backgrounds(int x) => [
        for (var y = 0; y < 6; y++) t.cell(x, y).bg,
      ];
      expect(backgrounds(3), [0, red.value, 0, blue.value, blue.value, 0]);
      expect(backgrounds(11), backgrounds(3), reason: 'to the right edge');
      expect(backgrounds(0), backgrounds(3), reason: 'the gutter too');
      expect(c.highlights, {2: const Style(bg: red), 4: null, 5: null});
      c.unhighlightLines([4]);
      await t.pump();
      expect(backgrounds(3), [0, red.value, 0, 0, blue.value, 0]);
      c.clearHighlights();
      await t.pump();
      expect(backgrounds(3), [0, 0, 0, 0, 0, 0]);
    });

    testTwk('by default on a tint of the primary color', (t) async {
      final c = CodeViewController()..highlightLines([1]);
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(
            data: ThemeData.dark,
            child: CodeView('a\nb', controller: c),
          ),
        ),
        size: (4, 2),
      );
      expect(t.cell(0, 0).bg, isNot(t.cell(0, 1).bg));
    });

    testTwk('in a translucent style once across the line, under its text as '
        'under its blanks', (t) async {
      const half = Style(bg: red, bgAlpha: 0x30);
      final c = CodeViewController()
        ..highlightLines([1])
        ..highlightLines([2], style: half);
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(
            data: ThemeData.dark,
            child: CodeView(
              'ab\ncd',
              lineNumbers: true,
              signs: const {1: CodeSign('●'), 2: CodeSign('●')},
              controller: c,
            ),
          ),
        ),
        size: (8, 3),
      );
      // the sign, a blank, the number, a blank, the code and blanks after
      for (final y in [0, 1]) {
        final blank = t.cell(7, y).bg;
        expect(blank, isNot(t.cell(0, 2).bg), reason: 'line ${y + 1} tinted');
        expect(
          [for (var x = 0; x < 8; x++) t.cell(x, y).bg],
          List.filled(8, blank),
          reason: 'line ${y + 1}',
        );
      }
    });
  });

  testTwk('without a controller or the focus, is as tall as its lines and '
      'takes no keys', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: SingleChildScrollView(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeView(lines(3)),
              for (var i = 0; i < 5; i++) Text('after $i'),
            ],
          ),
        ),
      ),
      size: (10, 4),
    );
    expect(t.lines, ['line 1', 'line 2', 'line 3', 'after 0']);
    await t.press('down');
    await t.pump();
    expect(t.lines.first, 'line 2', reason: 'the view around it scrolls');
  });

  group('finds', () {
    const code = 'Foo bar\nfoo baz foo\nnothing\nFOO\nend foo';

    testTwk('every match, ignoring the case in lower case only', (t) async {
      final c = CodeViewController();
      await t.pumpWidget(
        Theme.terminal(child: CodeView(code, controller: c)),
        size: (12, 5),
      );
      c.query = 'foo';
      expect(c.matches, const [
        CodeMatch(1, 0, 3),
        CodeMatch(2, 0, 3),
        CodeMatch(2, 8, 11),
        CodeMatch(4, 0, 3),
        CodeMatch(5, 4, 7),
      ]);
      c.query = 'Foo';
      expect(c.matches, const [CodeMatch(1, 0, 3)]);
      c.query = '';
      expect(c.matches, isEmpty);
    });

    test('a match is equal by line and range, hashes alike and shows '
        'them', () {
      CodeMatch at(int line) => CodeMatch(line, 4, 7);
      expect(at(5), at(5));
      expect(at(5).hashCode, at(5).hashCode);
      expect(at(5), isNot(at(6)));
      expect(at(5), isNot(const CodeMatch(5, 4, 8)));
      expect(at(5), isNot(const CodeMatch(5, 3, 7)));
      expect('${at(5)}', 'CodeMatch(5, 4, 7)');
    });

    testTwk('the next and the previous match, round the ends, scrolling '
        'to show it', (t) async {
      final c = CodeViewController(query: 'foo');
      await t.pumpWidget(
        Theme.terminal(
          child: CodeView(
            '${lines(20)}\nfoo\n${lines(20)}\nfoo',
            controller: c,
          ),
        ),
        size: (12, 4),
      );
      expect(c.currentMatch, isNull);
      expect(c.nextMatch(), isTrue);
      await t.pump();
      expect(c.currentMatch, const CodeMatch(21, 0, 3));
      expect(c.currentMatchIndex, 0);
      expect(c.linesInView!.last, 21);
      expect(c.nextMatch(), isTrue);
      await t.pump();
      expect(c.currentMatch, const CodeMatch(42, 0, 3));
      expect(c.linesInView!.last, 42);
      expect(c.nextMatch(), isTrue);
      expect(c.currentMatch, const CodeMatch(21, 0, 3), reason: 'round');
      expect(c.previousMatch(), isTrue);
      expect(c.currentMatch, const CodeMatch(42, 0, 3), reason: 'round');
      c.query = 'nowhere';
      expect(c.currentMatch, isNull);
      expect(c.nextMatch(), isFalse);
    });

    testTwk('from the window when there is no current match', (t) async {
      final c = CodeViewController(query: 'x');
      await t.pumpWidget(
        Theme.terminal(
          child: CodeView('x\n${lines(10)}\nx\n${lines(10)}\nx', controller: c),
        ),
        size: (12, 4),
      );
      c.scrollToLine(10, alignment: 0);
      await t.pump();
      expect(c.nextMatch(), isTrue);
      expect(c.currentMatch!.line, 12);
      c
        ..query = ''
        ..query = 'x';
      expect(c.previousMatch(), isTrue);
      expect(c.currentMatch!.line, 12, reason: 'the last at or above the end');
    });

    testTwk('draws the matches, the current one apart', (t) async {
      final c = CodeViewController(query: 'ab');
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(
            data: ThemeData.dark,
            child: CodeView('xab ab\nab', controller: c),
          ),
        ),
        size: (8, 2),
      );
      String mark(int attrs) => attrs & Attr.reverse == 0
          ? '.'
          : (attrs & Attr.bold != 0 ? 'C' : 'x');
      String marked(int y) =>
          [for (var x = 0; x < 6; x++) mark(t.cell(x, y).attrs)].join();
      expect(marked(0), '.xx.xx');
      expect(marked(1), 'xx....');
      c.nextMatch();
      await t.pump();
      expect(marked(0), '.CC.xx');
      c.nextMatch();
      await t.pump();
      expect(marked(0), '.xx.CC');
      c.query = '';
      await t.pump();
      expect(marked(0), '......');
    });

    testTwk('n and N go to the matches while there is a query', (t) async {
      final c = CodeViewController();
      await t.pumpWidget(
        Theme.terminal(
          child: CodeView('a\nb\na', controller: c, autofocus: true),
        ),
        size: (8, 3),
      );
      expect(hints(t), isNot(contains('n next match')));
      c.query = 'a';
      await t.pump();
      expect(hints(t), containsAll(['n next match', 'N previous match']));
      await t.press('n');
      await t.pump();
      expect(c.currentMatch!.line, 1);
      await t.press('n');
      await t.pump();
      expect(c.currentMatch!.line, 3);
      await t.press('N');
      await t.pump();
      expect(c.currentMatch!.line, 1);
    });

    testTwk('scrolls across to show the match', (t) async {
      final c = CodeViewController(query: 'zz');
      await t.pumpWidget(
        Theme.terminal(child: CodeView('abcdefghijklmnopzz', controller: c)),
        size: (8, 1),
      );
      c.nextMatch();
      await t.pump();
      expect(t.lines.first, 'klmnopzz');
    });

    testTwk('again in new code, keeping the current match', (t) async {
      final c = CodeViewController(query: 'k');
      Widget view(String code) => CodeView(code, controller: c);
      await t.pumpWidget(Theme.terminal(child: view('k\na\nk')), size: (8, 3));
      c
        ..nextMatch()
        ..nextMatch();
      expect(c.currentMatch, const CodeMatch(3, 0, 1));
      await t.pumpWidget(
        Theme.terminal(child: view('k\na\nk\nk')),
        size: (8, 4),
      );
      expect(c.matches.length, 3);
      expect(c.currentMatch, const CodeMatch(3, 0, 1));
      await t.pumpWidget(Theme.terminal(child: view('a')), size: (8, 4));
      expect(c.matches, isEmpty);
      expect(c.currentMatch, isNull);
    });
  });

  testTwk('tells its listeners of each change, and of a scroll', (t) async {
    final c = CodeViewController();
    var told = 0;
    c.addListener(() => told++);
    await t.pumpWidget(
      Theme.terminal(child: CodeView(lines(30), controller: c)),
      size: (10, 4),
    );
    final before = told;
    c.query = 'line';
    expect(told, before + 1);
    c.highlightLines([1]);
    expect(told, before + 2);
    c.nextMatch();
    expect(told, greaterThan(before + 2));
    final scrolled = told;
    c.scrollToLine(20, alignment: 0);
    await t.pump();
    expect(told, greaterThan(scrolled));
    expect(c.linesInView!.first, 20);
  });

  testTwk('tells its listeners, after the build, as the matches change '
      'with the view: given to it, new code or line numbers, taken from '
      'it', (t) async {
    final c = CodeViewController(query: 'k');
    addTearDown(c.dispose);
    // a label above the view, built before it: told during the build, it
    // would be marked dirty again, which fails an assert
    Widget app(String? code, {int first = 1}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListenableBuilder(
          listenable: c,
          builder: (_, _) => Text(
            '${c.matches.length} from ${c.matches.firstOrNull?.line}',
          ),
        ),
        if (code != null)
          Expanded(
            child: CodeView(code, controller: c, firstLineNumber: first),
          ),
      ],
    );
    await t.pumpWidget(Theme.terminal(child: app('k\na\nk')), size: (12, 5));
    await t.pump();
    expect(t.lines.first, '2 from 1');
    await t.pumpWidget(Theme.terminal(child: app('a\nk\nk\nk')));
    await t.pump();
    expect(t.lines.first, '3 from 2');
    await t.pumpWidget(Theme.terminal(child: app('a\nk\nk\nk', first: 10)));
    await t.pump();
    expect(t.lines.first, '3 from 11');
    await t.pumpWidget(Theme.terminal(child: app(null)));
    await t.pump();
    expect(t.lines.first, '0 from null');
  });

  testTwk('goes over to a view built in place of its own: the matches, '
      "the window and the moves are the new one's", (t) async {
    final c = CodeViewController(query: 'line 2');
    addTearDown(c.dispose);
    var told = 0;
    c.addListener(() => told++);
    Widget view(int key) =>
        CodeView(lines(30), key: ValueKey(key), controller: c);
    await t.pumpWidget(Theme.terminal(child: view(0)), size: (10, 4));
    c.nextMatch();
    await t.pump();
    expect(c.currentMatch, const CodeMatch(2, 0, 6));
    await t.pumpWidget(Theme.terminal(child: view(1)));
    await t.pump();
    expect(c.matches.length, 11);
    expect(c.linesInView, (first: 1, last: 4));
    c.nextMatch();
    await t.pump();
    expect(c.currentMatch, const CodeMatch(20, 0, 6));
    expect(t.lines, contains('line 20'));
    expect(told, greaterThan(0));
  });

  testTwk('lets go of a controller given to it no more', (t) async {
    final a = CodeViewController();
    final b = CodeViewController();
    await t.pumpWidget(
      Theme.terminal(child: CodeView(lines(9), controller: a)),
      size: (10, 3),
    );
    expect(a.linesInView, isNotNull);
    await t.pumpWidget(
      Theme.terminal(child: CodeView(lines(9), controller: b)),
      size: (10, 3),
    );
    expect(a.linesInView, isNull);
    expect(b.linesInView, (first: 1, last: 3));
    a.query = 'line';
    expect(a.matches, isEmpty);
  });
}
