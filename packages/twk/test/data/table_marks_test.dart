// Rows marked in a Table and a TreeTable: a SelectionController given as
// marks, drawn as a checkbox column before the columns, a header blank
// above it; Space marking or unmarking the row selected, a click on its
// checkbox too, the selected row kept; the marks kept on their rows across
// sorting, and drawn again as the controller changes; the columns still
// found by a click and the keys with the checkbox column before them; no
// cascade in a tree: a node marks itself alone.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

typedef File = ({String name, int size});

const files = <File>[
  (name: 'readme.md', size: 120),
  (name: 'main.dart', size: 3400),
  (name: 'a', size: 5),
];

final columns = <TableColumn<File>>[
  TableColumn(
    title: 'Name',
    cell: (f) => TableCell(f.name),
    compare: (a, b) => a.name.compareTo(b.name),
  ),
  TableColumn(
    title: 'Size',
    cell: (f) => TableCell('${f.size}'),
    width: const GridTrack.fixed(4),
    align: TextAlign.right,
    compare: (a, b) => a.size.compareTo(b.size),
  ),
];

Table<File> marked(
  SelectionController<Object> marks, {
  TableController? controller,
  TableSelection selection = TableSelection.row,
}) => Table<File>(
  rows: files,
  rowKey: (f) => f.name,
  columns: columns,
  marks: marks,
  controller: controller,
  selection: selection,
  autofocus: true,
);

/// A node of the trees of the tests.
final class N {
  const N(this.name, [this.children = const []]);

  final String name;
  final List<N> children;
}

const tree = [
  N('src', [N('a.dart'), N('b.dart')]),
  N('test'),
];

TreeTable<N> treeTable(
  SelectionController<Object> marks, {
  TreeController? controller,
  TableController? tableController,
  FutureOr<List<N>> Function(N node)? children,
}) => TreeTable<N>(
  roots: tree,
  children: children ?? (n) => n.children,
  nodeKey: (n) => n.name,
  columns: [
    TableColumn(
      title: 'Name',
      cell: (n) => TableCell(n.name),
      compare: (a, b) => a.name.compareTo(b.name),
    ),
  ],
  marks: marks,
  controller: controller,
  tableController: tableController,
  autofocus: true,
);

Future<void> click(TwkTester t, int x, int y) async {
  await t.mouse(MouseKind.down, x, y);
  await t.mouse(MouseKind.up, x, y);
  await t.pump();
}

