// A column aligned to its end puts its cells and its title at its right
// edge, the title of the column the rows are sorted by with its arrow too.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

typedef File = ({String name, int size});

const files = <File>[
  (name: 'readme.md', size: 120),
  (name: 'main.dart', size: 3400),
  (name: 'a', size: 5),
];

void main() {
  testTwk('an end-aligned column hugs its right edge, sorted by it too', (
    t,
  ) async {
    await t.pumpWidget(
      Table<File>(
        rows: files,
        controller: TableController(sortColumn: 1),
        columns: [
          TableColumn(title: 'Name', cell: (f) => TableCell(f.name)),
          TableColumn(
            title: 'Size',
            cell: (f) => TableCell('${f.size}'),
            width: const GridTrack.fixed(8),
            align: TextAlign.end,
            compare: (a, b) => a.size.compareTo(b.size),
          ),
        ],
      ),
      size: (30, 4),
    );
    String row(String name, String size) =>
        '${name.padRight(9)} ${size.padLeft(8)}';
    expect(t.lines, [
      row('Name', 'Size ▴'),
      row('a', '5'),
      row('readme.md', '120'),
      row('main.dart', '3400'),
    ]);
  });
}
