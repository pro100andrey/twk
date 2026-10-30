// A TreeTable in an app: the nodes of a tree as the rows of a table, the
// first column the tree's with its guides (ASCII where box drawing is two
// columns wide) and expanders, measured with them; expanded and collapsed
// by the keys and by a click on an expander, inside the tree's column
// however narrow; without a selection, scrolled by the keys and expanded by
// a click alone; sorted within their parents
// by a click on a title and by the keys, either way, the guides following
// the order; the selection kept on its node by key across expanding,
// collapsing and sorting, and on a node collapsed above it; children in a
// future loaded with a spinner row the keys go past; the rows' source it
// makes disposed as it leaves the tree and as it is replaced; and of a hundred
// thousand nodes, ten thousand shown, as many rows built for each key as
// a table of ten thousand rows builds.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

/// A node of the trees of the tests: its name, its size and its children.
final class N {
  const N(this.name, this.size, [this.children = const []]);

  final String name;
  final int size;
  final List<N> children;
}

const files = [
  N('src', 30, [
    N('data', 20, [N('table.dart', 12), N('tree.dart', 8)]),
    N('widgets', 10, [N('button.dart', 10)]),
  ]),
  N('test', 5, [N('tree_test.dart', 5)]),
  N('readme.md', 1),
];

TableColumn<N> nameColumn({
  TableCell Function(N node)? cell,
  GridTrack width = const GridTrack.content(),
}) => TableColumn(
  title: 'Name',
  cell: cell ?? (n) => TableCell(n.name),
  width: width,
  compare: (a, b) => a.name.compareTo(b.name),
);

final sizeColumn = TableColumn<N>(
  title: 'Size',
  cell: (n) => TableCell('${n.size}'),
  width: const GridTrack.fixed(6),
  align: TextAlign.right,
  compare: (a, b) => a.size.compareTo(b.size),
);

/// A [TreeTable] of [roots] in a name and a size column, keyed by name.
TreeTable<N> table(
  List<N> roots, {
  TreeController? controller,
  TableController? tableController,
  List<TableColumn<N>>? columns,
  FutureOr<List<N>> Function(N node)? children,
  void Function(N node)? onActivated,
  TableSelection selection = TableSelection.row,
  bool autofocus = true,
}) => TreeTable<N>(
  roots: roots,
  children: children ?? (n) => n.children,
  nodeKey: (n) => n.name,
  columns: columns ?? [nameColumn(), sizeColumn],
  controller: controller,
  tableController: tableController,
  onActivated: onActivated,
  selection: selection,
  autofocus: autofocus,
);

/// The rows of the screen, a frame of a spinner in them as `@`.
List<String> spun(TwkTester t) => [
  for (final line in t.lines)
    SpinnerFrames.dots.frames.fold(line, (l, f) => l.replaceAll(f, '@')),
];

