// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/assists/move_widget.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(MoveWidgetUpTest);
    defineReflectiveTests(MoveWidgetDownTest);
  });
}

@reflectiveTest
class MoveWidgetUpTest extends TwkAssistTest {
  @override
  AssistKind get kind => MoveWidgetUp.kind;

  Future<void> test_lines_and_comments() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    Text('a'), // after a
    // about b
    ^Box(
      child: Text('b'),
    ),
    Text('c'),
  ],
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    // about b
    Box(
      child: Text('b'),
    ), // after a
    Text('a'),
    Text('c'),
  ],
);
''');
  }

  Future<void> test_variable() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget w) => Column(children: [Text('a'), ^w]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(Widget w) => Column(children: [w, Text('a')]);
''');
  }

  Future<void> test_not_first() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [^Text('a'), Text('b')]);
''');
    await assertNoAssist();
  }

  Future<void> test_not_past_if() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(bool c) => Column(children: [if (c) Text('a'), ^Text('b')]);
''');
    await assertNoAssist();
  }

  Future<void> test_not_in_if() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(bool c) => Column(children: [Text('a'), if (c) ^Text('b')]);
''');
    await assertNoAssist();
  }
}

@reflectiveTest
class MoveWidgetDownTest extends TwkAssistTest {
  @override
  AssistKind get kind => MoveWidgetDown.kind;

  Future<void> test_one_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [^Text('a'), Text('b'), Text('c')]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [Text('b'), Text('a'), Text('c')]);
''');
  }

  Future<void> test_not_last() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [Text('a'), ^Text('b')]);
''');
    await assertNoAssist();
  }

  Future<void> test_not_past_spread() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(List<Widget> more) => Column(children: [^Text('a'), ...more]);
''');
    await assertNoAssist();
  }

  Future<void> test_not_a_list_of_widgets() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

List<Object> f() => [^Text('a'), 1];
''');
    await assertNoAssist();
  }
}
