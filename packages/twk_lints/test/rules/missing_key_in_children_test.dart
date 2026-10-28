// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/fixes/add_value_key.dart';
import 'package:twk_lints/src/rules/missing_key_in_children.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(MissingKeyInChildrenTest);
  });
}

@reflectiveTest
class MissingKeyInChildrenTest extends TwkRuleTest {
  @override
  void setUp() {
    rule = MissingKeyInChildren();
    super.setUp();
  }

  Future<void> test_for_element() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(List<String> items) => Column(
  children: [for (final item in items) TextField()],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'TextField', messageContainsAll: ["'TextField'"]),
    ]);
  }

  Future<void> test_for_element_keyed() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(List<String> items) => Column(
  children: [for (final item in items) TextField(key: ValueKey(item))],
);
''');
  }

  Future<void> test_for_if_and_conditional() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(List<String> items, bool a) => Column(
  children: [
    for (final item in items)
      if (item.isEmpty) TextField() else (a ? TextField() : Text(item)),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'TextField'),
      lintAt(code, 'TextField', occurrence: 1),
    ]);
  }

  Future<void> test_spread_map() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(List<String> items) => Column(
  children: [
    ...items.map((item) => TextField()),
    ...items.map((item) {
      return TextField();
    }).toList(),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'TextField'),
      lintAt(code, 'TextField', occurrence: 1),
    ]);
  }

  Future<void> test_stateless() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(List<String> items) =>
    Column(children: [for (final item in items) Text(item)]);
''');
  }

  Future<void> test_one_child() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [TextField(), TextField()]);
''');
  }

  Future<void> test_no_key_parameter() async {
    await assertNoDiagnostics('''
import 'package:twk/twk.dart';

Widget f(List<String> items) =>
    Column(children: [for (final item in items) Spinner()]);
''');
  }

  Future<void> test_fix_for_element() async {
    const code = '''
import 'package:twk/twk.dart';

Widget f(List<String> items) => Column(
  children: [for (final item in items) if (item.isNotEmpty) TextField()],
);
''';
    await assertDiagnostics(code, [lintAt(code, 'TextField')]);
    expect(
      await fixed(AddValueKey.new),
      code.replaceFirst('TextField()', 'TextField(key: ValueKey(item))'),
    );
  }

  Future<void> test_fix_map_before_the_first_named_argument() async {
    const code = '''
import 'package:twk/twk.dart' as twk;

twk.Widget f(List<String> items) => twk.Column(
  children: [
    ...items.map((i) => twk.TextField(placeholder: i)),
    ...items.map((i) {
      return twk.TextField(
        placeholder: i,
      );
    }),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'twk.TextField'),
      lintAt(code, 'twk.TextField', occurrence: 1),
    ]);
    expect(
      await fixed(AddValueKey.new),
      code.replaceFirst(
        'twk.TextField(placeholder: i)',
        'twk.TextField(key: twk.ValueKey(i), placeholder: i)',
      ),
    );
    expect(
      await fixed(AddValueKey.new, index: 1),
      code.replaceFirst(
        '        placeholder: i,\n',
        '        key: twk.ValueKey(i),\n        placeholder: i,\n',
      ),
    );
  }

  Future<void> test_fix_after_positional_arguments_and_without_const() async {
    const code = '''
import 'package:twk/twk.dart';

enum Kind { a, b }

final class Tile extends StatefulWidget {
  const Tile(this.n, {super.key});
  final int n;
  @override
  State<Tile> createState() => throw 0;
}

Widget f(List<int> ns, List<Kind> kinds) => Column(
  children: [
    for (final n in ns) Tile(n),
    for (final kind in kinds)
      if (kind == Kind.a)
        const Tile(
          1,
        ),
  ],
);
''';
    await assertDiagnostics(code, [
      lintAt(code, 'Tile(n', length: 4),
      lintAt(code, 'Tile(\n', length: 4),
    ]);
    expect(
      await fixed(AddValueKey.new),
      code.replaceFirst('Tile(n)', 'Tile(n, key: ValueKey(n))'),
    );
    expect(
      await fixed(AddValueKey.new, index: 1),
      code.replaceFirst(
        '        const Tile(\n          1,\n',
        '        Tile(\n          1,\n          key: ValueKey(kind),\n',
      ),
    );
  }

  Future<void> test_no_fix_where_the_variable_is_no_key() async {
    const code = r'''
import 'package:twk/twk.dart';

final class Todo {}

Widget f(List<Todo> todos, List<String?> names, List<List<int>> rows) =>
    Column(
      children: [
        for (final todo in todos) TextField(placeholder: '$todo'),
        for (final name in names) TextField(placeholder: name),
        for (var i = 0; i < 3; i++) TextField(placeholder: '$i'),
        for (final row in rows)
          for (final cell in row) TextField(placeholder: '$cell'),
        ...todos.map((todo) => TextField(placeholder: '$todo')),
      ],
    );
''';
    await assertDiagnostics(code, [
      lintAt(code, 'TextField'),
      lintAt(code, 'TextField', occurrence: 1),
      lintAt(code, 'TextField', occurrence: 2),
      lintAt(code, 'TextField', occurrence: 3),
      lintAt(code, 'TextField', occurrence: 4),
    ]);
    for (var i = 0; i < 5; i++) {
      expect(await fixed(AddValueKey.new, index: i), isNull);
    }
  }
}
