// A LogView in an app: it follows the end as lines are added, stops when
// scrolled up, counting the lines that came, and goes back on End; keeps at
// most the cap of lines; filters by level and text as the filter is typed,
// lines added while filtered too; finds the query with n and N; wraps or
// scrolls across; a line added while following is a hardware scroll and a
// row, at a million lines too; shows a scrollbar of the lines shown; a drag
// past its edge scrolls on, selecting the lines it scrolls through, copied
// and highlighted when they are out of view.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// `line <from>` to `line <to - 1>`.
List<String> lines(int from, int to) => [
  for (var i = from; i < to; i++) 'line $i',
];

/// The bytes the app wrote since frame [from].
int bytesSince(TwkTester t, int from) => [
  for (final f in t.terminal.frames.skip(from)) f.length,
].fold(0, (a, b) => a + b);

/// A view of [c], its lines bare, focused, with no scrollbar unless
/// [scrollbar].
Widget plain(
  LogController c, {
  bool wrap = false,
  ScrollbarVisibility scrollbar = ScrollbarVisibility.never,
}) => LogView(
  controller: c,
  showTime: false,
  showLevel: false,
  autofocus: true,
  wrap: wrap,
  scrollbar: scrollbar,
);

/// What the app copied last since frame [from] (OSC 52); null for nothing.
String? copiedSince(TwkTester t, int from) {
  final found = RegExp(
    r'\x1b\]52;c;([A-Za-z0-9+/=]*)',
  ).allMatches(t.written(since: from));
  if (found.isEmpty) {
    return null;
  }
  return utf8.decode(base64.decode(found.last[1]!));
}

/// The rows 0 to [rows] - 1 of the view with the selection's background
/// in [theme], as `x`, and without, as `.`, as their first cell has it.
String selectedRows(TwkTester t, int rows, ThemeData theme) => [
  for (var y = 0; y < rows; y++)
    if (t.cell(0, y).bg == theme.selection.bg) 'x' else '.',
].join();

/// The cells of column [x], rows 0 to [rows] - 1: `#` where the thumb is
/// whole (reverse video), its glyph where it covers part of the cell, `.`
/// on the bare track.
String bar(TwkTester t, int x, int rows) => [
  for (var y = 0; y < rows; y++)
    switch (t.cell(x, y)) {
      final c when c.attrs & Attr.reverse != 0 => '#',
      final c when c.text.trim().isEmpty => '.',
      final c => c.text,
    },
].join();

/// Adds `line <from>` to `line <to - 1>` to [c].
void addLines(LogController c, int from, int to) => c.addAll(lines(from, to));

