// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/assists/wrap_flex.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(WrapWithRowTest);
    defineReflectiveTests(WrapWithColumnTest);
    defineReflectiveTests(WrapWithExpandedTest);
    defineReflectiveTests(WrapWithFlexibleTest);
  });
}

@reflectiveTest
class WrapWithRowTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithRow.kind;

  Future<void> test_one_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(child: ^Text('a'));
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Box(child: Row(children: [Text('a')]));
''');
  }

  Future<void> test_lines() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(
  child: ^Box(
    child: Text('a'),
  ),
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Box(
  child: Row(
    children: [
      Box(
        child: Text('a'),
      ),
    ],
  ),
);
''');
  }

  Future<void> test_selection_lines() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(bool c) => Column(
  children: [
    Text('a'),
    Te[!xt('b'),
    // about c
    if (c) Text('c'),
    Box(
      child: Te!]xt('d'),
    ),
    Text('e'),
  ],
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(bool c) => Column(
  children: [
    Text('a'),
    Row(
      children: [
        Text('b'),
        // about c
        if (c) Text('c'),
        Box(
          child: Text('d'),
        ),
      ],
    ),
    Text('e'),
  ],
);
''');
  }

  Future<void> test_selection_one_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(List<Widget> more) =>
    Column(children: [Text('a'), /*[0*/Text('b'), ...more/*0]*/]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(List<Widget> more) =>
    Column(children: [Text('a'), Row(children: [Text('b'), ...more])]);
''');
  }

  Future<void> test_not_a_nullable_widget() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget? w) => Box(child: ^w);
''');
    await assertNoAssist();
  }

  Future<void> test_not_a_selection_in_a_list_of_objects() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

List<Object> f() => [[!Text('a'), Text('b')!]];
''');
    await assertNoAssist();
  }
}

@reflectiveTest
class WrapWithColumnTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithColumn.kind;

  Future<void> test_one_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart' as t;

t.Widget f() => t.^Text('a');
''');
    await assertHasAssist('''
import 'package:twk/twk.dart' as t;

t.Widget f() => t.Column(children: [t.Text('a')]);
''');
  }

  Future<void> test_selection() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Row(children: [[!Text('a'), Text('b')!]]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Row(children: [Column(children: [Text('a'), Text('b')])]);
''');
  }
}

@reflectiveTest
class WrapWithExpandedTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithExpanded.kind;

  Future<void> test_child_of_a_row() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Row(children: [Text('a'), ^Text('b')]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Row(children: [Text('a'), Expanded(child: Text('b'))]);
''');
  }

  Future<void> test_in_an_if() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(bool c) => Column(children: [if (c) ^Text('a')]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(bool c) => Column(children: [if (c) Expanded(child: Text('a'))]);
''');
  }

  Future<void> test_not_in_a_list_of_its_own() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

List<Widget> f() => [^Text('a')];
''');
    await assertNoAssist();
  }

  Future<void> test_not_in_a_stack() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Stack(children: [^Text('a')]);
''');
    await assertNoAssist();
  }

  Future<void> test_not_a_child() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(child: ^Text('a'));
''');
    await assertNoAssist();
  }

  Future<void> test_not_a_flexible() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Row(children: [^Flexible(child: Text('a'))]);
''');
    await assertNoAssist();
  }

  Future<void> test_not_a_spacer() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Row(children: [^Spacer()]);
''');
    await assertNoAssist();
  }
}

@reflectiveTest
class WrapWithFlexibleTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithFlexible.kind;

  Future<void> test_child_of_a_column() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    ^Box(
      child: Text('a'),
    ),
  ],
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    Flexible(
      child: Box(
        child: Text('a'),
      ),
    ),
  ],
);
''');
  }

  Future<void> test_not_an_expanded() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Row(children: [^Expanded(child: Text('a'))]);
''');
    await assertNoAssist();
  }
}
