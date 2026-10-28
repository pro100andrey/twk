// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/assists/swap_widgets.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SwapWithChildTest);
    defineReflectiveTests(SwapWithParentTest);
  });
}

@reflectiveTest
class SwapWithChildTest extends TwkAssistTest {
  @override
  AssistKind get kind => SwapWithChild.kind;

  Future<void> test_lines() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    ^Box(
      border: const Border.all(),
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Column(
          children: [Text('a')],
        ),
      ),
    ),
  ],
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    Padding(
      padding: const EdgeInsets.all(1),
      child: Box(
        border: const Border.all(),
        child: Column(
          children: [Text('a')],
        ),
      ),
    ),
  ],
);
''');
  }

  Future<void> test_child_on_the_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => ^Box(child: Padding(
  padding: const EdgeInsets.all(1),
  child: Text('a'),
));
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Padding(
  padding: const EdgeInsets.all(1),
  child: Box(child: Text('a')),
);
''');
  }

  Future<void> test_const_of_the_child() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Border border) => ^Box(border: border, child: const Padding(padding: EdgeInsets.all(1), child: Text('a')));
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(Border border) => Padding(padding: EdgeInsets.all(1), child: Box(border: border, child: Text('a')));
''');
  }

  Future<void> test_not_child_without_child() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => ^Box(child: Text('a'));
''');
    await assertNoAssist();
  }

  Future<void> test_not_child_a_variable() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget w) => ^Box(child: w);
''');
    await assertNoAssist();
  }

  Future<void> test_not_nullable_grandchild_where_required() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget? w) => ^InputListener(
  onEvent: (_) => false,
  child: Padding(padding: const EdgeInsets.all(1), child: w),
);
''');
    await assertNoAssist();
  }
}

@reflectiveTest
class SwapWithParentTest extends TwkAssistTest {
  @override
  AssistKind get kind => SwapWithParent.kind;

  Future<void> test_one_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(child: ^Padding(padding: const EdgeInsets.all(1), child: Text('a')));
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Padding(padding: const EdgeInsets.all(1), child: Box(child: Text('a')));
''');
  }

  Future<void> test_not_without_child() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Box(child: ^Text('a'));
''');
    await assertNoAssist();
  }

  Future<void> test_not_parent_not_a_widget() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

final class Holder {
  const Holder({required this.child});
  final Widget child;
}

final class Any extends Widget {
  const Any({this.child});
  final Object? child;
}

Object f() => Holder(child: ^Any(child: Text('a')));
''');
    await assertNoAssist();
  }

  Future<void> test_not_in_children() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [^Box(child: Text('a'))]);
''');
    await assertNoAssist();
  }
}
