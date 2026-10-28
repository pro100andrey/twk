// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/assists/extract_widget.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ExtractWidgetTest);
  });
}

@reflectiveTest
class ExtractWidgetTest extends TwkAssistTest {
  @override
  AssistKind get kind => ExtractWidget.kind;

  Future<void> test_no_reads() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [^Text('a')]);
''');
    final change = await assertHasAssist('''
import 'package:twk/twk.dart';

Widget f() => Column(children: [NewWidget()]);

class NewWidget extends StatelessWidget {
  const NewWidget({super.key});

  @override
  Widget build(BuildContext context) => Text('a');
}
''');
    expectSnippetShape(change);
    final edited = SourceEdit.applySequence(
      testCode,
      change.edits.single.edits,
    );
    final group = change.linkedEditGroups.single;
    // the call, the class and its constructor
    expect(
      [for (final p in group.positions) p.offset],
      [for (final m in 'NewWidget'.allMatches(edited)) m.start],
    );
    expect(group.length, 'NewWidget'.length);
  }

  Future<void> test_reads() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

final class W extends StatefulWidget {
  const W({required this.title, super.key});
  final String title;
  @override
  State<W> createState() => _S();
}

final class _S extends State<W> {
  static const gap = 1;
  var _count = 0;
  final _text = TextEditingController();

  void _reset() {}

  @override
  Widget build(BuildContext context) {
    final label = '${widget.title}:';
    return Column(
      children: [
        ^Column(
          children: [
            Text('$label $_count $gap'),
            TextField(controller: _text),
            InputListener(onEvent: (_) => false, child: Text('$context')),
          ],
        ),
      ],
    );
  }
}
''');
    final change = await assertHasAssist(r'''
import 'package:twk/twk.dart';

final class W extends StatefulWidget {
  const W({required this.title, super.key});
  final String title;
  @override
  State<W> createState() => _S();
}

final class _S extends State<W> {
  static const gap = 1;
  var _count = 0;
  final _text = TextEditingController();

  void _reset() {}

  @override
  Widget build(BuildContext context) {
    final label = '${widget.title}:';
    return Column(
      children: [
        NewWidget(label: label, count: _count, text: _text),
      ],
    );
  }
}

class NewWidget extends StatelessWidget {
  const NewWidget({
    required this.label,
    required this.count,
    required this.text,
    super.key,
  });

  final String label;
  final int count;
  final TextEditingController text;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$label $count ${_S.gap}'),
      TextField(controller: text),
      InputListener(onEvent: (_) => false, child: Text('$context')),
    ],
  );
}
''');
    expectSnippetShape(change);
    expect(change.linkedEditGroups.single.positions, hasLength(3));
  }

  Future<void> test_tear_off_and_context() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

final class A {
  bool _onEvent(InputEvent e) => false;

  Widget build(BuildContext ctx, Widget child) =>
      ^InputListener(onEvent: _onEvent, child: Text('$ctx'));
}
''');
    await assertHasAssist(r'''
import 'package:twk/twk.dart';

final class A {
  bool _onEvent(InputEvent e) => false;

  Widget build(BuildContext ctx, Widget child) =>
      NewWidget(onEvent: _onEvent);
}

class NewWidget extends StatelessWidget {
  const NewWidget({required this.onEvent, super.key});

  final bool Function(InputEvent e) onEvent;

  @override
  Widget build(BuildContext context) => InputListener(onEvent: onEvent, child: Text('$context'));
}
''');
  }

  Future<void> test_name_taken() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

class NewWidget {}

Widget f() => ^Text('a');
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

class NewWidget {}

Widget f() => NewWidget2();

class NewWidget2 extends StatelessWidget {
  const NewWidget2({super.key});

  @override
  Widget build(BuildContext context) => Text('a');
}
''');
  }

  Future<void> test_names_taken() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

class NewWidget {}

class NewWidget2 {}

Widget f() => ^Text('a');
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

class NewWidget {}

class NewWidget2 {}

Widget f() => NewWidget3();

class NewWidget3 extends StatelessWidget {
  const NewWidget3({super.key});

  @override
  Widget build(BuildContext context) => Text('a');
}
''');
  }

  Future<void> test_calls_method() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

final class A {
  String _label() => 'a';

  Widget build() => ^Text(_label());
}
''');
    await assertNoAssist();
  }

  Future<void> test_assigns() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

Widget f() {
  var taken = false;
  return ^InputListener(onEvent: (_) => taken = true, child: Text('$taken'));
}
''');
    await assertNoAssist();
  }

  Future<void> test_this() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

final class A {
  Widget build() => ^Text('$this');
}
''');
    await assertNoAssist();
  }

  Future<void> test_awaits() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Future<Widget> f(Future<String> label) async => ^Text(await label);
''');
    await assertNoAssist();
  }

  Future<void> test_increments() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

Widget f() {
  var count = 0;
  return ^InputListener(onEvent: (_) => count++ > 0, child: Text('$count'));
}
''');
    await assertNoAssist();
  }

  Future<void> test_type_parameter() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

Widget f<T>(T value) => ^Text('$value');
''');
    await assertNoAssist();
  }

  Future<void> test_identifier() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

Widget f(Widget child) => Column(children: [^child]);
''');
    await assertNoAssist();
  }
}