void main() {
  group('rows', () {
    testTwk('the tree is the first column, its guides and expanders before '
        'the names and measured with them; the others show each node', (
      t,
    ) async {
      await t.pumpWidget(
        table(
          files,
          controller: TreeController(expanded: ['src', 'data', 'widgets']),
        ),
        size: (24, 10),
      );
      expect(t.lines, [
        'Name                Size',
        '▾ src                 30',
        '├─▾ data              20',
        '│ ├── table.dart      12',
        '│ └── tree.dart        8',
        '└─▾ widgets           10',
        '  └── button.dart     10',
        '▸ test                 5',
        '  readme.md            1',
        '',
      ]);
    });

    test(
      'the guides are ASCII where box drawing is two columns wide',
      () async {
        final app = await WideApp.start(
          table(files, controller: TreeController(expanded: ['src', 'data'])),
          width: 24,
          height: 4,
        );
        await app.quit();
        final vt = Vt(24, 4, segmenter: TextSegmenter(ambiguousWidth: 2));
        app.terminal.frames.forEach(vt.feed);
        expect(
          [
            for (var y = 0; y < 4; y++)
              [for (var x = 0; x < 24; x++) vt.cell(x, y).text]
                  .join()
                  .trimRight(),
          ],
          [
            'Name               Size',
            '▾ src                30',
            '+-▾ data             20',
            '| +-- table.dart     12',
          ],
        );
      },
    );
  });

  group('expanding', () {
    testTwk('Right expands the node selected, then selects its first child; '
        'Left collapses it, or selects its parent; +, - and * expand, '
        'collapse and expand all below; Enter toggles', (t) async {
      final controller = TreeController(selectedKey: 'src');
      await t.pumpWidget(table(files, controller: controller), size: (24, 6));
      await t.press('right');
      expect(controller.expanded, {'src'});
      await t.press('right');
      expect(controller.selectedKey, 'data');
      await t.press('*');
      expect(controller.expanded, {'src', 'data'});
      await t.press('left');
      expect(controller.expanded, {'src'});
      await t.press('left');
      expect(controller.selectedKey, 'src');
      await t.press('-');
      expect(controller.expanded, isEmpty);
      await t.press('+');
      expect(controller.expanded, {'src'});
      await t.press('enter');
      expect(controller.expanded, isEmpty);
      await t.press('*');
      expect(controller.expanded, {'src', 'data', 'widgets'});
      await t.pump();
      expect(t.lines.sublist(1), [
        '▾ src                 30',
        '├─▾ data              20',
        '│ ├── table.dart      12',
        '│ └── tree.dart        8',
        '└─▾ widgets           10',
      ]);
    });

    testTwk('Enter calls onActivated with the node selected', (t) async {
      final activated = <String>[];
      final controller = TreeController(selectedKey: 'test');
      await t.pumpWidget(
        table(
          files,
          controller: controller,
          onActivated: (n) => activated.add(n.name),
        ),
        size: (24, 6),
      );
      await t.press('enter');
      expect(activated, ['test']);
      expect(controller.expanded, isEmpty);
    });

    testTwk('a click on an expander expands or collapses its node and selects '
        'it; collapsing the node above the one selected selects it', (
      t,
    ) async {
      final controller = TreeController();
      await t.pumpWidget(table(files, controller: controller), size: (24, 6));
      // the expander of src
      await t.click(0, 1);
      await t.pump();
      expect(controller.expanded, {'src'});
      expect(controller.selectedKey, 'src');
      // the expander of widgets, then its child's name
      await t.click(2, 3);
      await t.pump();
      expect(controller.expanded, {'src', 'widgets'});
      await t.click(8, 4);
      await t.pump();
      expect(controller.selectedKey, 'button.dart');
      expect(controller.expanded, {'src', 'widgets'});
      await t.click(0, 1);
      await t.pump();
      expect(controller.selectedKey, 'src');
      expect(controller.expanded, {'widgets'});
      // below the rows, in the column of src's expander
      await t.click(0, 5);
      await t.pump();
      expect(controller.expanded, {'widgets'});
      expect(t.lines.sublist(1), [
        '▸ src           30',
        '▸ test           5',
        '  readme.md      1',
        '',
        '',
      ]);
    });

    testTwk('a click in a column after a tree column narrower than a '
        "node's indent, at the x of its expander, does not expand it", (
      t,
    ) async {
      final controller = TreeController(expanded: ['src']);
      await t.pumpWidget(
        table(
          files,
          controller: controller,
          columns: [
            nameColumn(width: const GridTrack.fixed(2)),
            sizeColumn,
          ],
        ),
        size: (24, 6),
      );
      // data's expander is at 2 and 3: past the tree column's 2 cells, in
      // the gap and in the size column
      await t.click(2, 2);
      await t.pump();
      expect(controller.selectedKey, 'data');
      expect(controller.expanded, {'src'});
      await t.click(3, 2);
      await t.pump();
      expect(controller.expanded, {'src'});
      // src's, inside the column, still does
      await t.click(0, 1);
      await t.pump();
      expect(controller.expanded, isEmpty);
    });
  });

  group('no selection', () {
    testTwk('the keys scroll the rows, select nothing and expand nothing; a '
        'click on an expander expands or collapses its node alone', (t) async {
      final controller = TreeController();
      await t.pumpWidget(
        table(
          [
            for (var i = 0; i < 50; i++) N('r$i', i, [N('r$i.a', 0)]),
          ],
          controller: controller,
          selection: TableSelection.none,
        ),
        size: (20, 6),
      );
      expect(t.lines[1], startsWith('▸ r0'));
      await t.press('down');
      await t.press('pagedown');
      await t.pump();
      expect(t.lines[1], startsWith('▸ r6'));
      for (final key in ['right', '+', '*', 'enter']) {
        await t.press(key);
      }
      await t.pump();
      expect(controller.expanded, isEmpty);
      expect(controller.selectedKey, isNull);
      // r7's expander, then its name
      await t.click(0, 2);
      await t.pump();
      expect(controller.expanded, {'r7'});
      expect(controller.selectedKey, isNull);
      expect(t.lines.sublist(1, 4), [
        '▸ r6          6',
        '▾ r7          7',
        '└── r7.a      0',
      ]);
      await t.click(4, 2);
      await t.pump();
      expect(controller.expanded, {'r7'});
      await t.click(0, 2);
      await t.pump();
      expect(controller.expanded, isEmpty);
      expect(controller.selectedKey, isNull);
    });
    testTwk('nor do they act on a node the controller selects', (t) async {
      final activated = <String>[];
      final controller = TreeController(selectedKey: 'src');
      await t.pumpWidget(
        table(
          files,
          controller: controller,
          selection: TableSelection.none,
          onActivated: (n) => activated.add(n.name),
        ),
        size: (24, 6),
      );
      for (final key in ['right', '+', '*', 'enter', 'down']) {
        await t.press(key);
      }
      await t.pump();
      expect(controller.expanded, isEmpty);
      expect(controller.selectedKey, 'src');
      expect(activated, isEmpty);
    });
  });

  group('sorting', () {
    testTwk('a click on a title sorts the children of each node among '
        'themselves, every node above its children, either way; the guides '
        'follow the order', (t) async {
      final tableController = TableController();
      await t.pumpWidget(
        table(
          files,
          tableController: tableController,
          controller: TreeController(expanded: ['src', 'data', 'widgets']),
        ),
        size: (24, 10),
      );
      // by size
      await t.click(18, 0);
      await t.pump();
      expect(tableController.sortColumn, 1);
      expect(t.lines, [
        'Name              Size ▴',
        '  readme.md            1',
        '▸ test                 5',
        '▾ src                 30',
        '├─▾ widgets           10',
        '│ └── button.dart     10',
        '└─▾ data              20',
        '  ├── tree.dart        8',
        '  └── table.dart      12',
        '',
      ]);
      await t.click(18, 0);
      await t.pump();
      expect(t.lines, [
        'Name              Size ▾',
        '▾ src                 30',
        '├─▾ data              20',
        '│ ├── table.dart      12',
        '│ └── tree.dart        8',
        '└─▾ widgets           10',
        '  └── button.dart     10',
        '▸ test                 5',
        '  readme.md            1',
        '',
      ]);
    });

    testTwk('s sorts by name, the selection staying on its node, which '
        'the keys move through in the order shown', (t) async {
      final controller = TreeController(
        selectedKey: 'tree.dart',
        expanded: ['src', 'data'],
      );
      final tableController = TableController();
      await t.pumpWidget(
        table(
          files,
          controller: controller,
          tableController: tableController,
        ),
        size: (24, 10),
      );
      await t.press('s');
      await t.pump();
      expect(tableController.sortColumn, 0);
      expect(t.lines.sublist(1, 8), [
        '  readme.md           1',
        '▾ src                30',
        '├─▾ data             20',
        '│ ├── table.dart     12',
        '│ └── tree.dart       8',
        '└─▸ widgets          10',
        '▸ test                5',
      ]);
      expect(controller.selectedKey, 'tree.dart');
      expect(tableController.selectedKey, 'tree.dart');
      await t.press('s');
      await t.pump();
      expect(t.lines.sublist(1, 8), [
        '▸ test                5',
        '▾ src                30',
        '├─▸ widgets          10',
        '└─▾ data             20',
        '  ├── tree.dart       8',
        '  └── table.dart     12',
        '  readme.md           1',
      ]);
      expect(controller.selectedKey, 'tree.dart');
      await t.press('down');
      expect(controller.selectedKey, 'table.dart');
      await t.press('down');
      expect(controller.selectedKey, 'readme.md');
      await t.press('up');
      await t.press('up');
      await t.press('up');
      expect(controller.selectedKey, 'data');
      // Right selects the first child shown
      await t.press('right');
      expect(controller.selectedKey, 'tree.dart');
    });

    testTwk('the selection stays on its node as nodes above it expand and '
        'collapse', (t) async {
      final controller = TreeController(selectedKey: 'readme.md');
      final tableController = TableController();
      await t.pumpWidget(
        table(
          files,
          controller: controller,
          tableController: tableController,
        ),
        size: (24, 10),
      );
      controller.expandAll(['src', 'data']);
      await t.pump();
      expect(controller.selectedKey, 'readme.md');
      await t.press('up');
      expect(controller.selectedKey, 'test');
      controller.collapse('src');
      await t.pump();
      await t.press('up');
      expect(controller.selectedKey, 'src');
      expect(tableController.selectedKey, 'src');
    });
  });

  group('selection', () {
    testTwk('a node the controller selects is the row the table selects and '
        'shows, and the keys go on from it', (t) async {
      final controller = TreeController();
      final tableController = TableController();
      await t.pumpWidget(
        table(
          [for (var i = 0; i < 50; i++) N('r$i', i)],
          controller: controller,
          tableController: tableController,
        ),
        size: (20, 6),
      );
      controller.selectedKey = 'r40';
      await t.pump();
      expect(tableController.selectedKey, 'r40');
      expect(t.lines.last, startsWith('  r40'));
      await t.press('down');
      expect(controller.selectedKey, 'r41');
    });

    testTwk("the hidden cursor rests on the selected node's row, on the "
        'cursor cell where cells are selected', (t) async {
      for (final selection in [TableSelection.row, TableSelection.cell]) {
        await t.pumpWidget(
          table(
            files,
            controller: TreeController(selectedKey: 'data', expanded: ['src']),
            selection: selection,
          ),
          size: (24, 6),
        );
        await t.pump();
        expect(t.cursorVisible, isFalse);
        // under the header, after src
        expect(t.cursor, (0, 2), reason: '$selection');
        if (selection == TableSelection.cell) {
          await t.press('right');
          await t.pump();
          // the size column
          expect(t.cursor.$1, greaterThan(4));
          expect(t.cursor.$2, 2);
        }
        await t.press('down');
        await t.pump();
        expect(t.cursor.$2, 3, reason: '$selection');
      }
    });
  });

  group('loading', () {
    testTwk('children in a future show a spinner row until they come, which '
        'the keys go past', (t) async {
      final load = Completer<List<N>>();
      final controller = TreeController(selectedKey: 'lazy');
      await t.pumpWidget(
        table(
          const [N('lazy', 2), N('next', 3)],
          controller: controller,
          children: (n) => n.name == 'lazy' ? load.future : n.children,
        ),
        size: (24, 5),
      );
      await t.press('right');
      await t.pump();
      expect(spun(t).sublist(1, 4), [
        '▾ lazy      2',
        '└─@',
        '  next      3',
      ]);
      await t.press('down');
      expect(controller.selectedKey, 'next');
      await t.press('up');
      expect(controller.selectedKey, 'lazy');
      // a click on the spinner selects its node
      await t.click(4, 2);
      await t.pump();
      expect(controller.selectedKey, 'lazy');
      expect(controller.expanded, {'lazy'});
      load.complete(const [N('b', 1), N('a', 2)]);
      await t.pump();
      await t.pump();
      expect(t.lines.sublist(1, 5), [
        '▾ lazy      2',
        '├── b       1',
        '└── a       2',
        '  next      3',
      ]);
      await t.press('down');
      expect(controller.selectedKey, 'b');
    });
  });

  group('the source', () {
    // the rows' source the TreeTable makes for its Table, disposed: adding
    // a listener to it asserts
    TableSource<int> source(TwkTester t) =>
        t.widget<Table<int>>(find.byType(Table<int>)).source!;
    final disposed = throwsA(isA<AssertionError>());

    testTwk('the source is disposed when the TreeTable leaves the tree', (
      t,
    ) async {
      await t.pumpWidget(table(files), size: (24, 6));
      final first = source(t);
      await t.pumpWidget(const Text('gone'), size: (24, 6));
      expect(() => first.addListener(() {}), disposed);
    });

    testTwk('a source replaced by one for other nodes shown is disposed', (
      t,
    ) async {
      await t.pumpWidget(table(files), size: (24, 6));
      final first = source(t);
      await t.pumpWidget(table(files.sublist(1)), size: (24, 6));
      final second = source(t);
      expect(second, isNot(same(first)));
      expect(() => first.addListener(() {}), disposed);
      expect(t.lines.sublist(1, 3), [
        '▸ test           5',
        '  readme.md      1',
      ]);
    });
  });

  group('cost', () {
    // a hundred roots of a hundred children each, every root expanded
    final roots = [
      for (var i = 0; i < 100; i++)
        N('r$i', i, [for (var j = 0; j < 999; j++) N('r$i.$j', j)]),
    ];
    final expanded = [for (var i = 0; i < 10; i++) 'r$i'];

    /// The cells built for each of [keys] pressed in turn.
    Future<List<int>> builtPerKey(
      TwkTester t,
      Widget Function(void Function() built) view,
      List<String> keys,
    ) async {
      var built = 0;
      await t.pumpWidget(view(() => built++), size: (30, 12));
      final counts = <int>[];
      for (final key in keys) {
        built = 0;
        await t.press(key);
        await t.pump();
        counts.add(built);
      }
      return counts;
    }

    const keys = ['down', 'down', 'pagedown', 'end', 'up', 'home'];

    testTwk('of a hundred thousand nodes, ten thousand shown, each key '
        'builds as many rows as in a table of ten thousand rows', (t) async {
      final tree = await builtPerKey(
        t,
        (built) => table(
          roots,
          controller: TreeController(expanded: expanded),
          columns: [
            nameColumn(
              width: const GridTrack.fixed(12),
              cell: (n) {
                built();
                return TableCell(n.name);
              },
            ),
            sizeColumn,
          ],
        ),
        keys,
      );
      expect(t.lines.first, startsWith('Name'));
      final flat = [
        for (final r in roots.take(10)) ...[r, ...r.children],
        ...roots.skip(10),
      ];
      expect(flat, hasLength(10090));
      final rows = await builtPerKey(
        t,
        (built) => Table<N>(
          rows: flat,
          autofocus: true,
          rowKey: (n) => n.name,
          columns: [
            nameColumn(
              width: const GridTrack.fixed(12),
              cell: (n) {
                built();
                return TableCell(n.name);
              },
            ),
            sizeColumn,
          ],
        ),
        keys,
      );
      expect(tree, rows);
      expect(tree.first, lessThanOrEqualTo(2));
    });
  });
}
