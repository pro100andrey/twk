// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/assists/convert_to_stateful_widget.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ConvertToStatefulWidgetTest);
  });
}

@reflectiveTest
class ConvertToStatefulWidgetTest extends TwkAssistTest {
  @override
  AssistKind get kind => ConvertToStatefulWidget.kind;

  Future<void> test_fields_and_methods() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

/// Greets.
final class ^Greeting extends StatelessWidget {
  const Greeting({required this.name, super.key});

  static const greeting = 'Hello';

  final String name;

  String get _text => '$greeting, $name';

  @override
  Widget build(BuildContext context) {
    final self = this;
    return Text('$_text ${this.name} $key $self');
  }

  void _log() => print(name);
}
''');
    await assertHasAssist(r'''
import 'package:twk/twk.dart';

/// Greets.
final class Greeting extends StatefulWidget {
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
  }

  Future<void> test_build_only() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

class Hello extends ^StatelessWidget {
  const Hello({super.key});

  @override
  Widget build(BuildContext context) => const Text('hello');
}
''');
    await assertHasAssist('''
import 'package:twk/twk.dart';

class Hello extends StatefulWidget {
  const Hello({super.key});

  @override
  State<Hello> createState() => _HelloState();
}

class _HelloState extends State<Hello> {
  @override
  Widget build(BuildContext context) => const Text('hello');
}
''');
  }

  Future<void> test_generic_private() async {
    await resolveTestCode(r'''
import 'package:twk/twk.dart';

class ^_Item<T extends Object> extends StatelessWidget {
  const _Item(this.value);

  final T value;

  @override
  Widget build(BuildContext context) => Text('$value');
}

Widget f() => _Item(1);
''');
    await assertHasAssist(r'''
import 'package:twk/twk.dart';

class _Item<T extends Object> extends StatefulWidget {
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
  }

  Future<void> test_in_body() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

class Hello extends StatelessWidget {
  const Hello({super.key});

  @override
  Widget build(BuildContext context) => const ^Text('hello');
}
''');
    await assertNoAssist();
  }

  Future<void> test_stateful() async {
    await resolveTestCode('''
import 'package:twk/twk.dart';

class ^W extends StatefulWidget {
  const W({super.key});

  @override
  State<W> createState() => throw 0;
}
''');
    await assertNoAssist();
  }
}