void main() {
  group('Table marks', () {
    testTwk('a checkbox column before the columns shows the rows marked, '
        'a blank above it', (t) async {
      final marks = SelectionController<Object>(
        multiple: true,
        selected: ['main.dart'],
      );
      await t.pumpWidget(Theme.terminal(child: marked(marks)), size: (30, 4));
      expect(t.lines, [
        '    Name      Size',
        '[ ] readme.md  120',
        '[x] main.dart 3400',
        '[ ] a            5',
      ]);
    });

    testTwk('Space marks and unmarks the row selected, which stays '
        'selected', (t) async {
      final marks = SelectionController<Object>(multiple: true);
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(child: marked(marks, controller: controller)),
        size: (30, 4),
      );
      await t.press('down');
      await t.press('space');
      await t.pump();
      expect(marks.selected, {'readme.md'});
      expect(controller.selectedKey, 'readme.md');
      expect(t.lines[1], startsWith('[x] readme.md'));
      await t.press('down');
      await t.press('space');
      await t.pump();
      expect(marks.selected, {'readme.md', 'main.dart'});
      expect(t.lines[1], startsWith('[x] readme.md'));
      expect(t.lines[2], startsWith('[x] main.dart'));
      await t.press('space');
      await t.pump();
      expect(marks.selected, {'readme.md'});
      expect(t.lines[2], startsWith('[ ] main.dart'));
    });

    testTwk('Space with no row selected marks nothing', (t) async {
      final marks = SelectionController<Object>(multiple: true);
      await t.pumpWidget(Theme.terminal(child: marked(marks)), size: (30, 4));
      await t.press('space');
      await t.pump();
      expect(marks.selected, isEmpty);
    });

    testTwk('a click on a checkbox toggles the mark and selects the row, a '
        'click on the rest of the row only selects it', (t) async {
      final marks = SelectionController<Object>(multiple: true);
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(child: marked(marks, controller: controller)),
        size: (30, 4),
      );
      await click(t, 1, 1);
      expect(marks.selected, {'readme.md'});
      expect(controller.selectedKey, 'readme.md');
      await click(t, 8, 2);
      expect(marks.selected, {'readme.md'});
      expect(controller.selectedKey, 'main.dart');
      await click(t, 1, 1);
      expect(marks.selected, isEmpty);
    });

    testTwk('the marks stay on their rows as the rows are sorted', (t) async {
      final marks = SelectionController<Object>(
        multiple: true,
        selected: ['a'],
      );
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(child: marked(marks, controller: controller)),
        size: (30, 4),
      );
      controller.sortBy(0);
      await t.pump();
      expect(t.lines.skip(1), [
        '[x] a            5',
        '[ ] main.dart 3400',
        '[ ] readme.md  120',
      ]);
    });

    testTwk('the marks are drawn again as the controller changes', (t) async {
      final marks = SelectionController<Object>(multiple: true);
      await t.pumpWidget(Theme.terminal(child: marked(marks)), size: (30, 4));
      marks.selectAll(['a', 'readme.md']);
      await t.pump();
      expect(t.lines[1], startsWith('[x] readme.md'));
      expect(t.lines[3], startsWith('[x] a'));
      marks.clear();
      await t.pump();
      expect(t.lines[1], startsWith('[ ] readme.md'));
    });

    testTwk('the columns are found by a click and the keys with the '
        'checkbox column before them', (t) async {
      final marks = SelectionController<Object>(multiple: true);
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: marked(
            marks,
            controller: controller,
            selection: TableSelection.cell,
          ),
        ),
        size: (30, 4),
      );
      // the size title
      await click(t, 16, 0);
      expect(controller.sortColumn, 1);
      // a size cell
      await click(t, 16, 2);
      expect(controller.selectedColumn, 1);
      expect(marks.selected, isEmpty);
      await t.press('left');
      expect(controller.selectedColumn, 0);
    });
  });

  group('TreeTable marks', () {
    testTwk('a node marks itself alone, as Space and a click on its '
        'checkbox say, not its children', (t) async {
      final marks = SelectionController<Object>(multiple: true);
      final expanded = TreeController(expanded: ['src']);
      await t.pumpWidget(
        Theme.terminal(child: treeTable(marks, controller: expanded)),
        size: (30, 5),
      );
      expect(t.lines.take(4), [
        '    Name',
        '[ ] ▾ src',
        '[ ] ├── a.dart',
        '[ ] └── b.dart',
      ]);
      await t.press('down');
      await t.press('space');
      await t.pump();
      expect(marks.selected, {'src'});
      expect(t.lines[1], startsWith('[x] ▾ src'));
      expect(t.lines[2], startsWith('[ ] ├── a.dart'));
      await click(t, 1, 2);
      expect(marks.selected, {'src', 'a.dart'});
      expect(expanded.selectedKey, 'a.dart');
      await t.press('space');
      await t.pump();
      expect(marks.selected, {'src'});
    });

    testTwk('the marks stay on their nodes as they are sorted and '
        'collapsed', (t) async {
      final marks = SelectionController<Object>(
        multiple: true,
        selected: ['a.dart', 'test'],
      );
      final expanded = TreeController(expanded: ['src']);
      final table = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: treeTable(marks, controller: expanded, tableController: table),
        ),
        size: (30, 5),
      );
      table.sortBy(0, ascending: false);
      await t.pump();
      expect(t.lines.skip(1).take(4), [
        '[x] ▸ test'.replaceFirst('▸ ', '  '),
        '[ ] ▾ src',
        '[ ] ├── b.dart',
        '[x] └── a.dart',
      ]);
      expanded.collapse('src');
      await t.pump();
      expect(marks.selected, {'a.dart', 'test'});
      expect(t.lines.skip(1).take(2), ['[x]   test', '[ ] ▸ src']);
    });

    testTwk('the row of a load has no checkbox and cannot be marked', (
      t,
    ) async {
      final marks = SelectionController<Object>(multiple: true);
      final load = Completer<List<N>>();
      await t.pumpWidget(
        Theme.terminal(
          child: treeTable(
            marks,
            controller: TreeController(expanded: ['test']),
            children: (n) => n.name == 'test' ? load.future : n.children,
          ),
        ),
        size: (30, 5),
      );
      final row = t.lines.indexWhere(
        (l) => l.startsWith('   ') && l.trim().isNotEmpty,
        1,
      );
      expect(row, 3);
      await click(t, 1, row);
      expect(marks.selected, isEmpty);
    });
  });
}
