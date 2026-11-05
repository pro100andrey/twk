// A Table and a TreeTable whose rows shrink under a filter: the row
// selected, scrolled to, focused or the last one, none of it leaving a row
// built for an index the rows no longer have, and a new key starting over.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'tree_table_test.dart' show N, nameColumn, sizeColumn, table;

Widget flat(
  List<int> rows,
  TableController c, {
  Key? key,
  List<int>? data,
  bool byKey = false,
}) => Table<int>(
  key: key,
  rows: rows,
  controller: c,
  autofocus: true,
  rowKey: byKey ? (r) => 'k$r' : null,
  columns: [
    TableColumn<int>(
      title: 'N',
      // indexes a list by the row, as a cell builder over a list does
      cell: (r) => TableCell('v${(data ?? rows)[r]}'),
    ),
  ],
);

List<N> nodes(int n) => [for (var i = 0; i < n; i++) N('r$i', i)];

void main() {
  for (final byKey in [false, true]) {
    group('Table, rowKey $byKey', () {
      testTwk('a filter taking the rows below the selected one, scrolled '
          'down and focused', (t) async {
        final c = TableController();
        final data = [for (var i = 0; i < 100; i++) i * 10];
        await t.pumpWidget(
          flat([for (var i = 0; i < 100; i++) i], c, data: data, byKey: byKey),
          size: (10, 6),
        );
        c.selectedKey = byKey ? 'k90' : 90;
        await t.pump();
        for (var n = 80; n >= 0; n -= 20) {
          await t.pumpWidget(
            flat([for (var i = 0; i < n; i++) i], c, data: data, byKey: byKey),
            size: (10, 6),
          );
          await t.pump();
        }
        await t.press('down');
        await t.pumpWidget(
          flat([], c, data: data, byKey: byKey),
          size: (10, 6),
        );
        await t.pump();
        await t.pumpWidget(
          flat([5, 6, 7], c, data: data, byKey: byKey),
          size: (10, 6),
        );
        expect(t.lines[1], contains('v50'));
      });

      testTwk('a new key and a shrunk list with a shared controller', (
        t,
      ) async {
        final c = TableController();
        final data = [for (var i = 0; i < 100; i++) i];
        await t.pumpWidget(
          flat([for (var i = 0; i < 50; i++) i], c, data: data, byKey: byKey),
          size: (10, 6),
        );
        c.selectedKey = byKey ? 'k40' : 40;
        await t.pump();
        await t.pumpWidget(
          flat(
            [1, 2, 3],
            c,
            key: const ValueKey('b'),
            data: data,
            byKey: byKey,
          ),
          size: (10, 6),
        );
        await t.pump();
        expect(t.lines[1], contains('v1'));
        expect(t.lines[3], contains('v3'));
      });
    });
  }

  group('a selection moved as the rows shrink', () {
    testTwk('the row left is not built again from the rows it was built in, '
        'by a cell builder reading what has shrunk since', (t) async {
      final c = TableController();
      var live = [for (var i = 0; i < 20; i++) 'v$i'];
      Widget build(List<int> rows) => Table<int>(
        rows: rows,
        controller: c,
        autofocus: true,
        columns: [
          TableColumn<int>(title: 'N', cell: (r) => TableCell(live[r])),
        ],
      );
      await t.pumpWidget(
        build([for (var i = 0; i < 20; i++) i]),
        size: (10, 6),
      );
      c.selectedKey = 15;
      await t.pump();
      // the data shrinks and the selection moves in one go, before a frame
      live = [for (var i = 0; i < 5; i++) 'w$i'];
      c.selectedKey = 2;
      await t.pumpWidget(build([for (var i = 0; i < 5; i++) i]), size: (10, 6));
      expect(t.lines[1], contains('w0'));
    });
  });

  group('TreeTable', () {
    testTwk('roots shrinking under a selected, scrolled row, in a '
        'LayoutBuilder', (t) async {
      final c = TreeController();
      final tc = TableController();
      Widget build(int n, {Key? key}) => LayoutBuilder(
        builder: (context, box) => SizedBox(
          key: key,
          child: table(nodes(n), controller: c, tableController: tc),
        ),
      );
      await t.pumpWidget(build(100), size: (20, 6));
      c.selectedKey = 'r90';
      await t.pump();
      await t.press('down');
      for (final n in [60, 10, 0, 4]) {
        await t.pumpWidget(build(n), size: (20, 6));
        await t.pump();
      }
      expect(t.lines[1], contains('r0'));
      await t.press('down');
      await t.pumpWidget(build(3, key: const ValueKey('new')), size: (20, 6));
      await t.pump();
      expect(t.lines[1], contains('r0'));
      expect(t.lines[3], contains('r2'));
    });

    testTwk('expanded children removed with the selection in them', (t) async {
      final c = TreeController(expanded: ['a'], selectedKey: 'a9');
      final big = [
        N('a', 0, [for (var i = 0; i < 20; i++) N('a$i', i)]),
        N('b', 1),
      ];
      await t.pumpWidget(table(big, controller: c), size: (20, 6));
      await t.pump();
      await t.press('down');
      await t.pumpWidget(
        table([N('a', 0, const []), const N('b', 1)], controller: c),
        size: (20, 6),
      );
      await t.pump();
      await t.press('down');
      await t.pumpWidget(
        table(
          [const N('b', 1)],
          controller: c,
          columns: [nameColumn(), sizeColumn],
        ),
        size: (20, 6),
      );
      await t.pump();
      expect(t.lines[1], contains('b'));
    });

    testTwk('a TreeTable given a new key is not empty', (t) async {
      final c = TreeController(selectedKey: 'r40');
      Widget build(List<N> roots, Key key) => SizedBox(
        key: key,
        child: table(roots, controller: c),
      );
      await t.pumpWidget(build(nodes(50), const ValueKey(1)), size: (20, 6));
      await t.pump();
      await t.pumpWidget(build(nodes(5), const ValueKey(2)), size: (20, 6));
      await t.pump();
      expect(t.lines[1], contains('r0'));
      await t.pumpWidget(build(nodes(3), const ValueKey(3)), size: (20, 6));
      await t.pump();
      expect(t.lines[1], contains('r0'));
      expect(t.lines[3], contains('r2'));
    });
  });
}
