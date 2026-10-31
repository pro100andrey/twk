// A Table in an app: its columns sized as a grid sizes them at wide and
// narrow sizes, text cut off with an ellipsis, a new list of rows measured
// again and the rows laid out by the new widths in the same frame, those
// scrolled out and back too, many rows measured by those in view and a
// sample; columns resized by a drag of their edge and by keys; the header
// staying while the rows scroll, a row's scroll moved in hardware, the
// selection's too; sorting by a click on a title or by keys, rows that
// compare equal keeping their order either way; the selection kept on its
// row by key across sorting, the view following it, showing it from the
// first frame and with a new controller, of a million rows too; rows and
// cells selected by the keys, only with the focus, and the mouse, the keys
// that select nothing going on; lines between the columns; widget cells
// in the styles of their row and cell, and keeping their State across
// sorting; of a hundred thousand rows only
// those in view built; a source of a million rows read only in view and
// in a sample, scrolled as fast as one of ten thousand; a source's change
// read.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show MouseTracking;
import 'package:twk_test/twk_test.dart';

import '../gestures/shape_run.dart';

typedef File = ({String name, int size, String kind});

const files = <File>[
  (name: 'readme.md', size: 120, kind: 'text'),
  (name: 'main.dart', size: 3400, kind: 'dart'),
  (name: 'a', size: 5, kind: 'x'),
];

/// `n0` to `n<count - 1>`, of sizes [size] gives.
List<File> numbered(int count, {int Function(int i)? size}) => [
  for (var i = 0; i < count; i++)
    (name: 'n$i', size: size == null ? i : size(i), kind: 'k'),
];

TableColumn<File> nameColumn({
  GridTrack width = const GridTrack.content(),
  bool sorts = false,
}) => TableColumn(
  title: 'Name',
  cell: (f) => TableCell(f.name),
  width: width,
  compare: sorts ? (a, b) => a.name.compareTo(b.name) : null,
);

TableColumn<File> sizeColumn({
  GridTrack width = const GridTrack.fixed(4),
  bool sorts = false,
}) => TableColumn(
  title: 'Size',
  cell: (f) => TableCell('${f.size}'),
  width: width,
  align: TextAlign.right,
  compare: sorts ? (a, b) => a.size.compareTo(b.size) : null,
);

TableColumn<File> kindColumn({
  GridTrack width = const GridTrack.fr(1),
  bool sorts = false,
}) => TableColumn(
  title: 'Kind',
  cell: (f) => TableCell(f.kind),
  width: width,
  compare: sorts ? (a, b) => a.kind.compareTo(b.kind) : null,
);

/// Rows read one at a time, `n0` on, or as [name] names them where it
/// names one, of sizes [size] gives (the index by default); it counts the
/// rows read.
final class Numbered extends TableSource<File> {
  Numbered(this._count, {this.name, this.size});

  int _count;
  final String? Function(int i)? name;
  final int Function(int i)? size;

  /// The indices of the rows read, and how many times rows were read.
  final read = <int>{};
  var reads = 0;

  @override
  int get rowCount => _count;

  set rowCount(int count) {
    _count = count;
    notifyListeners();
  }

  /// Tells the table that rows changed.
  void changed() => notifyListeners();

  @override
  File rowAt(int index) {
    read.add(index);
    reads++;
    return (
      name: name?.call(index) ?? 'n$index',
      size: size?.call(index) ?? index,
      kind: 'k',
    );
  }
}

/// A column titled [title] whose cells are [title] over and over, cut off
/// at its width: what shows how wide it is.
TableColumn<int> filled(String title, GridTrack width) => TableColumn(
  title: title,
  cell: (_) => TableCell(title * 40),
  width: width,
  overflow: TextOverflow.clip,
);

const red = Color.rgb(255, 0, 0);
const green = Color.rgb(0, 255, 0);
const blue = Color.rgb(0, 0, 255);

/// The rows of the screen whose first cell is on [bg].
List<String> rowsOn(TwkTester t, Color bg) => [
  for (var y = 0; y < t.vt.height; y++)
    if (hasBg(bg).matches(t.cell(0, y), {})) t.lines[y],
];

/// Shows the label its State was made with; logs `+<label>` when its
/// State is made and `-<label>` when it is disposed.
final class Tally extends StatefulWidget {
  const Tally(this.label, this.log, {super.key});

  final String label;
  final List<String> log;

  @override
  State<Tally> createState() => _TallyState();
}

final class _TallyState extends State<Tally> {
  late final String _made = widget.label;

  @override
  void initState() {
    super.initState();
    widget.log.add('+${widget.label}');
  }

