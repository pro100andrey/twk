// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/assists/convert_to_stateful_widget.dart';
import 'package:twk_lints/src/assists/convert_to_stateless_widget.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ConvertToStatelessWidgetTest);
  });
}

@reflectiveTest
class ConvertToStatelessWidgetTest extends TwkAssistTest {
  @override
  AssistKind get kind => ConvertToStatelessWidget.kind;

  Future<void> test_fields_and_methods() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

/// Greets.
final class ^Greeting extends StatefulWidget {
  const Greeting({required this.name, super.key});

  static const greeting = 'Hello';

  final String name;

  @override
  State<Greeting> createState() => _GreetingState();
}

final class _GreetingState extends State<Greeting> {
  String get _text => '${Greeting.greeting}, ${widget.name}';

  @override
  Widget build(BuildContext context) {
    final self = widget;
    return Text('$_text ${widget.name} ${widget.key} $self');
  }

  void _log() => print(widget.name);
}
''');
    await assertHasAssist(r'''
import 'package:twk/twk.dart';

/// Greets.
final class Greeting extends StatelessWidget {
  const Greeting({required this.name, super.key});

  static const greeting = 'Hello';

  final String name;

  String get _text => '$greeting, $name';

  @override
  Widget build(BuildContext context) {
    final self = this;
    return Text('$_text $name $key $self');
  }

  void _log() => print(name);
}
''');
  }

  Future<void> test_build_only_state_first() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

class _HelloState extends State<Hello> {
  @override
  Widget build(BuildContext context) => const Text('hello');
}

class Hello extends ^StatefulWidget {
  const Hello({super.key});

  @override
  State<Hello> createState() {
    return _HelloState();
  }
}
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

class Hello extends StatelessWidget {
  const Hello({super.key});

  @override
  Widget build(BuildContext context) => const Text('hello');
}
''');
  }

  Future<void> test_generic_private() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

class ^_Item<T extends Object> extends StatefulWidget {
  const _Item(this.value);

  final T value;

  @override
  State<_Item<T>> createState() => _ItemState<T>();
}

class _ItemState<T extends Object> extends State<_Item<T>> {
  @override
  Widget build(BuildContext context) => Text('${widget.value}');
}

Widget f() => _Item(1);
''');
    await assertHasAssist(r'''
import 'package:twk/twk.dart';

class _Item<T extends Object> extends StatelessWidget {
  const _Item(this.value);

  final T value;

  @override
  Widget build(BuildContext context) => Text('$value');
}

Widget f() => _Item(1);
''');
  }

  Future<void> test_shadowed_called_and_fields() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart' as t;

class ^Label extends t.StatefulWidget {
  Label(this.name);

  final String name;

  String describe() => name;

  static String shout(String s) => s;

  @override
  t.State<Label> createState() => _LabelState();
}

class _LabelState extends t.State<Label> {
  // the parts
  final parts = <String>[];

  static const sep = ', ';

  @override
  t.Widget build(t.BuildContext context) {
    final name = widget.name;
    final all = [name, widget.describe(), Label.shout(sep), ...parts];
    return t.Text('${widget.name}s ${widget.name}_ ${all.length} ${widget.name}!');
  }

  t.Widget get self => widget;

  String get d => widget
      .describe();
}
''');
    await assertHasAssist(r'''
import 'package:twk/twk.dart' as t;

class Label extends t.StatelessWidget {
  Label(this.name);

  final String name;

  String describe() => name;

  static String shout(String s) => s;

  // the parts
  final parts = <String>[];

  static const sep = ', ';

  @override
  t.Widget build(t.BuildContext context) {
    final name = this.name;
    final all = [name, describe(), shout(sep), ...parts];
    return t.Text('${this.name}s ${this.name}_ ${all.length} ${this.name}!');
  }

  t.Widget get self => this;

  String get d => describe();
}
''');
  }

  Future<void> test_braces_kept_before_a_name() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