void main() {
  testTwk('follows the end as lines are added; scrolled up it stays, '
      'counting the lines that came; End goes back and follows', (t) async {
    final c = LogController();
    addLines(c, 0, 10);
    await t.pumpWidget(Theme.terminal(child: plain(c)), size: (30, 5));
    expect(t.lines, lines(5, 10));
    expect(c.following, isTrue);

    c.add('line 10');
    await t.pump();
    expect(t.lines, lines(6, 11));

    await t.press('up');
    await t.pump();
    await t.pump();
    expect(c.following, isFalse);
    expect(t.lines, lines(5, 10));

    addLines(c, 11, 14);
    await t.pump();
    expect(c.newLines, 3);
    expect(t.lines.take(4), lines(5, 9));
    expect(t.lines.last, startsWith('line 9'));
    expect(t.lines.last, endsWith('↓ 3 new lines'));

    await t.press('end');
    await t.pump();
    await t.pump();
    expect(c.following, isTrue);
    expect(c.newLines, 0);
    expect(t.lines, lines(9, 14));

    c.add('line 14');
    await t.pump();
    expect(t.lines, lines(10, 15));
  });

  testTwk('a click on the indicator, or follow(), goes back to the end', (
    t,
  ) async {
    final c = LogController();
    addLines(c, 0, 10);
    await t.pumpWidget(Theme.terminal(child: plain(c)), size: (30, 5));
    await t.press('pageup');
    await t.pump();
    await t.pump();
    c.add('line 10');
    await t.pump();
    expect(t.lines.last, endsWith('↓ 1 new line'));
    await t.click(29, 4);
    await t.pump();
    await t.pump();
    expect(t.lines, lines(6, 11));
    expect(c.following, isTrue);

    await t.press('home');
    await t.pump();
    await t.pump();
    expect(c.following, isFalse);
    c.follow();
    await t.pump();
    await t.pump();
    expect(t.lines, lines(6, 11));
    expect(c.following, isTrue);
  });

  testTwk('keeps at most maxLines lines, the oldest dropped; scrolled up, '
      'it stays on the lines it shows', (t) async {
    final c = LogController(maxLines: 20);
    addLines(c, 0, 25);
    expect(c.length, 20);
    expect(c[0].text, 'line 5');
    expect(c[0].number, 5);
    await t.pumpWidget(Theme.terminal(child: plain(c)), size: (30, 5));
    expect(t.lines, lines(20, 25));

    // following, the lines move up as the oldest are dropped
    c.add('line 25');
    await t.pump();
    expect(t.lines, lines(21, 26));
    expect(c.length, 20);

    await t.press('pageup');
    await t.pump();
    await t.pump();
    expect(t.lines, lines(16, 21));
    addLines(c, 26, 30);
    await t.pump();
    expect(c[0].text, 'line 10');
    expect(t.lines.take(4), lines(16, 20));

    // the lines it showed dropped: it shows the oldest kept
    addLines(c, 30, 40);
    await t.pump();
    expect(c[0].text, 'line 20');
    expect(t.lines.take(4), lines(20, 24));

    c.maxLines = 3;
    await t.press('end');
    await t.pump();
    await t.pump();
    expect([for (var i = 0; i < c.length; i++) c[i].text], lines(37, 40));
    expect(t.lines.take(3), lines(37, 40));
  });

  testTwk('filters by level and by text as it is typed, lines added while '
      'filtered too', (t) async {
    final c = LogController()
      ..add('starting', level: LogLevel.debug)
      ..add('listening on 8080')
      ..add('slow request', level: LogLevel.warning)
      ..add('request failed', level: LogLevel.error)
      ..add('request done');
    await t.pumpWidget(Theme.terminal(child: plain(c)), size: (30, 6));
    expect(t.lines.take(5), [
      'starting',
      'listening on 8080',
      'slow request',
      'request failed',
      'request done',
    ]);

    c.level = LogLevel.warning;
    await t.pump();
    expect(t.lines.take(3), ['slow request', 'request failed', '']);

    c.level = LogLevel.info;
    for (final filter in ['r', 're', 'req', 'requ']) {
      c.filter = filter;
    }
    await t.pump();
    expect(t.lines.take(4), [
      'slow request',
      'request failed',
      'request done',
      '',
    ]);
    // all in lower case, it ignores the case; else it heeds it
    c.filter = 'REQ';
    await t.pump();
    expect(t.lines.first, '');
    c
      ..filter = 'req'
      ..add('REQUEST again')
      ..add('nothing')
      ..add('debug request', level: LogLevel.debug);
    await t.pump();
    expect(c.shownLength, 4);
    expect(t.lines.take(5), [
      'slow request',
      'request failed',
      'request done',
      'REQUEST again',
      '',
    ]);

    c.filter = '';
    await t.pump();
    expect(c.shownLength, 6);
  });

  testTwk('n and N go to the next and the previous match, round past the '
      'ends, scrolling to it; what the query finds is highlighted', (
    t,
  ) async {
    final c = LogController();
    for (var i = 0; i < 30; i++) {
      c.add(i % 10 == 3 ? 'line $i hit' : 'line $i');
    }
    await t.pumpWidget(Theme.terminal(child: plain(c)), size: (30, 5));
    expect(t.lines, lines(25, 30));
    c.query = 'hit';
    await t.pump();
    await t.press('n');
    await t.pump();
    await t.pump();
    // from the top of the window: line 25 on, round to line 3
    expect(c.match?.text, 'line 3 hit');
    expect(t.lines.first, 'line 3 hit');
    final row = t.lines.indexOf('line 3 hit');
    // the current match on the accent's fill, bold
    expect(t.cell(7, row), hasBg(Color.magenta));
    expect(t.cell(7, row).attrs & Attr.bold, Attr.bold);
    expect(t.cell(2, row), isNot(hasBg(Color.magenta)));

    await t.press('n');
    await t.pump();
    expect(c.match?.text, 'line 13 hit');
    expect(t.lines, contains('line 13 hit'));
    await t.press('N');
    await t.press('N');
    await t.pump();
    expect(c.match?.text, 'line 23 hit');
    expect(t.lines, contains('line 23 hit'));
    // the other matches in view are highlighted, not bold
    await t.press('N');
    await t.pump();
    expect(c.match?.text, 'line 13 hit');
    final other = t.lines.indexOf('line 3 hit');
    if (other >= 0) {
      expect(t.cell(7, other).attrs & Attr.bold, 0);
    }

    c.query = 'nothing like it';
    expect(c.nextMatch(), isFalse);
    expect(c.match, isNull);
  });

  testTwk('wraps a long line onto the rows below, or cuts it and scrolls '
      'across with Left and Right', (t) async {
    final c = LogController()
      ..add('short')
      ..add('a long line that goes past the window');
    await t.pumpWidget(Theme.terminal(child: plain(c)), size: (20, 4));
    expect(t.lines.take(2), ['short', 'a long line that goe']);

    await t.press('right');
    await t.pump();
    expect(t.lines.take(2), ['t', 'ng line that goes pa']);
    await t.press('right right right right right right');
    await t.pump();
    // as far as the widest line
    expect(t.lines[1], 'goes past the window');
    await t.press('left');
    await t.pump();
    expect(t.lines[1], 'hat goes past the wi');

    await t.pumpWidget(Theme.terminal(child: plain(c, wrap: true)));
    expect(t.lines.take(3), [
      'short',
      'a long line that',
      'goes past the window',
    ]);
  });

  testTwk('a line shows its time, muted, and its level in its color', (
    t,
  ) async {
    final c = LogController()
      ..add('up', time: DateTime(2026, 1, 1, 9, 5, 7, 42))
      ..add('bad', level: LogLevel.error);
    const dark = ThemeData.dark;
    await t.pumpWidget(
      Theme.terminal(
        child: Theme(
          data: dark,
          child: LogView(controller: c),
        ),
      ),
      size: (40, 3),
    );
    expect(t.lines.take(2), ['09:05:07.042 INFO  up', 'ERROR bad']);
    expect(t.cell(0, 0).fg, dark.muted.fg);
    expect(t.cell(13, 0).fg, dark.info.fg);
    expect(t.cell(19, 0).fg, dark.text.fg);
    expect(t.cell(0, 1).fg, dark.error.fg);
    expect(t.cell(6, 1).fg, dark.text.fg);
  });

  testTwk('lines are selected with the mouse and copied on release; the '
      'selection stays on its line as lines are added and dropped', (
    t,
  ) async {
    final c = LogController(maxLines: 3);
    addLines(c, 0, 3);
    const dark = ThemeData.dark;
    await t.pumpWidget(
      Theme.terminal(
        child: Theme(data: dark, child: plain(c)),
      ),
      size: (20, 3),
    );
    final from = t.terminal.frames.length;
    await t.mouse(MouseKind.down, 0, 1);
    await t.mouse(MouseKind.drag, 5, 2);
    await t.mouse(MouseKind.up, 5, 2);
    await t.pump();
    expect(
      t.written(since: from),
      contains('\x1b]52;c;${base64.encode(utf8.encode('line 1\nline 2'))}'),
    );
    expect(
      [for (var y = 0; y < 3; y++) t.cell(0, y).bg],
      [
        dark.background.bg,
        dark.selection.bg,
        dark.selection.bg,
      ],
    );

    c.add('line 3');
    await t.pump();
    expect(t.lines, lines(1, 4));
    expect(
      [for (var y = 0; y < 3; y++) t.cell(0, y).bg],
      [
        dark.selection.bg,
        dark.selection.bg,
        dark.background.bg,
      ],
    );
  });

  testTwk('shows a scrollbar at its right, its thumb the window of the '
      'lines shown, filtered or not, at the end while it follows', (t) async {
    final c = LogController();
    addLines(c, 0, 20);
    await t.pumpWidget(
      Theme.terminal(child: plain(c, scrollbar: ScrollbarVisibility.always)),
      size: (20, 8),
    );
    expect(bar(t, 19, 8), '....▂###');
    expect(t.lines.first, 'line 12');
    addLines(c, 20, 40);
    await t.pump();
    expect(bar(t, 19, 8), '......▅#');

    c.filter = 'line 1';
    await t.pump();
    expect(c.shownLength, 11);
    expect(bar(t, 19, 8), '..▇#####');

    c.filter = 'line 3';
    await t.pump();
    expect(c.shownLength, 11);
    expect(bar(t, 19, 8), '..▇#####');
    expect(t.lines.first, 'line 32');
    c.filter = 'line 39';
    await t.pump();
    expect(bar(t, 19, 8), '........', reason: 'nothing to scroll');
    expect(t.lines.first, 'line 39');
  });

  testTwk('a selection copies a line as it reads, its time and level too; '
      'in a line wrapped, from the row and column pressed', (t) async {
    final c = LogController()
      ..add('up', time: DateTime(2026, 1, 1, 9, 5, 7, 42))
      ..add('a long line that goes on', level: LogLevel.warning);
    await t.pumpWidget(
      Theme.terminal(
        child: LogView(
          controller: c,
          wrap: true,
          scrollbar: ScrollbarVisibility.never,
        ),
      ),
      size: (20, 4),
    );
    expect(t.lines, [
      '09:05:07.042 INFO',
      'up',
      'WARN  a long line',
      'that goes on',
    ]);
    var from = t.terminal.frames.length;
    await t.mouse(MouseKind.down, 0, 0);
    await t.mouse(MouseKind.drag, 7, 2);
    await t.mouse(MouseKind.up, 7, 2);
    await t.pump();
    expect(copiedSince(t, from), '09:05:07.042 INFO  up\nWARN  a ');

    await t.pump(const Duration(milliseconds: 400));
    from = t.terminal.frames.length;
    await t.mouse(MouseKind.down, 2, 3);
    await t.mouse(MouseKind.drag, 19, 3);
    await t.mouse(MouseKind.up, 19, 3);
    await t.pump();
    expect(copiedSince(t, from), 'at goes on');
  });

  group('a drag past its edge', () {
    testTwk('at the bottom scrolls on, selecting the lines it scrolls '
        'through; copied all, those out of view too', (t) async {
      final c = LogController();
      addLines(c, 0, 20);
      const dark = ThemeData.dark;
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(data: dark, child: plain(c)),
        ),
        size: (20, 5),
      );
      await t.press('home');
      await t.pump();
      await t.pump();
      expect(t.lines.first, 'line 0');
      final from = t.terminal.frames.length;
      await t.mouse(MouseKind.down, 0, 1);
      // the last row of the screen: one past the view's end
      await t.mouse(MouseKind.drag, 3, 4);
      await t.pump();
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(t.lines.first, 'line 6');
      await t.mouse(MouseKind.drag, 3, 3);
      await t.mouse(MouseKind.up, 3, 3);
      await t.pump();
      expect(copiedSince(t, from), [...lines(1, 9), 'line'].join('\n'));
      expect(selectedRows(t, 5, dark), 'xxxx.');

      // scrolled back, the lines it selected are highlighted
      await t.press('home');
      await t.pump();
      await t.pump();
      expect(t.lines.first, 'line 0');
      expect(selectedRows(t, 5, dark), '.xxxx');
    });

    testTwk('at the top scrolls up, the view no longer following; lines '
        'added meanwhile leave the selection where it is', (t) async {
      final c = LogController();
      addLines(c, 0, 20);
      const dark = ThemeData.dark;
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(data: dark, child: plain(c)),
        ),
        size: (20, 5),
      );
      expect(t.lines.first, 'line 15');
      final from = t.terminal.frames.length;
      await t.mouse(MouseKind.down, 6, 3);
      await t.mouse(MouseKind.drag, 2, 0);
      await t.pump();
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(c.following, isFalse);
      expect(t.lines.first, 'line 10');
      await t.mouse(MouseKind.drag, 2, 1);
      await t.mouse(MouseKind.up, 2, 1);
      await t.pump();
      expect(
        copiedSince(t, from),
        ['ne 11', ...lines(12, 18), 'line 18'].join('\n'),
      );

      addLines(c, 20, 25);
      await t.pump();
      expect(t.lines.first, 'line 10');
      expect(selectedRows(t, 5, dark), '..xxx');
      expect(c.newLines, 5);
    });

    testTwk('while it follows: the lines added move the selection up with '
        'them, and the drag goes on from them', (t) async {
      final c = LogController();
      addLines(c, 0, 10);
      await t.pumpWidget(Theme.terminal(child: plain(c)), size: (20, 5));
      expect(t.lines.first, 'line 5');
      final from = t.terminal.frames.length;
      await t.mouse(MouseKind.down, 0, 2);
      await t.mouse(MouseKind.drag, 3, 3);
      addLines(c, 10, 12);
      await t.pump();
      expect(t.lines.first, 'line 7');
      await t.mouse(MouseKind.drag, 2, 2);
      await t.mouse(MouseKind.up, 2, 2);
      await t.pump();
      // from line 7, where it was pressed, to the end of line 9
      expect(copiedSince(t, from), 'line 7\nline 8\nlin');
    });
  });

  testTwk('of a million lines, a line added while it follows is a hardware '
      'scroll and a row; one added scrolled up writes nothing', (t) async {
    final c = LogController(maxLines: 1000000);
    addLines(c, 0, 1000000);
    await t.pumpWidget(Theme.terminal(child: plain(c)), size: (40, 10));
    expect(t.lines, lines(999990, 1000000));

    var from = t.terminal.frames.length;
    c.add('line 1000000');
    await t.pump();
    expect(t.lines, lines(999991, 1000001));
    final written = t.written(since: from);
    expect(written, contains('\x1b[S'));
    expect(written, contains('line 1000000'));
    expect(written, isNot(contains('line 999999')));
    expect(bytesSince(t, from), lessThan(80));

    await t.press('up');
    await t.pump();
    await t.pump();
    from = t.terminal.frames.length;
    c.add('line 1000001');
    await t.pump();
    // the indicator, once
    expect(t.written(since: from), isNot(contains('line 10')));
    expect(t.written(since: from), contains('1 new line'));
    from = t.terminal.frames.length;
    c.add('line 1000002');
    await t.pump();
    expect(t.written(since: from), isNot(contains('line 10')));
  });

  testTwk('costs a ListView of a million lines what it costs to add a line, '
      'a row up and a window up, at its cap too', (t) async {
    final c = LogController(maxLines: 2000000);
    addLines(c, 0, 1000000);
    await t.pumpWidget(Theme.terminal(child: plain(c)), size: (80, 24));
    final log = await costs(t, () => c.add('line 1000000'));
    // at the cap, each line added drops one
    c.maxLines = c.length;
    await t.press('end');
    await t.pump();
    await t.pump();
    final capped = await costs(t, () => c.add('line 1000001'));

    var count = 1000000;
    Widget list() => ListView.builder(
      itemCount: count,
      stickToBottom: true,
      autofocus: true,
      itemExtent: 1,
      itemBuilder: (_, i) => Text('line $i'),
    );
    await t.pumpWidget(
      Theme.terminal(
        child: SizedBox(key: UniqueKey(), child: list()),
      ),
    );
    final listed = await costs(t, () {
      count++;
      t.binding.attachRootWidget(SizedBox(child: list()));
    });
    for (var i = 0; i < 3; i++) {
      expect(log[i], lessThanOrEqualTo(listed[i] + 16));
      expect(capped[i], lessThanOrEqualTo(listed[i] + 16));
    }
  });

  testTwk('clear drops every line and the match; the view, scrolled up '
      'before, follows the lines added next', (t) async {
    final c = LogController(query: 'line 3');
    addLines(c, 0, 10);
    await t.pumpWidget(Theme.terminal(child: plain(c)), size: (30, 5));
    await t.press('pageup');
    await t.pump();
    await t.pump();
    expect(c.nextMatch(), isTrue);
    expect(c.following, isFalse);

    var told = 0;
    c
      ..addListener(() => told++)
      ..clear();
    expect(told, 1);
    expect(c.length, 0);
    expect(c.shownLength, 0);
    expect(c.match, isNull);
    expect(c.following, isTrue);
    expect(c.newLines, 0);
    await t.pump();
    expect(t.lines, ['', '', '', '', '']);

    addLines(c, 10, 17);
    await t.pump();
    expect(t.lines, lines(12, 17));
  });

  test('a controller reads back the cap, the level and the filter it was '
      'made with and given since', () {
    final c = LogController(
      maxLines: 5,
      level: LogLevel.warning,
      filter: 'disk',
    );
    expect((c.maxLines, c.level, c.filter), (5, LogLevel.warning, 'disk'));
    c
      ..maxLines = 2
      ..level = LogLevel.error
      ..filter = '';
    expect((c.maxLines, c.level, c.filter), (2, LogLevel.error, ''));
  });

  test('a line says its number, level and text in its toString', () {
    final c = LogController()
      ..add('booted')
      ..add('disk full', level: LogLevel.error);
    expect('${c[1]}', 'LogLine(1, error, disk full)');
  });
}

/// The bytes [t] writes for each of: a line added while it follows, Up,
/// PageUp; [add] adds the line.
Future<List<int>> costs(TwkTester t, void Function() add) async {
  final out = <int>[];
  var from = t.terminal.frames.length;
  add();
  await t.pump();
  out.add(bytesSince(t, from));
  for (final key in ['up', 'pageup']) {
    from = t.terminal.frames.length;
    await t.press(key);
    await t.pump();
    await t.pump();
    out.add(bytesSince(t, from));
  }
  return out;
}
