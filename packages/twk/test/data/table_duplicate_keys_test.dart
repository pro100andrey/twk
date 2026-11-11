// A table's rows with one key assert, with a hint; rows without a rowKey
// are keyed by their index.
import 'package:test/test.dart';
import 'package:twk/src/foundation/helpers.dart' show debugDistinctLimit;
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

Widget table(List<String> rows, {bool keyed = true}) => Theme.terminal(
  child: Table<String>(
    rows: rows,
    rowKey: keyed ? (r) => r : null,
    columns: const [TableColumn(title: 'name', cell: TableCell.new)],
  ),
);

List<String> errors(TwkTester t) => [
  for (final r in t.takeErrors())
    if (r.error is AssertionError) '${r.error}' else 'other: ${r.error}',
];

void main() {
  testTwk('two rows with one key assert', (t) async {
    await t.pumpWidget(table(['a', 'b', 'a']));
    expect(errors(t), [contains('Table has two rows with the key a (at 2)')]);
  });

  testTwk('a table refused for its keys leaves no controller undisposed', (
    t,
  ) async {
    await t.pumpWidget(table(['a', 'b', 'a']));
    expect(errors(t), isNotEmpty);
  }, trackDisposables: true);

  testTwk('a new list with a duplicate asserts; equal rows without a '
      'rowKey do not', (t) async {
    await t.pumpWidget(table(['a', 'a'], keyed: false));
    await t.pumpWidget(table(['a', 'b']));
    expect(errors(t), isEmpty);
    await t.pumpWidget(table(['b', 'b']));
    expect(errors(t), [contains('Table has two rows with the key b (at 1)')]);
  });

  testTwk('a duplicate past the cap asserts at the first build, and a '
      'rebuild with an inline rowKey reads at most the cap', (t) async {
    final rows = [for (var i = 0; i < 5000; i++) '${i == 3000 ? 0 : i}'];
    await t.pumpWidget(table(rows));
    expect(errors(t), [
      contains('Table has two rows with the key 0 (at 3000)'),
    ]);

    final ok = [for (var i = 0; i < 5000; i++) '$i'];
    var reads = 0;
    Widget inline() => Theme.terminal(
      child: Table<String>(
        rows: ok,
        rowKey: (r) {
          reads++;
          return r;
        },
        columns: const [TableColumn(title: 'name', cell: TableCell.new)],
      ),
    );
    await t.pumpWidget(inline());
    reads = 0;
    await t.pumpWidget(inline());
    expect(errors(t), isEmpty);
    expect(reads, lessThanOrEqualTo(debugDistinctLimit + 200));
  });
}