class ^W extends StatefulWidget {
  const W(this.n);

  final int n;

  @override
  State<W> createState() => _WState();
}

class _WState extends State<W> {
  @override
  Widget build(BuildContext context) => Text('${widget.n}x ${widget.n}. ${widget.n}');
}
''');
    await assertHasAssist(r'''
import 'package:twk/twk.dart';

class W extends StatelessWidget {
  const W(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Text('${n}x $n. $n');
}
''');
  }

  Future<void> test_in_body() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

class W extends StatefulWidget {
  const W({super.key});

  @override
  State<W> createState() => _WState();
}

class _WState extends State<W> {
  @override
  Widget build(BuildContext context) => const ^Text('hello');
}
''');
    await assertNoAssist();
  }

  Future<void> test_at_the_state() async {
    await _assertNoAssistWith(state: '^class _WState extends State<W> {');
  }

  Future<void> test_not_twk_stateful() async {
    await _assertNoAssistWith(
      prelude:
          'abstract class Base extends StatefulWidget {\n'
          '  const Base({super.key});\n'
          '}',
      widget: 'Base',
    );
  }

  Future<void> test_stateless() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

class ^W extends StatelessWidget {
  const W({super.key});

  @override
  Widget build(BuildContext context) => const Text('hello');
}
''');
    await assertNoAssist();
  }

  Future<void> test_lifecycle() async {
    await _assertNoAssistWith(
      members: '''
  @override
  void initState() {}''',
    );
    await _assertNoAssistWith(
      members: '''
  @override
  void dispose() {}''',
    );
  }

  Future<void> test_set_state_mounted_context() async {
    await _assertNoAssistWith(members: '  void f() => setState(() {});');
    await _assertNoAssistWith(members: '  bool get f => mounted;');
    await _assertNoAssistWith(members: '  BuildContext get f => context;');
    await _assertNoAssistWith(members: '  bool get f => this.mounted;');
  }

  Future<void> test_super_and_this() async {
    await _assertNoAssistWith(members: '  Object get f => this;');
    await _assertNoAssistWith(members: '  int get f => super.hashCode;');
  }

  Future<void> test_state_shape() async {
    await _assertNoAssistWith(
      prelude: '''
