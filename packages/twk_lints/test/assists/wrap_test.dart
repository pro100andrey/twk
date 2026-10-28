// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/assists/wrap.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(WrapInWidgetTest);
    defineReflectiveTests(WrapWithPaddingTest);
    defineReflectiveTests(WrapWithBoxTest);
    defineReflectiveTests(WrapWithCenterTest);
    defineReflectiveTests(WrapWithSizedBoxTest);
  });
}

@reflectiveTest
class WrapInWidgetTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapInWidget.kind;

  Future<void> test_one_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [^Text('a')]);
''');
    final change = await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [widget(child: Text('a'))]);
''');
    expectSnippetShape(change);
    final group = change.linkedEditGroups.single;
    expect(group.positions.single.offset, testCode.indexOf("Text('a')"));
    expect(group.length, 'widget'.length);
  }

  Future<void> test_lines() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    ^Column(
      children: [Text('a')],
    ),
  ],
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    widget(
      child: Column(
        children: [Text('a')],
      ),
    ),
  ],
);
''');
  }

  Future<void> test_variable() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget child) => Column(children: [^child]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(Widget child) => Column(children: [widget(child: child)]);
''');
  }

  Future<void> test_not_a_widget() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Padding(padding: ^EdgeInsets.all(1));
''');
    await assertNoAssist();
  }
}

@reflectiveTest
class WrapWithPaddingTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithPadding.kind;

  Future<void> test_creation() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    Te^xt('a'),
  ],
);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(
  children: [
    Padding(
      padding: const EdgeInsets.all(1),
      child: Text('a'),
    ),
  ],
);
''');
  }

  Future<void> test_prefixed() async {
    await resolveTestCode('''
import 'package:twk/twk.dart' as t;

t.Widget f() => t.^Text('a');
''');
    await assertHasAssist('''
import 'package:twk/twk.dart' as t;

t.Widget f() => t.Padding(
  padding: const t.EdgeInsets.all(1),
  child: t.Text('a'),
);
''');
  }
}

@reflectiveTest
class WrapWithBoxTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithBox.kind;

  Future<void> test_creation() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => ^Text('a');
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Box(
  border: const Border.all(),
  child: Text('a'),
);
''');
  }
}

@reflectiveTest
class WrapWithCenterTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithCenter.kind;

  Future<void> test_one_line() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [^Text('a')]);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [Center(child: Text('a'))]);
''');
  }

  Future<void> test_nullable() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget? w) => Box(child: ^w);
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f(Widget? w) => Box(child: Center(child: w));
''');
  }

  Future<void> test_not_a_widget() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Padding(padding: ^EdgeInsets.all(1));
''');
    await assertNoAssist();
  }
}

@reflectiveTest
class WrapWithSizedBoxTest extends TwkAssistTest {
  @override
  AssistKind get kind => WrapWithSizedBox.kind;

  Future<void> test_creation() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => ^Text('a');
''');
    final change = await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => SizedBox(
  width: 1,
  height: 1,
  child: Text('a'),
);
''');
    expectSnippetShape(change);
    final edited = SourceEdit.applySequence(
      testCode,
      change.edits.single.edits,
    );
    expect(
      [
        for (final group in change.linkedEditGroups)
          (group.positions.single.offset, group.length),
      ],
      [
        (edited.indexOf('1,'), 1),
        (edited.indexOf('1,', edited.indexOf('height')), 1),
      ],
    );
  }

  Future<void> test_prefixed() async {
    await resolveTestCode('''
import 'package:twk/twk.dart' as t;

t.Widget f() => t.^Text('a');
''');
    await assertHasAssist('''
import 'package:twk/twk.dart' as t;

t.Widget f() => t.SizedBox(
  width: 1,
  height: 1,
  child: t.Text('a'),
);
''');
  }
}
