// What Dart infers for a Table written without its type argument, checked
// at compile time: each `expectStaticType` stops this file compiling where
// the type is not exactly the one named.
//
// Dart infers the arguments of a call that are not function literals
// first, all of them against the parameters' types with the type
// arguments still unknown, none of them seeing the others; only a function
// literal whose parameters' types name a type argument waits for it (the
// horizontal inference of Dart 3). So a list of columns written in place
// is inferred apart from the rows: each `TableColumn(...)` in it has
// nothing to give its own type argument but its closure, which fixes it
// at `Object?`, and the table's is then the rows' and the columns' upper
// bound, `Object?`. A table or a column given its type argument, or
// columns from elsewhere, are typed.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// `T Function(T)`: `Exactly<A>` is a subtype of `Exactly<B>` only where
/// A is B.
typedef Exactly<T> = T Function(T);

extension<T> on T {
  /// Compiles only where the static type of this is exactly [R]'s.
  void expectStaticType<R extends Exactly<T>>() {}
}

final class Person {
  const Person(this.name, this.id);

  final String name;
  final int id;
}

const people = [Person('Ada', 2), Person('Brian', 1)];

/// The columns of a table of [Person]s, from elsewhere.
List<TableColumn<Person>> personColumns() => [
  TableColumn(title: 'Name', cell: (p) => TableCell(p.name)),
];

final class People extends TableSource<Person> {
  @override
  int get rowCount => people.length;

  @override
  Person rowAt(int index) => people[index];
}

void main() {
  testTwk('a Table<Person> types the columns written in it', (t) async {
    await t.pumpWidget(
      Table<Person>(
        rows: people,
        columns: [
          TableColumn(
            title: 'Name',
            cell: (p) {
              p.expectStaticType<Exactly<Person>>();
              return TableCell(p.name);
            },
            compare: (a, b) => a.name.compareTo(b.name),
          ),
          TableColumn(title: 'Id', cell: (p) => TableCell('${p.id}')),
        ],
        rowKey: (p) => p.id,
        onActivated: (p) => p.name,
      ),
      size: (10, 3),
    );
    expect(t.lines, ['Name   Id', 'Ada    2', 'Brian  1']);
  });

  test('typed columns give the table its row type', () {
    Table(
      rows: people,
      columns: [
        TableColumn<Person>(title: 'Name', cell: (p) => TableCell(p.name)),
        TableColumn<Person>(title: 'Id', cell: (p) => TableCell('${p.id}')),
      ],
      rowKey: (p) => p.id,
    ).expectStaticType<Exactly<Table<Person>>>();
    Table(
      rows: people,
      columns: personColumns(),
    ).expectStaticType<Exactly<Table<Person>>>();
  });

  test('a table of a source takes its row type the same ways', () {
    Table<Person>.source(
      source: People(),
      columns: [TableColumn(title: 'Name', cell: (p) => TableCell(p.name))],
    ).expectStaticType<Exactly<Table<Person>>>();
    Table.source(
      source: People(),
      columns: personColumns(),
    ).expectStaticType<Exactly<Table<Person>>>();
  });

  // Where a later Dart infers the rows' type here, this stops compiling:
  // the README's note on Table's type argument then goes.
  test('columns written in place leave a table of Object?', () {
    TableColumn(
      title: 'Row',
      cell: (p) => TableCell('$p'),
    ).expectStaticType<Exactly<TableColumn<Object?>>>();
    Table(
      rows: people,
      columns: [TableColumn(title: 'Row', cell: (p) => TableCell('$p'))],
      rowKey: (p) {
        p.expectStaticType<Exactly<Object?>>();
        return p!;
      },
    ).expectStaticType<Exactly<Table<Object?>>>();
    Table.source(
      source: People(),
      columns: [TableColumn(title: 'Row', cell: (p) => TableCell('$p'))],
    ).expectStaticType<Exactly<Table<Object?>>>();
    // A column typed beside one that is not: the list is of their upper
    // bound.
    Table(
      rows: people,
      columns: [
        TableColumn<Person>(title: 'Name', cell: (p) => TableCell(p.name)),
        TableColumn(title: 'Row', cell: (p) => TableCell('$p')),
      ],
    ).expectStaticType<Exactly<Table<Object?>>>();
  });
}
