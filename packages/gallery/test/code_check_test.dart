// tool/code_check/wrap.dart: how each kind of Code is made into a library
// whose codeWidget() returns its widget.
import 'package:test/test.dart';

import '../tool/code_check/wrap.dart';

void main() {
  test('a program runs its main with runApp keeping the widget', () {
    final w = wrap('''
import 'package:twk/twk.dart';

void main() => runApp(const Text('hi'), maxFps: 30);
''');
    expect(w.mode, WrapMode.file);
    expect(w.dart, contains('void _codeMain() => _codeRunApp('));
    expect(w.dart, contains('Widget codeWidget() {'));
    expect(
      RegExp("import 'package:twk/twk.dart';").allMatches(w.dart),
      hasLength(1),
    );
  });

  test('a State whose widget the Code leaves out gets the widget', () {
    final w = wrap(r'''
class _CounterState extends State<Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => Text('$_n');
}
''');
    expect(w.mode, WrapMode.stateGiven);
    expect(w.dart, contains('Widget codeWidget() => const Counter();'));
    expect(w.dart, contains('final class Counter extends StatefulWidget {'));
    expect(
      w.dart,
      contains('State<Counter> createState() => _CounterState();'),
    );
  });

  test('build() and other members go in a State, the classes beside it', () {
    final w = wrap('''
var _saved = 0;

@override
Widget build(BuildContext context) => Button(
  label: 'Save',
  onPressed: () => setState(() => _saved++),
);

final class Note extends StatelessWidget {
  const Note({super.key});

  @override
  Widget build(BuildContext context) => const Text('note');
}
''');
    expect(w.mode, WrapMode.members);
    expect(w.dart, contains('  var _saved = 0;'));
    expect(w.dart, contains('  Widget build(BuildContext context) => Button('));
    // the class stays at the top level, after the State
    expect(
      w.dart.indexOf('final class Note'),
      greaterThan(w.dart.indexOf('final class _S extends State<_W>')),
    );
    expect(w.dart, contains('\nfinal class Note'));
  });

  test("a build()'s body goes in one", () {
    final w = wrap('''
final theme = Theme.of(context);
return Text('hi', style: theme.muted);
''');
    expect(w.mode, WrapMode.body);
    expect(
      w.dart,
      contains(
        '  Widget build(BuildContext context) {\n'
        '    final theme = Theme.of(context);\n'
        "    return Text('hi', style: theme.muted);\n"
        '  }',
      ),
    );
  });

  test('a bracket in a string or a comment does not end an item', () {
    final w = wrap(r'''
const open = '{ (';
const raw = r'\(';
// not code: {
final class A {
  final s = """
}""";
}
''');
    expect(w.mode, WrapMode.body);
    expect(w.dart, contains("\nconst open = '{ (';"));
    expect(w.dart, contains(r"const raw = r'\(';"));
    expect(w.dart, contains('\n// not code: {\nfinal class A {'));
  });

  test('the packages a Code names are imported', () {
    final w = wrap("return const MarkdownView('# hi');");
    expect(w.dart, contains("import 'package:twk_rich/twk_rich.dart';"));
    expect(w.dart, isNot(contains('twk_term')));
    expect(
      wrap('return TerminalView(session: s);').dart,
      contains("import 'package:twk_term/twk_term.dart';"),
    );
  });
}
