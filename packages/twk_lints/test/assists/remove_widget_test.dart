// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/assists/remove_widget.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RemoveWidgetTest);
  });
}

@reflectiveTest
class RemoveWidgetTest extends TwkAssistTest {
  @override
  AssistKind get kind => RemoveWidget.kind;

  Future<void> test_child() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(
  child: ^Padding(
    padding: const EdgeInsets.all(1),
    child: Column(
      // the rows
      children: [Text('a')],
    ),
  ),
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Box(
  child: Column(
    // the rows
    children: [Text('a')],
  ),
);
''');
  }

  Future<void> test_child_one_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart' as t;

t.Widget f() => t.Box(child: t.^Padding(padding: const t.EdgeInsets.all(1), child: t.Text('a')));
''');
    await assertHasAssist('''
import 'package:twk/twk.dart' as t;

t.Widget f() => t.Box(child: t.Text('a'));
''');
  }

  Future<void> test_children_spliced() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(bool more) => Column(
  children: [
    Text('a'),
    ^Column(
      children: [
        // b first
        Text('b'),
        if (more) Text('c'),
      ],
    ),
    Text('d'),
  ],
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(bool more) => Column(
  children: [
    Text('a'),
    // b first
    Text('b'),
    if (more) Text('c'),
    Text('d'),
  ],
);
''');
  }

  Future<void> test_children_empty() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [Text('a'), ^Column(children: []), Text('b')]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [Text('a'), Text('b')]);
''');
  }

  Future<void> test_children_empty_last() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    Text('a'),
    ^Column(children: []),
  ],
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    Text('a'),
  ],
);
''');
  }

  Future<void> test_children_empty_only() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [^Column(children: [])]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(children: []);
''');
  }

  Future<void> test_one_of_children_where_one_widget() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(child: ^Column(children: [Text('a')]));
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Box(child: Text('a'));
''');
  }

  Future<void> test_not_children_where_one_widget() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(child: ^Column(children: [Text('a'), Text('b')]));
''');
    await assertNoAssist();
  }

  Future<void> test_not_nullable_child_where_required() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget? w) => InputListener(
  onEvent: (_) => false,
  child: ^Padding(padding: const EdgeInsets.all(1), child: w),
);
''');
    await assertNoAssist();
  }

  Future<void> test_not_without_child() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(child: ^Box());
''');
    await assertNoAssist();
  }
}