abstract class Base<T extends StatefulWidget> extends State<T> {}''',
      state: 'class _WState extends Base<W> {',
    );
    await _assertNoAssistWith(
      state: 'class _WState<T> extends State<W> {',
    );
    await _assertNoAssistWith(
      prelude: 'mixin M {}',
      state: 'class _WState extends State<W> with M {',
    );
    await _assertNoAssistWith(
      prelude: 'abstract interface class I {}',
      state: 'class _WState extends State<W> implements I {',
    );
  }

  Future<void> test_fields_and_constructors() async {
    await _assertNoAssistWith(members: '  var count = 0;', constWidget: false);
    await _assertNoAssistWith(
      members: '  late final count = 0;',
      constWidget: false,
    );
    await _assertNoAssistWith(members: '  final count = 0;');
    await _assertNoAssistWith(members: '  _WState();', constWidget: false);
  }

  Future<void> test_state_public_or_named_elsewhere() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

class ^W extends StatefulWidget {
  const W({super.key});

  @override
  State<W> createState() => WState();
}

class WState extends State<W> {
  @override
  Widget build(BuildContext context) => const Text('hello');
}
''');
    await assertNoAssist();
    await _assertNoAssistWith(prelude: '_WState? current;');
    await _assertNoAssistWith(members: '  static const a = 1, b = _WState.a;');
  }

  Future<void> test_create_state_not_plain() async {
    await _assertNoAssistWith(createState: 'throw 0');
    await _assertNoAssistWith(
      createState: '_WState.named()',
      members: '  _WState.named();',
      constWidget: false,
    );
    await _assertNoAssistWith(
      createState: '_WState(1)',
      members: '  _WState(int x);',
      constWidget: false,
    );
  }

  Future<void> test_names_collide() async {
    // a member of the state named as one of the widget, or of Widget
    await _assertNoAssistWith(members: '  int get label => 0;');
    await _assertNoAssistWith(members: '  int get key => 0;');
    // a top-level name the widget's field would hide
    await _assertNoAssistWith(
      prelude: "const label = 'top';",
      members: '  String get f => label;',
    );
    // a top-level name the widget reads that a member moved in would hide
    await _assertNoAssistWith(
      prelude: 'int helper() => 0;',
      widgetMembers: '  int get g => helper();',
      members: '  int helper() => 1;',
    );
  }

  /// Convert to StatefulWidget, then Convert to StatelessWidget, gives back
  /// what there was.
  Future<void> test_round_trip() async {
    for (final original in [
      r'''
import 'package:twk/twk.dart';

/// Greets.
final class Greeting extends StatelessWidget {
  const Greeting({required this.name, super.key});

  static const greeting = 'Hello';

  final String name;

  String get _text => '$greeting, $name';

  @override
  Widget build(BuildContext context) {
    final self = this;
    return Text('$_text ${name}s $key $self ${describe()}');
  }

  /// What it says.
  String describe() => name;
}

Widget f() => const Greeting(name: 'you');
''',
      r'''
import 'package:twk/twk.dart' as t;

class _Item<T extends Object> extends t.StatelessWidget {
  const _Item(this.value);

  final T value;

  @override
  t.Widget build(t.BuildContext context) {
    final value = this.value;
    return t.Text('$value');
  }
}

t.Widget f() => _Item(1);
''',
    ]) {
      final head = original.indexOf(' extends ');
      final stateful = await _applied(
        ConvertToStatefulWidget.new,
        original.replaceRange(head, head, '^'),
      );
      expect(stateful, contains('createState()'));
      final stateless = await _applied(
        ConvertToStatelessWidget.new,
        stateful!.replaceRange(head, head, '^'),
      );
      expect(stateless, original);
    }
  }

  /// [code], resolved, as [make]'s assist at its `^` edits it; null where
  /// it does not.
  Future<String?> _applied(
    CorrectionProducer Function({required CorrectionProducerContext context})
    make,
    String code,
  ) async {
    final at = code.indexOf('^');
    final source = code.replaceRange(at, at + 1, '');
    newFile(testFile.path, source);
    await resolveTestFile();
    final producer = make(
      context: CorrectionProducerContext.createResolved(
        libraryResult: testLibraryResult!,
        unitResult: testAnalysisResult,
        selectionOffset: at,
      ),
    );
    final builder = ChangeBuilder(session: testAnalysisResult.session);
    await producer.compute(builder);
    final edits = builder.sourceChange.edits;
    return edits.isEmpty
        ? null
        : SourceEdit.applySequence(source, edits.single.edits);
  }

  /// That the assist is not offered at the head of a widget `W` whose
  /// state has [members] after its `build`, [state] as its head, with
  /// [prelude] before the widget, [widgetMembers] in it and [createState]
  /// what its `createState` returns. The fixture is to have no
  /// diagnostic, so that what refuses the assist is the assist.
  Future<void> _assertNoAssistWith({
    String prelude = '',
    String state = 'class _WState extends State<W> {',
    String members = '',
    String widgetMembers = '',
    String createState = '_WState()',
    String widget = 'StatefulWidget',
    bool constWidget = true,
  }) async {
    final code =
        '''
import 'package:twk/twk.dart';

$prelude

class ${state.startsWith('^') ? '' : '^'}W extends $widget {
  ${constWidget ? 'const ' : ''}W({this.label = '', super.key});

  final String label;
$widgetMembers

  @override
  State<W> createState() => $createState;
}

$state
  @override
  Widget build(BuildContext context) => Text(widget.label);

$members
}
''';
    expect(await _applied(ConvertToStatelessWidget.new, code), isNull);
  }
}
