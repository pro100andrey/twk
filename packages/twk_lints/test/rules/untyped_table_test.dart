// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/fixes/add_row_type.dart';
import 'package:twk_lints/src/rules/untyped_table.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(UntypedTableTest);
  });
}

@reflectiveTest
class UntypedTableTest extends TwkRuleTest {
  @override
  void setUp() {
    rule = UntypedTable();
    super.setUp();
  }

  Future<void> test_dynamic() async {
    const code = r'''
import 'package:twk/twk.dart';

Widget f(List<dynamic> rows) => Table(
  rows: rows,
  columns: [TableColumn(title: 'name', cell: (row) => TableCell('$row'))],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'Table', messageContainsAll: ["'dynamic'"]),
    ]);
  }

  Future<void> test_nullable_and_object() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(
  List<String?> a,
  List<TableColumn<String?>> c,
  List<Object> b,
  List<TableColumn<Object>> d,
) => Column(
  children: [
    Table(rows: a, columns: c),
    Table(rows: b, columns: d),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'Table(', length: 5, messageContainsAll: ["'String?'"]),
      lintAt(
        code,
        'Table(',
        occurrence: 1,
        length: 5,
        messageContainsAll: ["'Object'"],
      ),
    ]);
  }

  Future<void> test_columns_inferred_loosely() async {
    // the closure's row is inferred apart from the rows: Object?
    const code = r'''
import 'package:twk/twk.dart';

Widget f(List<String> rows) => Table(
  rows: rows,
  columns: [TableColumn(title: 'name', cell: (row) => TableCell('$row'))],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'Table', messageContainsAll: ["'Object?'"]),
    ]);
  }

  Future<void> test_inferred() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(List<String> rows, List<TableColumn<String>> columns) =>
    Table(rows: rows, columns: columns);
''');
  }

  Future<void> test_written() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(List<Object?> rows) =>
    Table<Object?>(rows: rows, columns: []);
''');
  }

  Future<void> test_fix_writes_the_type_of_the_rows() async {
    const code = '''
import 'package:twk/twk.dart' as twk;

final class Todo {
  String get title => '';
}

twk.Widget f(List<Todo> todos) => twk.Table(
  rows: todos,
  columns: [twk.TableColumn(title: 'title', cell: (t) => twk.TableCell(''))],
);
''';
    await assertDiagnostics(code, [lintAt(code, 'twk.Table')]);
    expect(
      await fixed(AddRowType.new),
      code.replaceFirst('twk.Table(', 'twk.Table<Todo>('),
    );
  }

  Future<void> test_fix_imports_the_type_and_writes_its_arguments() async {
    newFile('$testPackageLibPath/item.dart', 'final class Item<T> {}');
    newFile('$testPackageLibPath/data.dart', '''
import 'item.dart';

List<Item<int>> items() => [];
''');
    const code = '''
import 'package:twk/twk.dart';

import 'data.dart';

Widget f() => Table(
  rows: items(),
  columns: [TableColumn(title: 'item', cell: (i) => TableCell(''))],
);
''';
    await assertDiagnostics(code, [lintAt(code, 'Table')]);
    expect(
      await fixed(AddRowType.new),
      "import 'package:test/item.dart';\n"
      '${code.replaceFirst('Table(', 'Table<Item<int>>(')}',
    );
  }

  Future<void> test_fix_of_a_type_parameter() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f<T extends Object>(List<T> rows) => Table(
  rows: rows,
  columns: [TableColumn(title: 'row', cell: (r) => TableCell(''))],
);
''';
    await assertDiagnostics(code, [lintAt(code, 'Table')]);
    expect(
      await fixed(AddRowType.new),
      code.replaceFirst('Table(', 'Table<T>('),
    );
  }

  Future<void> test_no_fix_where_the_rows_are_loose_or_private() async {
    newFile('$testPackageLibPath/data.dart', '''
final class _Secret {}

List<_Secret> secrets() => [];
''');
    const code = r'''
import 'package:twk/twk.dart';

import 'data.dart';

Widget f(List<String?> names, List<dynamic> any, List<int> Function() g) =>
    Column(
      children: [
        Table(
          rows: names,
          columns: [TableColumn(title: 'n', cell: (n) => TableCell('$n'))],
        ),
        Table(
          rows: any,
          columns: [TableColumn(title: 'a', cell: (a) => TableCell('$a'))],
        ),
        Table(
          rows: secrets(),
          columns: [TableColumn(title: 's', cell: (s) => TableCell('$s'))],
        ),
      ],
    );
''';
    await assertDiagnostics(code, [
      lintAt(code, 'Table(', length: 5),
      lintAt(code, 'Table(', occurrence: 1, length: 5),
      lintAt(code, 'Table(', occurrence: 2, length: 5),
    ]);
    for (var i = 0; i < 3; i++) {
      expect(await fixed(AddRowType.new, index: i), isNull);
    }
  }
}