  @override
  void dispose() {
    widget.log.add('-${widget.label}');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(_made);
}

void main() {
  group('columns', () {
    testTwk('a content column is as wide as its widest text, a fixed one '
        'its cells, and a fraction one takes the rest', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: files,
            columns: [nameColumn(), sizeColumn(), kindColumn()],
          ),
        ),
        size: (30, 5),
      );
      expect(t.lines, [
        'Name      Size Kind',
        'readme.md  120 text',
        'main.dart 3400 dart',
        'a            5 x',
        '',
      ]);
    });

    testTwk('the content columns give up cells where they are too few, the '
        'widest first, then all of them alike, text cut off with an '
        'ellipsis', (t) async {
      const rows = <File>[
        (name: 'a-rather-long-name.txt', size: 1, kind: 'text'),
        (name: 'b', size: 22, kind: 'markdown'),
      ];
      final columns = [
        kindColumn(width: const GridTrack.content()),
        nameColumn(),
        sizeColumn(),
      ];
      await t.pumpWidget(
        Theme.terminal(
          child: Table(rows: rows, columns: columns),
        ),
        size: (40, 3),
      );
      expect(t.lines, [
        'Kind     Name                   Size',
        'text     a-rather-long-name.txt    1',
        'markdown b                        22',
      ]);
      // 18 cells for the two: the name gives up 12 of its 22
      await t.pumpWidget(
        Theme.terminal(
          child: Table(rows: rows, columns: columns),
        ),
        size: (24, 3),
      );
      expect(t.lines, [
        'Kind     Name       Size',
        'text     a-rather-…    1',
        'markdown b            22',
      ]);
      // 10 cells: 5 each
      await t.pumpWidget(
        Theme.terminal(
          child: Table(rows: rows, columns: columns),
        ),
        size: (16, 3),
      );
      expect(t.lines, [
        'Kind  Name  Size',
        'text  a-ra…    1',
        'mark… b       22',
      ]);
    });

    testTwk('a content column gives up cells down to its minimum; what '
        'does not fit is cut off at the right', (t) async {
      final columns = [
        kindColumn(width: const GridTrack.content(min: 6)),
        nameColumn(width: const GridTrack.content(min: 4)),
        sizeColumn(),
      ];
      await t.pumpWidget(
        Theme.terminal(
          child: Table(rows: files, columns: columns),
        ),
        size: (14, 4),
      );
      expect(t.lines, [
        'Kind   Name Si',
        'text   rea…  1',
        'dart   mai… 34',
        'x      a',
      ]);
    });

    testTwk('the fraction columns share the cells left by their fractions, '
        'within their bounds', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: const [0],
            columns: [
              filled('a', const GridTrack.fr(1)),
              filled('b', const GridTrack.fr(2)),
              filled('c', const GridTrack.fixed(3)),
            ],
          ),
        ),
        size: (30, 2),
      );
      // 25 cells: a third and two thirds, the odd one to the first
      expect(t.lines[1], '${'a' * 9} ${'b' * 16} ccc');
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: const [0],
            columns: [
              filled('a', const GridTrack.fr(1, min: 12)),
              filled('b', const GridTrack.fr(2, max: 10)),
              filled('c', const GridTrack.fixed(3)),
            ],
          ),
        ),
      );
      expect(t.lines[1], '${'a' * 15} ${'b' * 10} ccc');
    });

    testTwk('a new list of rows is measured again, the rows laid out by '
        'the new widths in the frame that shows them', (t) async {
      final columns = [nameColumn(), sizeColumn(), kindColumn()];
      await t.pumpWidget(
        Theme.terminal(
          child: Table(rows: files, columns: columns),
        ),
        size: (30, 4),
      );
      final frames = t.frames.length;
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: const [...files, (name: 'a-longer-name', size: 1, kind: 'y')],
            columns: columns,
          ),
        ),
      );
      expect(t.lines, [
        'Name          Size Kind',
        'readme.md      120 text',
        'main.dart     3400 dart',
        'a                5 x',
      ]);
      expect(t.frames.length, frames + 1);
    });

    testTwk('rows scrolled out of view and back are laid out by the widths '
        'of the columns as they are now', (t) async {
      final controller = TableController();
      Widget table(String last) => Table(
        rows: [...numbered(30), (name: last, size: 0, kind: 'k')],
        controller: controller,
        autofocus: true,
        columns: [nameColumn(), sizeColumn()],
      );
      await t.pumpWidget(Theme.terminal(child: table('n')), size: (20, 4));
      expect(t.lines.skip(1), ['n0      0', 'n1      1', 'n2      2']);
      await t.press('end');
      await t.pump();
      await t.pumpWidget(Theme.terminal(child: table('a-longer-name')));
      expect(t.lines.last, 'a-longer-name    0');
      await t.press('home');
      await t.pump();
      expect(t.lines.skip(1), [
        'n0               0',
        'n1               1',
        'n2               2',
      ]);
    });

    testTwk('a content column of more rows than the sample and those in '
        'view is as wide as the widest of those; new rows are measured in '
        'the view they show in', (t) async {
      // one in a hundred sampled: 0, 100, 200 and on
      final source = Numbered(1000, name: (i) => {150: 'x' * 12}[i]);
      final controller = TableController();
      Widget table() => Table.source(
        source: source,
        controller: controller,
        sampleRows: 10,
        columns: [nameColumn(), sizeColumn()],
      );
      await t.pumpWidget(Theme.terminal(child: table()), size: (30, 4));
      expect(t.lines, ['Name Size', 'n0      0', 'n1      1', 'n2      2']);
      controller.selectedKey = 150;
      await t.pump();
      expect(t.lines.last, 'xxx…  150');
      source.changed();
      await t.pump();
      expect(t.lines, [
        'Name         Size',
        'n148          148',
        'n149          149',
        'xxxxxxxxxxxx  150',
      ]);
      // read: the sample, and those in view and a few past them
      final sample = {for (var i = 0; i < 1000; i += 100) i};
      expect(source.read, containsAll(sample));
      expect(
        source.read.difference(sample),
        everyElement(anyOf(lessThan(10), inInclusiveRange(140, 160))),
      );
    });

    testTwk('a drag from the gap after a title makes its column as wide as '
        'the drag says, at least a cell, the rows laid out by it; a click '
        'on a title sorts', (t) async {
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: files,
            controller: controller,
            columns: [nameColumn(sorts: true), sizeColumn(), kindColumn()],
          ),
        ),
        size: (30, 4),
      );
      expect(t.lines.take(2), ['Name      Size Kind', 'readme.md  120 text']);
      // the gap after the name
      await t.mouse(MouseKind.down, 9, 0);
      await t.mouse(MouseKind.drag, 12, 0);
      await t.pump();
      expect(t.lines.take(2), [
        'Name         Size Kind',
        'readme.md     120 text',
      ]);
      // past the title, back
      await t.mouse(MouseKind.drag, 6, 3);
      await t.mouse(MouseKind.up, 6, 3);
      await t.pump();
      expect(t.lines, [
        'Name   Size Kind',
        'readm…  120 text',
        'main.… 3400 dart',
        'a         5 x',
      ]);
      expect(controller.columnWidths, {0: 6});
      expect(controller.sortColumn, isNull);
      await t.mouse(MouseKind.down, 6, 0);
      await t.mouse(MouseKind.drag, 0, 0);
      await t.mouse(MouseKind.up, 0, 0);
      await t.pump();
      expect(t.lines[1], '…  120 text');
      // the size's edge
      await t.mouse(MouseKind.down, 6, 0);
      await t.mouse(MouseKind.drag, 8, 0);
      await t.mouse(MouseKind.up, 8, 0);
      await t.pump();
      expect(t.lines[1], '…    120 text');
      expect(controller.columnWidths, {0: 1, 1: 6});
      await t.click(0, 0);
      await t.pump();
      expect(controller.sortColumn, 0);
      controller.resizeColumn(0, null);
      await t.pump();
      expect(t.lines[1], 'a              5 x');
    });

    testTwk('Shift+Left and Shift+Right narrow and widen the column of the '
        'cell selected, or the one sorted by, within its bounds; a key at a '
        'bound goes on', (t) async {
      final controller = TableController(sortColumn: 2, columnWidths: {1: 3});
      final passed = <String>[];
      Widget table(TableSelection selection) => Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          passed.add('${KeyCombo.fromEvent(event)}');
          return KeyEventResult.ignored;
        },
        child: Table(
          rows: files,
          controller: controller,
          selection: selection,
          autofocus: true,
          columns: [
            nameColumn(width: const GridTrack.content(max: 10)),
            sizeColumn(),
            kindColumn(width: const GridTrack.fr(1, min: 5), sorts: true),
          ],
        ),
      );
      await t.pumpWidget(
        Theme.terminal(child: table(TableSelection.cell)),
        size: (30, 4),
      );
      for (final key in ['shift+right', 'shift+right', 'right']) {
        await t.press(key);
      }
      for (var i = 0; i < 3; i++) {
        await t.press('shift+left');
      }
      await t.pump();
      expect(t.lines[1], 'main.dart  … dart');
      expect(controller.columnWidths, {0: 10, 1: 1});
      expect(passed, ['shift+right', 'shift+left']);
      // the column sorted by, down to its minimum
      await t.pumpWidget(Theme.terminal(child: table(TableSelection.row)));
      for (var i = 0; i < 12; i++) {
        await t.press('shift+left');
      }
      await t.pump();
      expect(controller.columnWidths, {0: 10, 1: 1, 2: 5});
      expect(t.lines.first, 'Name       … Ki… ▴');
    });

    testTwk('a column resized leaves the view where it is', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(100),
            controller: TableController(selectedKey: 0),
            autofocus: true,
            columns: [nameColumn(), sizeColumn()],
          ),
        ),
        size: (20, 4),
      );
      await t.mouse(MouseKind.wheelDown, 2, 2);
      await t.pump();
      expect(t.lines.skip(1), ['n3      3', 'n4      4', 'n5      5']);
      await t.press('shift+right');
      await t.pump();
      expect(t.lines.skip(1), ['n3       3', 'n4       4', 'n5       5']);
    });

    testTwk('the gaps between the columns are as wide as columnGap', (
      t,
    ) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: files,
            columnGap: 3,
            columns: [nameColumn(), sizeColumn(), kindColumn()],
          ),
        ),
        size: (30, 2),
      );
      expect(t.lines, ['Name        Size   Kind', 'readme.md    120   text']);
    });
  });

  group('header', () {
    testTwk('stays above the rows as they scroll', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(100),
            autofocus: true,
            columns: [nameColumn(), sizeColumn()],
          ),
        ),
        size: (20, 6),
      );
      expect(t.lines, [
        'Name Size',
        'n0      0',
        'n1      1',
        'n2      2',
        'n3      3',
        'n4      4',
      ]);
      await t.press('end');
      await t.pump();
      expect(t.lines.first, 'Name Size');
      expect(t.lines.last, 'n99    99');
      await t.mouse(MouseKind.wheelUp, 2, 3);
      await t.pump();
      expect(t.lines, [
        'Name Size',
        'n92    92',
        'n93    93',
        'n94    94',
        'n95    95',
        'n96    96',
      ]);
    });

    testTwk('is left out without showHeader', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(rows: files, showHeader: false, columns: [nameColumn()]),
        ),
        size: (20, 3),
      );
      expect(t.lines, ['readme.md', 'main.dart', 'a']);
    });

    testTwk('with a border, lines run down the gaps and under the header, '
        'joined where they cross', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: files,
            border: BorderType.single,
            columns: [nameColumn(), sizeColumn(), kindColumn()],
          ),
        ),
        size: (24, 5),
      );
      expect(t.lines, [
        'Name     │Size│Kind',
        '─────────┼────┼─────────',
        'readme.md│ 120│text',
        'main.dart│3400│dart',
        'a        │   5│x',
      ]);
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: files,
            border: BorderType.double,
            columnGap: 3,
            columns: [nameColumn(), sizeColumn()],
          ),
        ),
      );
      // the line in the middle of the gap
      expect(t.lines.take(3), [
        'Name      ║ Size',
        '══════════╬═════════════',
        'readme.md ║  120',
      ]);
    });
  });

  group('sorting', () {
    testTwk('a click on the title of a column that sorts sorts the rows by '
        'it, again the other way, marking the title', (t) async {
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: files,
            controller: controller,
            columns: [
              nameColumn(sorts: true),
              sizeColumn(width: const GridTrack.content(), sorts: true),
              kindColumn(),
            ],
          ),
        ),
        size: (30, 4),
      );
      expect(t.lines, [
        'Name        Size Kind',
        'readme.md    120 text',
        'main.dart   3400 dart',
        'a              5 x',
      ]);
      // the size's title
      await t.click(14, 0);
      await t.pump();
      expect(t.lines, [
        'Name      Size ▴ Kind',
        'a              5 x',
        'readme.md    120 text',
        'main.dart   3400 dart',
      ]);
      expect((controller.sortColumn, controller.sortAscending), (1, true));
      await t.click(14, 0);
      await t.pump();
      expect(t.lines, [
        'Name      Size ▾ Kind',
        'main.dart   3400 dart',
        'readme.md    120 text',
        'a              5 x',
      ]);
      // a column that does not sort
      await t.click(20, 0);
      await t.pump();
      expect((controller.sortColumn, controller.sortAscending), (1, false));
      await t.click(1, 0);
      await t.pump();
      expect(t.lines, [
        'Name ▴      Size Kind',
        'a              5 x',
        'main.dart   3400 dart',
        'readme.md    120 text',
      ]);
    });

    testTwk('rows that compare equal keep their order, sorted either way', (
      t,
    ) async {
      final controller = TableController(sortColumn: 1);
      Widget table() => Table(
        rows: numbered(100, size: (i) => i % 3),
        controller: controller,
        columns: [nameColumn(), sizeColumn(sorts: true)],
      );
      await t.pumpWidget(Theme.terminal(child: table()), size: (20, 6));
      expect(t.lines.skip(1), [
        'n0      0',
        'n3      0',
        'n6      0',
        'n9      0',
        'n12     0',
      ]);
      controller.sortBy(1, ascending: false);
      await t.pump();
      expect(t.lines.skip(1), [
        'n2      2',
        'n5      2',
        'n8      2',
        'n11     2',
        'n14     2',
      ]);
      await t.press('tab');
      await t.press('end');
      await t.pump();
      expect(t.lines.skip(1), [
        'n87     0',
        'n90     0',
        'n93     0',
        'n96     0',
        'n99     0',
      ]);
    });

    testTwk('s sorts by the column of the cell selected, again the other '
        'way; < and > by the column before and after the one sorted by', (
      t,
    ) async {
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: files,
            controller: controller,
            selection: TableSelection.cell,
            autofocus: true,
            columns: [
              nameColumn(sorts: true),
              sizeColumn(width: const GridTrack.content(), sorts: true),
              kindColumn(),
              kindColumn(width: const GridTrack.fixed(5), sorts: true),
            ],
          ),
        ),
        size: (40, 4),
      );
      final sorts = <(int?, bool)>[];
      Future<void> press(String key) async {
        await t.press(key);
        sorts.add((controller.sortColumn, controller.sortAscending));
      }

      await press('right');
      await press('s');
      await press('s');
      await press('>');
      await press('>');
      await press('<');
      await press('<');
      await press('<');
      await press('right');
      await press('s');
      expect(sorts, [
        (null, true),
        (1, true),
        (1, false),
        (3, true),
        (3, true),
        (1, true),
        (0, true),
        (0, true),
        (0, true),
        (0, true),
      ]);
    });

    testTwk('with sortKeys false, s, < and > go on to the bindings above '
        'it and sort nothing; a click on a title still sorts', (t) async {
      final controller = TableController();
      final heard = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: KeyBindings(
            {
              for (final k in ['s', '<', '>']) k: () => heard.add(k),
            },
            child: Table(
              rows: files,
              controller: controller,
              autofocus: true,
              sortKeys: false,
              columns: [nameColumn(sorts: true), sizeColumn(sorts: true)],
            ),
          ),
        ),
        size: (40, 4),
      );
      for (final k in ['s', '<', '>']) {
        await t.press(k);
      }
      expect(heard, ['s', '<', '>']);
      expect(controller.sortColumn, isNull);
      await t.click(1, 0);
      await t.pump();
      expect(controller.sortColumn, 0);
    });

    testTwk('s in a table that selects rows sorts the other way by the '
        'column sorted by, or by the first that sorts', (t) async {
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: files,
            controller: controller,
            autofocus: true,
            columns: [kindColumn(), nameColumn(sorts: true)],
          ),
        ),
        size: (40, 4),
      );
      await t.press('s');
      expect((controller.sortColumn, controller.sortAscending), (1, true));
      await t.press('s');
      expect((controller.sortColumn, controller.sortAscending), (1, false));
    });
  });

  group('selection', () {
    testTwk('stays on its row, by its key, as the rows are sorted, the view '
        'following it', (t) async {
      final controller = TableController(selectedKey: 'n3');
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(50, size: (i) => i * 7 % 50),
            rowKey: (f) => f.name,
            controller: controller,
            selectedStyle: const Style(bg: red),
            columns: [
              nameColumn(),
              sizeColumn(width: const GridTrack.content(), sorts: true),
            ],
          ),
        ),
        size: (20, 6),
      );
      expect(rowsOn(t, red), ['n3       21']);
      controller.sortBy(1);
      await t.pump();
      // sizes 0 to 49, each once: n3 is 22nd, scrolled the least that
      // shows it
      expect(t.lines, [
        'Name Size ▴',
        'n31      17',
        'n24      18',
        'n17      19',
        'n10      20',
        'n3       21',
      ]);
      expect(rowsOn(t, red), ['n3       21']);
      expect(controller.selectedKey, 'n3');
      // 29th the other way
      controller.sortBy(1, ascending: false);
      await t.pump();
      expect(t.lines.skip(1), [
        'n25      25',
        'n32      24',
        'n39      23',
        'n46      22',
        'n3       21',
      ]);
      expect(rowsOn(t, red), ['n3       21']);
    });

    testTwk('a row selected by its index stays on it as the rows are '
        'sorted', (t) async {
      final controller = TableController(selectedKey: 3);
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(50, size: (i) => i * 7 % 50),
            controller: controller,
            selectedStyle: const Style(bg: red),
            columns: [
              nameColumn(),
              sizeColumn(width: const GridTrack.content(), sorts: true),
            ],
          ),
        ),
        size: (20, 6),
      );
      controller.sortBy(1, ascending: false);
      await t.pump();
      expect(t.lines.last, 'n3       21');
      expect(rowsOn(t, red), ['n3       21']);
      expect(controller.selectedKey, 3);
    });

    testTwk('mounted with a row selected, the view shows it from its first '
        'frame, scrolled the least that shows it in the order sorted', (
      t,
    ) async {
      await t.pumpWidget(
        const Theme.terminal(child: Text('a tree')),
        size: (20, 6),
      );
      // put in place of another widget, as a view switched to
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(21),
            controller: TableController(selectedKey: 18),
            selectedStyle: const Style(bg: red),
            columns: [nameColumn(), sizeColumn()],
          ),
        ),
      );
      expect(t.lines, [
        'Name Size',
        'n14    14',
        'n15    15',
        'n16    16',
        'n17    17',
        'n18    18',
      ]);
      expect(rowsOn(t, red), ['n18    18']);
      // by its key, in the order the controller sorts in: 29th
      await t.pumpWidget(const Theme.terminal(child: Text('a tree')));
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(50, size: (i) => i * 7 % 50),
            rowKey: (f) => f.name,
            controller: TableController(
              selectedKey: 'n3',
              sortColumn: 1,
              sortAscending: false,
            ),
            selectedStyle: const Style(bg: red),
            columns: [
              nameColumn(),
              sizeColumn(width: const GridTrack.content(), sorts: true),
            ],
          ),
        ),
      );
      expect(t.lines.skip(1), [
        'n25      25',
        'n32      24',
        'n39      23',
        'n46      22',
        'n3       21',
      ]);
      expect(rowsOn(t, red), ['n3       21']);
    });

    testTwk('given a new controller, the view shows the row it selects', (
      t,
    ) async {
      Table<File> table(TableController controller) => Table(
        rows: numbered(21),
        controller: controller,
        selectedStyle: const Style(bg: red),
        columns: [nameColumn(), sizeColumn()],
      );
      final first = TableController(selectedKey: 2);
      await t.pumpWidget(Theme.terminal(child: table(first)), size: (20, 6));
      expect(rowsOn(t, red), ['n2      2']);
      final second = TableController(selectedKey: 18);
      await t.pumpWidget(Theme.terminal(child: table(second)));
      expect(t.lines.last, 'n18    18');
      expect(rowsOn(t, red), ['n18    18']);
      // the first again, scrolled up the least that shows its row
      await t.pumpWidget(Theme.terminal(child: table(first)));
      expect(t.lines[1], 'n2      2');
      expect(rowsOn(t, red), ['n2      2']);
      // the old controller no longer moves the view
      second.selectedKey = 20;
      await t.pump();
      expect(t.lines[1], 'n2      2');
    });

    testTwk('Up, Down, Page Up, Page Down, Home and End select rows while '
        'it has the focus, the view scrolled the least that shows them, a '
        'key that selects no other row going on; Enter activates the row '
        'selected', (t) async {
      final controller = TableController();
      final activated = <String>[];
      // the keys that go on from the table
      final passed = <KeyCode>[];
      await t.pumpWidget(
        Theme.terminal(
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: (_, event) {
              passed.add(event.code);
              return KeyEventResult.ignored;
            },
            child: Table(
              rows: numbered(20),
              controller: controller,
              selectedStyle: const Style(bg: red),
              onActivated: (f) => activated.add(f.name),
              columns: [nameColumn(), sizeColumn()],
            ),
          ),
        ),
        size: (20, 6),
      );
      await t.press('down');
      expect(controller.selectedKey, isNull);
      await t.press('tab');
      // the row selected, and the first and the last shown
      final shown = <String>[];
      for (final key in [
        'down',
        'down',
        'up',
        'pagedown',
        'pagedown',
        'pageup',
        'end',
        'down',
        'home',
        'up',
      ]) {
        await t.press(key);
        await t.pump();
        shown.add('${rowsOn(t, red).single}: ${t.lines[1]} to ${t.lines.last}');
      }
      expect(shown, [
        'n0      0: n0      0 to n4      4',
        'n1      1: n0      0 to n4      4',
        'n0      0: n0      0 to n4      4',
        'n5      5: n1      1 to n5      5',
        'n10    10: n6      6 to n10    10',
        'n5      5: n5      5 to n9      9',
        'n19    19: n15    15 to n19    19',
        'n19    19: n15    15 to n19    19',
        'n0      0: n0      0 to n4      4',
        'n0      0: n0      0 to n4      4',
      ]);
      // Down without the focus and Tab, then Down at the end and Up at the
      // start
      expect(passed, [KeyCode.down, KeyCode.tab, KeyCode.down, KeyCode.up]);
      await t.press('down');
      await t.press('enter');
      expect(activated, ['n1']);
    });

    testTwk('the keys select nothing while it does not have the focus, nor '
        'in one that takes none, where the keys start at it', (t) async {
      final controller = TableController();
      for (final focusable in [true, false]) {
        await t.pumpWidget(
          Theme.terminal(
            child: Table(
              rows: files,
              controller: controller,
              canRequestFocus: focusable,
              columns: [nameColumn()],
            ),
          ),
          size: (20, 4),
        );
        await t.press('down');
        expect(controller.selectedKey, isNull);
      }
    });

    testTwk('a click selects a row and gives the table the focus', (t) async {
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Focus(autofocus: true, child: Text('other')),
              Expanded(
                child: Table(
                  rows: files,
                  controller: controller,
                  selectedStyle: const Style(bg: red),
                  columns: [nameColumn(), sizeColumn()],
                ),
              ),
            ],
          ),
        ),
        size: (20, 5),
      );
      await t.click(12, 3);
      await t.pump();
      expect(controller.selectedKey, 1);
      expect(rowsOn(t, red), ['main.dart 3400']);
      await t.press('down');
      await t.pump();
      expect(rowsOn(t, red), ['a            5']);
      // the header selects nothing
      await t.click(1, 1);
      await t.pump();
      expect(controller.selectedKey, 2);
    });

    testTwk('a click selects a cell, Left and Right the cell before and '
        'after; the cell selected in the cursor style while the table has '
        'the focus', (t) async {
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Table(
                  rows: files,
                  controller: controller,
                  selection: TableSelection.cell,
                  selectedStyle: const Style(bg: red),
                  cursorStyle: const Style(bg: blue),
                  columns: [nameColumn(), sizeColumn(), kindColumn()],
                ),
              ),
              const Focus(child: Text('other')),
            ],
          ),
        ),
        size: (20, 5),
      );
      await t.click(11, 2);
      await t.pump();
      expect((controller.selectedKey, controller.selectedColumn), (1, 1));
      expect(
        t,
        matchesScreen(styles: true, '''
[bold]Name      Size Kind[/]
readme.md  120 text
[on #ff0000]main.dart [/][on #0000ff]3400[/][on #ff0000] dart [/]
a            5 x
other'''),
      );
      await t.press('left');
      await t.pump();
      expect(controller.selectedColumn, 0);
      await t.press('left');
      await t.press('right');
      await t.press('right');
      await t.press('right');
      await t.pump();
      expect(controller.selectedColumn, 2);
      // all of the cell, past its text
      expect(t.cell(19, 2), hasBg(blue));
      // without the focus, the row alone
      await t.press('tab');
      await t.pump();
      expect(t.cell(19, 2), hasBg(red));
    });

    testTwk('a selected style that lets the background through shows alike '
        'as the cursor moves along the row, the row painted on its own', (
      t,
    ) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: files,
            controller: TableController(selectedKey: 1),
            selection: TableSelection.cell,
            autofocus: true,
            style: const Style(bg: blue),
            selectedStyle: const Style(bg: red, bgAlpha: 128),
            columns: [nameColumn(), sizeColumn(), kindColumn()],
          ),
        ),
        size: (20, 4),
      );
      // the gap after the name
      final shown = t.cell(9, 2).bg;
      expect(shown, isNot(anyOf(red, blue)));
      for (final key in ['right', 'right', 'left', 'left']) {
        await t.press(key);
        await t.pump();
        expect(t.cell(9, 2).bg, shown, reason: key);
      }
    });

    testTwk('a widget cell is in the styles a text cell would be in: the '
        "row's, the selected style in the row selected and the cursor's in "
        'the cell selected while the table has the focus', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Table<File>(
                  rows: files,
                  controller: TableController(
                    selectedKey: 1,
                    selectedColumn: 1,
                  ),
                  selection: TableSelection.cell,
                  autofocus: true,
                  style: const Style(fg: green, attrs: Attr.italic),
                  selectedStyle: const Style(fg: red, attrs: Attr.bold),
                  cursorStyle: const Style(fg: blue, attrs: Attr.reverse),
                  columns: [
                    nameColumn(),
                    TableColumn(
                      title: 'Kind',
                      width: const GridTrack.fr(1),
                      cell: (f) => TableCell.widget(Text(f.kind)),
                    ),
                  ],
                ),
              ),
              const Focus(child: Text('other')),
            ],
          ),
        ),
        size: (20, 5),
      );
      // each over those before it
      final plain = allOf(
        hasFg(green),
        hasAttr(Attr.italic),
        isNot(hasAttr(Attr.bold)),
      );
      final selected = allOf(
        hasFg(red),
        hasAttr(Attr.italic | Attr.bold),
        isNot(hasAttr(Attr.reverse)),
      );
      final cursor = allOf(
        hasFg(blue),
        hasAttr(Attr.italic | Attr.bold | Attr.reverse),
      );
      expect(t, styleAt(0, 1, plain));
      expect(t, styleAt(10, 1, plain));
      expect(t, styleAt(0, 2, selected));
      expect(t, styleAt(10, 2, cursor));
      // the cursor on the name
      await t.press('left');
      await t.pump();
      expect(t, styleAt(0, 2, cursor));
      expect(t, styleAt(10, 2, selected));
      // without the focus, the row alone
      await t.press('right');
      await t.press('tab');
      await t.pump();
      expect(t, styleAt(0, 2, selected));
      expect(t, styleAt(10, 2, selected));
      expect(t, styleAt(10, 3, plain));
    });

    testTwk('with TableSelection.none, the keys scroll the rows and a click '
        'selects nothing', (t) async {
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(20),
            controller: controller,
            selection: TableSelection.none,
            autofocus: true,
            columns: [nameColumn(), sizeColumn()],
          ),
        ),
        size: (20, 4),
      );
      await t.press('down');
      await t.pump();
      expect(t.lines.skip(1), ['n1      1', 'n2      2', 'n3      3']);
      await t.press('pagedown');
      await t.pump();
      expect(t.lines.skip(1), ['n4      4', 'n5      5', 'n6      6']);
      await t.press('end');
      await t.pump();
      expect(t.lines.last, 'n19    19');
      await t.click(1, 2);
      await t.pump();
      expect(controller.selectedKey, isNull);
    });

    testTwk("the row selected is in the theme's selectionIdle while the "
        'table has not the focus, its selection while it has; '
        'unfocusedSelectedStyle in place of the first', (t) async {
      const theme = ThemeData.dark;
      final node = FocusNode();
      addTearDown(node.dispose);
      Widget table({Style? unfocused}) => Theme(
        data: theme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Table<File>(
                rows: files,
                controller: TableController(selectedKey: 1),
                focusNode: node,
                unfocusedSelectedStyle: unfocused,
                columns: [nameColumn(), kindColumn()],
              ),
            ),
            const Focus(autofocus: true, child: Text('other')),
          ],
        ),
      );
      await t.pumpWidget(Theme.terminal(child: table()), size: (20, 5));
      final idle = theme.selectionIdle.bg!;
      expect(idle, isNot(theme.selection.bg));
      expect(t, styleAt(0, 2, hasBg(idle)));
      expect(t, styleAt(15, 2, hasBg(idle)));
      expect(t, styleAt(0, 1, hasBg(theme.background.bg!)));
      node.requestFocus();
      await t.pump();
      expect(t, styleAt(0, 2, hasBg(theme.selection.bg!)));
      await t.pumpWidget(
        Theme.terminal(
          child: table(unfocused: const Style(bg: red)),
        ),
      );
      expect(t, styleAt(0, 2, hasBg(theme.selection.bg!)));
      node.unfocus();
      await t.pump();
      expect(t, styleAt(0, 2, hasBg(red)));
    });

    testTwk("a gauge in a widget cell takes its row's colours: the "
        "selection's, the cursor's fill", (t) async {
      const theme = ThemeData.dark;
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(
            data: theme,
            child: Table<File>(
              rows: files,
              controller: TableController(selectedKey: 1, selectedColumn: 1),
              selection: TableSelection.cell,
              columns: [
                nameColumn(),
                TableColumn(
                  title: 'Done',
                  width: const GridTrack.fr(1),
                  cell: (f) => TableCell.widget(
                    Builder(
                      builder: (context) => LineGauge(
                        ratio: 1,
                        label: '',
                        filledStyle: Theme.of(context).primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        size: (20, 4),
      );
      final primary = theme.primary.fg!;
      expect(
        t,
        styleAt(12, 1, allOf(hasFg(primary), hasBg(theme.background.bg!))),
      );
      expect(
        t,
        styleAt(12, 2, allOf(hasFg(primary), hasBg(theme.selectionIdle.bg!))),
      );
      await t.press('tab');
      await t.pump();
      // the cursor: the cell filled with primary, the gauge's own color
      // over it
      expect(t, styleAt(12, 2, hasBg(theme.primary.fg!)));
      expect(t, styleAt(0, 2, hasBg(theme.selection.bg!)));
    });

    testTwk('a new selection builds the row it left and the row it entered '
        'again, not the rows in view around them, a row scrolled in as it '
        'comes', (t) async {
      final built = <String>[];
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(20),
            controller: controller,
            autofocus: true,
            selectedStyle: const Style(bg: red),
            columns: [
              TableColumn<File>(
                title: 'Name',
                cell: (f) {
                  built.add(f.name);
                  return TableCell(f.name);
                },
                width: const GridTrack.fixed(4),
              ),
              sizeColumn(),
            ],
          ),
        ),
        size: (20, 8),
      );
      // what each key built, and the row selected then
      final steps = <String>[];
      Future<void> step(String key) async {
        built.clear();
        if (key.startsWith('=')) {
          controller.selectedKey = int.parse(key.substring(1));
        } else {
          await t.press(key);
        }
        await t.pump();
        steps.add('$key: ${(built..sort()).join(' ')} | ${rowsOn(t, red)}');
      }

      // n0 to n6 in view
      for (final key in ['down', 'down', 'up', '=5', 'end', 'home', 'down']) {
        await step(key);
      }
      expect(steps, [
        'down: n0 | [n0      0]',
        'down: n0 n1 | [n1      1]',
        'up: n0 n1 | [n0      0]',
        '=5: n0 n5 | [n5      5]',
        // n13 to n19 scrolled in, and the three rows the list builds
        // beyond the view
        'end: n10 n11 n12 n13 n14 n15 n16 n17 n18 n19 n5 | [n19    19]',
        'home: n0 n1 n19 n2 n3 n4 n5 n6 n7 n8 n9 | [n0      0]',
        'down: n0 n1 | [n1      1]',
      ]);
    });

    testTwk('the cursor moved along the row selected builds that row again '
        'only; the focus leaving, all of them', (t) async {
      final built = <String>[];
      final controller = TableController(selectedKey: 1);
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Table(
                  rows: numbered(5),
                  controller: controller,
                  autofocus: true,
                  selection: TableSelection.cell,
                  selectedStyle: const Style(bg: red),
                  cursorStyle: const Style(bg: blue),
                  columns: [
                    TableColumn<File>(
                      title: 'Name',
                      cell: (f) {
                        built.add(f.name);
                        return TableCell(f.name);
                      },
                      width: const GridTrack.fixed(4),
                    ),
                    sizeColumn(),
                  ],
                ),
              ),
              const Focus(child: Text('other')),
            ],
          ),
        ),
        size: (20, 7),
      );
      expect(t, styleAt(0, 2, hasBg(blue)));
      built.clear();
      await t.press('right');
      await t.pump();
      expect(built, ['n1']);
      expect(t, styleAt(0, 2, hasBg(red)));
      expect(t, styleAt(5, 2, hasBg(blue)));
      built.clear();
      await t.press('tab');
      await t.pump();
      expect(built, ['n0', 'n1', 'n2', 'n3', 'n4']);
      expect(t, styleAt(5, 2, hasBg(red)));
    });
  });

  group('the pointer over the edge of a column', () {
    Widget table({bool pointerShapes = true}) => Table<File>(
      rows: files,
      pointerShapes: pointerShapes,
      columns: [nameColumn(), sizeColumn(), kindColumn()],
    );

    test('is a resize across in the header, as the mouse comes over it and '
        'while it drags it', () async {
      final run = ShapeRun(table());
      await run.start();
      expect(run.term.mouseTracking, MouseTracking.motion);
      // the name column's edge: the gap after main.dart
      await run.move(9, 0);
      expect(run.shapes(), ['ew-resize']);
      await run.move(3, 0);
      expect(run.shapes(), ['default']);
      await run.move(9, 0);
      await run.press(9, 0);
      await run.drag(11, 0);
      expect(run.shapes(), ['ew-resize']);
      await run.release(11, 0);
      // a row's cell under an edge is no edge
      await run.move(11, 2);
      expect(run.shapes(), ['default']);
      await run.quit();
    });

    test('is left alone with pointerShapes false, and the motion of the '
        'mouse is not asked for', () async {
      final run = ShapeRun(table(pointerShapes: false));
      await run.start();
      expect(run.term.mouseTracking, isNot(MouseTracking.motion));
      await run.move(9, 0);
      await run.move(3, 0);
      await run.quit();
      // only the terminal's own given back as the app ends
      expect(run.shapes(), ['']);
    });

    test('nor where the terminal does not show it', () async {
      final run = ShapeRun(table(), shows: false);
      await run.start();
      expect(run.term.mouseTracking, isNot(MouseTracking.motion));
      await run.quit();
    });
  });

  group('rows', () {
    testTwk('of a hundred thousand rows, builds those in view and a few '
        'past them', (t) async {
      final built = <int>{};
      await t.pumpWidget(
        Theme.terminal(
          child: Table<int>(
            rows: [for (var i = 0; i < 100000; i++) i],
            autofocus: true,
            columns: [
              TableColumn(
                title: 'n',
                width: const GridTrack.fixed(6),
                cell: (i) {
                  built.add(i);
                  return TableCell('$i');
                },
              ),
            ],
          ),
        ),
        size: (20, 6),
      );
      expect(t.lines.last, '4');
      expect(built, {for (var i = 0; i < 8; i++) i});
      built.clear();
      await t.press('end');
      await t.pump();
      expect(t.lines.last, '99999');
      // the rows in view built again as the selection moved, then those
      // at the end
      expect(built.difference({for (var i = 0; i < 8; i++) i}), {
        for (var i = 99992; i < 100000; i++) i,
      });
    });

    testTwk('of a million rows from a source, builds those in view and a '
        'few past them, and reads those and a sample of the others', (
      t,
    ) async {
      final source = Numbered(1000000);
      final built = <int>{};
      await t.pumpWidget(
        Theme.terminal(
          child: Table<File>.source(
            source: source,
            autofocus: true,
            columns: [
              nameColumn(),
              TableColumn(
                title: 'Size',
                width: const GridTrack.fixed(6),
                align: TextAlign.right,
                cell: (f) {
                  built.add(f.size);
                  return TableCell('${f.size}');
                },
              ),
            ],
          ),
        ),
        size: (20, 6),
      );
      // as wide as the widest of the sample, 10000 apart
      expect(t.lines, [
        'Name      Size',
        'n0           0',
        'n1           1',
        'n2           2',
        'n3           3',
        'n4           4',
      ]);
      final window = {for (var i = 0; i < 8; i++) i};
      expect(built, window);
      expect(source.read, {...window, for (var i = 0; i < 100; i++) i * 10000});
      built.clear();
      source.read.clear();
      await t.press('end');
      await t.pump();
      expect(t.lines.last, 'n999999 999999');
      final end = {for (var i = 999992; i < 1000000; i++) i};
      expect(built.difference(window), end);
      expect(source.read.difference(window), end);
    });

    testTwk('a key is looked for out from where the selection was, few of '
        'a million rows read', (t) async {
      final source = Numbered(1000000);
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Table.source(
            source: source,
            rowKey: (f) => f.name,
            controller: controller,
            selectedStyle: const Style(bg: red),
            autofocus: true,
            columns: [
              nameColumn(width: const GridTrack.fixed(7)),
              sizeColumn(width: const GridTrack.fixed(6)),
            ],
          ),
        ),
        size: (20, 6),
      );
      await t.press('end');
      await t.pump();
      expect(controller.selectedKey, 'n999999');
      // a row added, and a key a few rows up
      source
        ..reads = 0
        ..rowCount = 1000001;
      await t.pump();
      expect(rowsOn(t, red), ['n999999 999999']);
      controller.selectedKey = 'n999990';
      await t.pump();
      expect(rowsOn(t, red), ['n999990 999990']);
      expect(source.reads, lessThan(50));
    });

    testTwk('of a million rows from a source, mounted with a row selected '
        'far down, shows it from the first frame, reading few rows', (
      t,
    ) async {
      final source = Numbered(1000000);
      await t.pumpWidget(
        Theme.terminal(
          child: Table.source(
            source: source,
            controller: TableController(selectedKey: 500000),
            selectedStyle: const Style(bg: red),
            columns: [
              nameColumn(width: const GridTrack.fixed(7)),
              sizeColumn(width: const GridTrack.fixed(6)),
            ],
          ),
        ),
        size: (20, 6),
      );
      expect(t.lines.skip(1), [
        'n499996 499996',
        'n499997 499997',
        'n499998 499998',
        'n499999 499999',
        'n500000 500000',
      ]);
      expect(rowsOn(t, red), ['n500000 500000']);
      expect(source.reads, lessThan(50));
    });

    testTwk('a frame scrolled a row takes as long with a million rows as '
        'with ten thousand', (t) async {
      Future<int> scroll(int rows) async {
        await t.pumpWidget(
          Theme.terminal(
            child: Table.source(
              key: ValueKey(rows),
              source: Numbered(rows),
              autofocus: true,
              columns: [
                nameColumn(),
                sizeColumn(width: const GridTrack.fr(1)),
              ],
            ),
          ),
          size: (40, 30),
        );
        // past the bottom: each a scroll
        for (var i = 0; i < 40; i++) {
          await t.press('down');
          await t.pump();
        }
        // real time on purpose: what the work costs is what is measured
        final watch = Stopwatch()..start();
        for (var i = 0; i < 200; i++) {
          await t.press('down');
          await t.pump();
        }
        expect(t.lines.last, startsWith('n239 '));
        return watch.elapsedMicroseconds ~/ 200;
      }

      final few = await scroll(10000);
      final many = await scroll(1000000);
      // generous: twice as long, and a millisecond
      expect(many, lessThan(2 * few + 1000), reason: '$many µs, $few µs');
    });

    testTwk('a source that notifies is read again: measured, sorted and the '
        'selection found on its row', (t) async {
      final names = ['b', 'c', 'a'];
      final source = Numbered(3, name: (i) => names[i]);
      final controller = TableController(sortColumn: 0, selectedKey: 'b');
      await t.pumpWidget(
        Theme.terminal(
          child: Table.source(
            source: source,
            rowKey: (f) => f.name,
            controller: controller,
            selectedStyle: const Style(bg: red),
            columns: [nameColumn(sorts: true), sizeColumn()],
          ),
        ),
        size: (20, 5),
      );
      expect(t.lines.skip(1), [
        'a         2',
        'b         0',
        'c         1',
        '',
      ]);
      expect(rowsOn(t, red), ['b         0']);
      names.insert(0, 'a-long-name');
      source.rowCount = 4;
      await t.pump();
      expect(t.lines.skip(1), [
        'a              3',
        'a-long-name    0',
        'b              1',
        'c              2',
      ]);
      expect(rowsOn(t, red), ['b              1']);
    });

    testTwk('scrolled a row, the rows below the header move in hardware, '
        'the row brought in written alone', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(100),
            selection: TableSelection.none,
            autofocus: true,
            columns: [nameColumn(), sizeColumn()],
          ),
        ),
        size: (20, 6),
      );
      final from = t.terminal.frames.length;
      await t.press('down');
      await t.pump();
      final written = latin1.decode([
        for (final f in t.terminal.frames.skip(from)) ...f,
      ]);
      expect(written, contains('\x1b[2;6r\x1b[S'));
      expect(written, contains('n5'));
      expect(written, isNot(contains('n4')));
      expect(t.lines, [
        'Name Size',
        'n1      1',
        'n2      2',
        'n3      3',
        'n4      4',
        'n5      5',
      ]);
    });

    testTwk('the selection moved past the bottom, the rows move in '
        'hardware, the row brought in written and the row left restyled', (
      t,
    ) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table(
            rows: numbered(100),
            controller: TableController(selectedKey: 4),
            selectedStyle: const Style(bg: red),
            autofocus: true,
            columns: [nameColumn(), sizeColumn()],
          ),
        ),
        size: (20, 6),
      );
      expect(rowsOn(t, red), ['n4      4']);
      final from = t.terminal.frames.length;
      await t.press('down');
      await t.pump();
      final written = latin1.decode([
        for (final f in t.terminal.frames.skip(from)) ...f,
      ]);
      // the rows moved in a region of four or five, as the presenter finds
      // it cheapest: the selected row's style kept where the row brought
      // in is selected, only its digits written
      expect(written, matches(RegExp(r'\x1b\[2;[56]r\x1b\[S')));
      for (final kept in ['n1', 'n2', 'n3']) {
        expect(written, isNot(contains(kept)));
      }
      expect(rowsOn(t, red), ['n5      5']);
      expect(t.lines.skip(1), [
        'n1      1',
        'n2      2',
        'n3      3',
        'n4      4',
        'n5      5',
      ]);
    });

    testTwk('the hidden cursor rests on the selected row, on the cursor '
        'cell where cells are selected', (t) async {
      for (final selection in [TableSelection.row, TableSelection.cell]) {
        await t.pumpWidget(
          Theme.terminal(
            child: Table(
              rows: numbered(10),
              controller: TableController(selectedKey: 2),
              selection: selection,
              autofocus: true,
              columns: [nameColumn(), sizeColumn()],
            ),
          ),
          size: (20, 6),
        );
        await t.pump();
        final row = t.lines.indexWhere((l) => l.startsWith('n2'));
        expect(t.cursorVisible, isFalse);
        expect(t.cursor, (0, row), reason: '$selection');
        if (selection == TableSelection.cell) {
          await t.press('right');
          await t.pump();
          // the size column, after the name and its gap
          expect(t.cursor.$1, greaterThan(1));
          expect(t.cursor.$2, row);
        }
        await t.press('down');
        await t.pump();
        expect(t.cursor.$2, row + 1, reason: '$selection');
      }
    });

    testTwk('widget cells keep their State as the rows are sorted, by the '
        "rows' keys", (t) async {
      final log = <String>[];
      final controller = TableController();
      await t.pumpWidget(
        Theme.terminal(
          child: Table<File>(
            rows: files,
            rowKey: (f) => f.name,
            controller: controller,
            columns: [
              nameColumn(sorts: true),
              TableColumn(
                title: 'State',
                width: const GridTrack.fixed(10),
                cell: (f) => TableCell.widget(Tally(f.kind, log)),
              ),
            ],
          ),
        ),
        size: (30, 4),
      );
      expect(log, ['+text', '+dart', '+x']);
      controller.sortBy(0);
      await t.pump();
      expect(t.lines.skip(1), [
        'a         x',
        'main.dart dart',
        'readme.md text',
      ]);
      expect(log, hasLength(3));
    });

    testTwk('rows are as tall as their tallest cell without a rowHeight', (
      t,
    ) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table<File>(
            rows: files,
            rowHeight: null,
            columns: [
              nameColumn(),
              TableColumn(
                title: 'Kind',
                width: const GridTrack.fr(1),
                cell: (f) => TableCell.widget(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(f.kind),
                      if (f.size > 100) const Text('large'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        size: (20, 6),
      );
      expect(t.lines, [
        'Name      Kind',
        'readme.md text',
        '          large',
        'main.dart dart',
        '          large',
        'a         x',
      ]);
    });

    testTwk('a cell of spans shows each in its style over the row', (t) async {
      await t.pumpWidget(
        Theme.terminal(
          child: Table<int>(
            rows: const [1],
            columns: [
              TableColumn(
                title: 'Status',
                cell: (_) => TableCell.rich([
                  'ok'.bold,
                  const Span(' '),
                  'done'.fg(red),
                ]),
              ),
            ],
          ),
        ),
        size: (20, 2),
      );
      expect(
        t,
        matchesScreen(styles: true, '''
[bold]Status[/]
[bold]ok[/] [#ff0000]done[/]'''),
      );
    });
  });
}
