// A Table's padding scrolls with its rows, as a ListView's does: the rows
// before the first and after the last are part of what scrolls, the header
// stays above them, and the columns on either side inset the header and
// every row alike. The row selected is kept in view with the padding.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

typedef Row = ({String name, int size});

final List<Row> rows = [for (var i = 0; i < 100; i++) (name: 'n$i', size: i)];

final columns = <TableColumn<Row>>[
  TableColumn(title: 'Name', cell: (r) => TableCell(r.name)),
  TableColumn(
    title: 'Size',
    cell: (r) => TableCell('${r.size}'),
    width: const GridTrack.fixed(4),
    align: TextAlign.right,
  ),
];

Widget table({
  EdgeInsets? padding,
  TableController? controller,
  int? rowHeight = 1,
  bool header = true,
}) => Theme.terminal(
  child: Table(
    rows: rows,
    autofocus: true,
    controller: controller,
    padding: padding,
    rowHeight: rowHeight,
    showHeader: header,
    columns: columns,
  ),
);

const pad = EdgeInsets.only(top: 2, bottom: 1);

void main() {
  testTwk('the rows are below the padding, the header above it', (t) async {
    await t.pumpWidget(table(padding: pad), size: (20, 7));
    expect(t.lines, [
      'Name Size',
      '',
      '',
      'n0      0',
      'n1      1',
      'n2      2',
      'n3      3',
    ]);
  });

  testTwk('scrolled, the padding goes with the rows, the header stays', (
    t,
  ) async {
    final controller = TableController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      table(padding: pad, controller: controller),
      size: (20, 7),
    );
    // End selects the last row, which is shown with the padding after it
    await t.press('end');
    await t.pump();
    expect(t.lines, [
      'Name Size',
      'n95    95',
      'n96    96',
      'n97    97',
      'n98    98',
      'n99    99',
      '',
    ]);
    // the wheel up three rows
    await t.mouse(MouseKind.wheelUp, 2, 3);
    await t.pump();
    expect(t.lines.first, 'Name Size');
    expect(t.lines[1], 'n92    92');
    // Home selects the first, shown with the padding before it
    await t.press('home');
    await t.pump();
    expect(t.lines, [
      'Name Size',
      '',
      '',
      'n0      0',
      'n1      1',
      'n2      2',
      'n3      3',
    ]);
  });

  testTwk('the row selected by the keys is kept in view', (t) async {
    await t.pumpWidget(table(padding: pad), size: (20, 7));
    for (var i = 0; i < 5; i++) {
      await t.press('down');
    }
    await t.pump();
    // row 4 is the fifth of the six rows below the header and the padding:
    // the window was moved the least that shows it
    expect(t.lines, [
      'Name Size',
      '',
      'n0      0',
      'n1      1',
      'n2      2',
      'n3      3',
      'n4      4',
    ]);
  });

  testTwk('left and right inset the header and the rows alike, the columns '
      'taking what is left', (t) async {
    await t.pumpWidget(
      table(padding: const EdgeInsets.only(left: 2, right: 1)),
      size: (20, 3),
    );
    expect(t.lines, ['  Name Size', '  n0      0', '  n1      1']);
    // the columns are those of 17 cells: Name takes what Size leaves
    await t.pumpWidget(
      Theme.terminal(
        child: Table(
          rows: rows,
          padding: const EdgeInsets.only(left: 2, right: 1),
          columns: [
            TableColumn<Row>(
              title: 'Name',
              cell: (r) => TableCell(r.name),
              width: const GridTrack.fr(1),
            ),
            TableColumn<Row>(
              title: 'Size',
              cell: (r) => TableCell('${r.size}'),
              width: const GridTrack.fixed(4),
              align: TextAlign.right,
            ),
          ],
        ),
      ),
    );
    // 20 - 2 - 1 cells: Name 12, a gap, Size 4
    expect(t.lines.first, '${'  Name'.padRight(2 + 12 + 1)}Size');
  });

  testTwk('rows taller than a row and the padding add up', (t) async {
    await t.pumpWidget(
      table(padding: const EdgeInsets.only(top: 1), rowHeight: 2),
      size: (20, 6),
    );
    expect(t.lines, ['Name Size', '', 'n0      0', '', 'n1      1', '']);
  });

  testTwk('without the header, the padding is at the top of the table', (
    t,
  ) async {
    await t.pumpWidget(table(padding: pad, header: false), size: (20, 4));
    expect(t.lines, ['', '', 'n0      0', 'n1      1']);
  });

  testTwk('without padding, or with none, is what a table was', (t) async {
    await t.pumpWidget(table(), size: (20, 3));
    final plain = t.lines;
    expect(plain, ['Name Size', 'n0      0', 'n1      1']);
    await t.pumpWidget(table(padding: EdgeInsets.zero));
    expect(t.lines, plain);
  });
}
