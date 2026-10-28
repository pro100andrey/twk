// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/assists/wrap_builder.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(WrapWithBuilderTest);
    defineReflectiveTests(WrapWithValueListenableBuilderTest);
  });
}

@reflectiveTest
class WrapWithBuilderTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithBuilder.kind;

  Future<void> test_one_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(child: ^Text('a'));
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Box(child: Builder(builder: (context) => Text('a')));
''');
  }

  Future<void> test_lines() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => ^Box(
  child: Text('a'),
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Builder(
  builder: (context) => Box(
    child: Text('a'),
  ),
);
''');
  }

  Future<void> test_context_of_its_own() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

Widget f(BuildContext context) => ^Text('${context.mounted}');
''');
    await assertHasAssist(r'''
import 'package:twk/twk.dart';

Widget f(BuildContext context) => Builder(builder: (context) => Text('${context.mounted}'));
''');
  }

  Future<void> test_context_read_from_around() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(String context) => ^Text(context);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(String context) => Builder(builder: (context2) => Text(context));
''');
  }

  Future<void> test_not_in_a_constant() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => const Column(children: [^Text('a')]);
''');
    await assertNoAssist();
  }

  Future<void> test_not_a_nullable_widget() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget? w) => Box(child: ^w);
''');
    await assertNoAssist();
  }
}

@reflectiveTest
class WrapWithValueListenableBuilderTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithValueListenableBuilder.kind;

  Future<void> test_creation() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => ^Text('a');
''');
    final change = await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => ValueListenableBuilder(
  valueListenable: valueListenable,
  builder: (context, value, child) => Text('a'),
);
''');
    expectSnippetShape(change);
    final group = change.linkedEditGroups.single;
    expect(
      group.positions.single.offset,
      testCode.indexOf("Text('a')") +
          'ValueListenableBuilder(\n'
                  '  valueListenable: '
              .length,
    );
    expect(group.length, 'valueListenable'.length);
  }

  Future<void> test_names_read_from_around() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget child, String value) =>
    Box(child: ^Padding(padding: EdgeInsets.all(1), child: child));
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(Widget child, String value) =>
    Box(child: ValueListenableBuilder(
      valueListenable: valueListenable,
      builder: (context, value, child2) => Padding(padding: EdgeInsets.all(1), child: child),
    ));
''');
  }

  Future<void> test_names_of_arguments_and_members() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(ValueListenable<String> n) => ^Box(child: Text(n.value));
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(ValueListenable<String> n) => ValueListenableBuilder(
  valueListenable: valueListenable,
  builder: (context, value, child) => Box(child: Text(n.value)),
);
''');
  }
}
