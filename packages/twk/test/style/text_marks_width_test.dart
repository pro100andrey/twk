// The marks a widget draws as text keep the width rule of the theme's
// Glyphs: one that is not one cell wide is Glyphs.ascii's, so the columns
// of the row it stands in do not shift: a tree table's expanders, the
// arrow of the digits typed to a Pagination, the one of a LogView's new
// lines, the arrows a KeyHintsBar names keys by, the buttons of a Window.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

/// A mark two columns wide everywhere.
const wide = '【';

Widget themed(Glyphs glyphs, Widget child) => Theme(
  data: ThemeData.dark.copyWith(glyphs: glyphs),
  child: child,
);

List<String> warnings(TwkTester t) => [
  for (final r in t.logs.records)
    if (r.level == LogLevel.warning) r.message,
];

void main() {
  group('TreeTable', () {
    const roots = [
      _N('src', [_N('a.dart', [])]),
      _N('test', [_N('b.dart', [])]),
    ];
    Widget tree() => TreeTable<_N>(
      roots: roots,
      children: (n) => n.children,
      nodeKey: (n) => n.name,
      columns: [TableColumn(title: 'Name', cell: (n) => TableCell(n.name))],
      controller: TreeController(expanded: ['src']),
    );

    testTwk('an expander two columns wide is the ASCII one, warned of', (
      t,
    ) async {
      await t.pumpWidget(
        themed(
          Glyphs.unicode.copyWith(expanded: wide, collapsed: '🙂'),
          tree(),
        ),
        size: (14, 5),
      );
      expect(t.lines.take(4), [
        'Name',
        'v src',
        '└── a.dart',
        '> test',
      ]);
      expect(warnings(t), hasLength(2));
    });

    test('on an ambiguous-wide terminal expanders that are ambiguous do '
        'not shift the columns', () async {
      final app = await WideApp.start(
        themed(Glyphs.unicode.copyWith(expanded: '●', collapsed: '○'), tree()),
        width: 14,
        height: 4,
      );
      final lines = app.lines();
      await app.quit();
      expect(lines, ['Name', 'v src', '+-- a.dart', '> test']);
    });
  });

  testTwk('the arrow before the digits typed to a Pagination is one cell', (
    t,
  ) async {
    final node = FocusNode(debugLabel: 'pages');
    addTearDown(node.dispose);
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(arrowRight: wide),
        SizedBox(
          width: 60,
          child: Pagination(
            page: 0,
            pageCount: 42,
            focusNode: node,
            onChanged: (_) {},
          ),
        ),
      ),
      size: (60, 2),
    );
    node.requestFocus();
    await t.pump();
    await t.press('1');
    await t.pump();
    expect(t.lines.first.trimRight(), endsWith('Last »  > 1'));
    expect(warnings(t), hasLength(1));
  });

  testTwk('the arrow of the new lines of a LogView is one cell', (t) async {
    final c = LogController();
    addTearDown(c.dispose);
    for (var i = 0; i < 10; i++) {
      c.add('line $i');
    }
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(arrowDown: wide),
        LogView(
          controller: c,
          showTime: false,
          showLevel: false,
          autofocus: true,
          scrollbar: ScrollbarVisibility.never,
        ),
      ),
      size: (30, 4),
    );
    await t.press('up');
    await t.pump();
    await t.pump();
    c.add('line 10');
    await t.pump();
    expect(t.lines.last.trimRight(), endsWith(' v 1 new line'));
    expect(warnings(t), hasLength(1));
  });

  testTwk('the arrows a KeyHintsBar names keys by are one cell each', (
    t,
  ) async {
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(arrowUp: wide, arrowDown: '🙂'),
        KeyBindings(
          {'up': () {}, 'down': () {}},
          hints: const {'up': 'move', 'down': 'move'},
          child: const Focus(autofocus: true, child: KeyHintsBar()),
        ),
      ),
      size: (20, 1),
    );
    expect(t.lines.single.trimRight(), '^v move');
    expect(warnings(t), hasLength(2));
  });

  test('on an ambiguous-wide terminal the bar names the arrows in ASCII, '
      'so a click lands on the key under it', () async {
    final seen = <String>[];
    final app = await WideApp.start(
      KeyBindings(
        {'up': () => seen.add('up'), 'down': () => seen.add('down')},
        hints: const {'up': 'move', 'down': 'move'},
        child: const Focus(
          autofocus: true,
          child: KeyHintsBar(pressable: true),
        ),
      ),
      width: 20,
      height: 1,
    );
    final lines = app.lines();
    await app.click(1, 0);
    await app.quit();
    expect(lines.single, '^v move');
    expect(seen, ['down']);
  });

  testTwk('the buttons of a Window are one cell each', (t) async {
    await t.pumpWidget(
      themed(
        Glyphs.unicode.copyWith(minimise: wide, maximise: wide, close: wide),
        WindowLayer(
          windows: [
            Window(
              title: 'W',
              controller: WindowController(
                width: 16,
                height: 3,
              ),
              onClose: () {},
              child: const Text('body'),
            ),
          ],
          child: const Text(''),
        ),
      ),
      size: (16, 3),
    );
    expect(t.lines.first.trimRight(), endsWith('─ + x'));
    expect(warnings(t), hasLength(2));
  });
}

final class _N {
  const _N(this.name, this.children);

  final String name;
  final List<_N> children;
}
