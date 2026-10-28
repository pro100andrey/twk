// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/fixes/add_mounted_check.dart';
import 'package:twk_lints/src/rules/set_state_after_dispose.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SetStateAfterDisposeTest);
  });
}

const _state = r'''
import 'package:twk/twk.dart';

final class W extends StatefulWidget {
  const W({super.key});
  @override
  State<W> createState() => _S();
}

final class _S extends State<W> {
  var n = 0;

  @override
  Widget build(BuildContext context) => Text('$n');

''';

@reflectiveTest
class SetStateAfterDisposeTest extends TwkRuleTest {
  @override
  void setUp() {
    rule = SetStateAfterDispose();
    super.setUp();
  }

  Future<void> test_in_dispose() async {
    const code =
        '''
$_state
  @override
  void dispose() {
    setState(() => n = 0);
    super.dispose();
  }
}
''';
    await assertDiagnostics(code, [
      lintAt(code, 'setState', messageContainsAll: ["in 'dispose'"]),
    ]);
  }

  Future<void> test_after_await() async {
    const code =
        '''
$_state
  Future<void> load() async {
    setState(() => n = 1);
    await Future<void>.value();
    setState(() => n = 2);
  }
}
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        'setState',
        occurrence: 1,
        messageContainsAll: ["follows an 'await'"],
      ),
    ]);
    expect(
      await fixed(AddMountedCheck.new),
      code.replaceFirst(
        '    setState(() => n = 2);',
        '    if (!mounted) return;\n    setState(() => n = 2);',
      ),
    );
  }

  Future<void> test_after_await_checked() async {
    await assertNoDiagnostics('''
$_state
  Future<void> load() async {
    await Future<void>.value();
    if (!mounted) return;
    setState(() => n = 1);
    await Future<void>.value();
    if (mounted) {
      setState(() => n = 2);
    }
    await Future<void>.value();
    if (!context.mounted || n > 2) {
      return;
    }
    setState(() => n = 3);
    await Future<void>.value();
    n > 0 && mounted ? setState(() => n = 4) : null;
  }
}
''');
  }

  Future<void> test_checked_in_the_branch_that_awaited() async {
    await assertNoDiagnostics('''
$_state
  Future<bool?> ask() async => true;

  Future<void> go(bool asking) async {
    if (asking) {
      final ok = await ask();
      if (ok == null || !mounted) {
        return;
      }
    }
    setState(() => n++);
    if (asking) {
      await ask();
      if (!mounted) return;
    } else {
      n++;
    }
    setState(() => n++);
  }
}
''');
  }

  Future<void> test_unchecked_in_one_branch() async {
    const code =
        '''
$_state
  Future<bool?> ask() async => true;

  Future<void> go(bool asking) async {
    if (asking) {
      await ask();
      if (!mounted) return;
    } else {
      await ask();
    }
    setState(() => n++);
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'setState')]);
  }

  Future<void> test_checked_then_awaited_in_a_branch() async {
    const code =
        '''
$_state
  Future<bool?> ask() async => true;

  Future<void> go(bool asking) async {
    await ask();
    if (!mounted) return;
    if (asking) {
      await ask();
    }
    setState(() => n++);
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'setState')]);
  }

  Future<void> test_checked_before_await() async {
    const code =
        '''
$_state
  Future<void> load() async {
    if (!mounted) return;
    await Future<void>.value();
    setState(() => n = 1);
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'setState')]);
  }

  Future<void> test_loop() async {
    const code =
        '''
$_state
  Future<void> load() async {
    while (n < 3) {
      setState(() => n++);
      await Future<void>.value();
    }
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'setState')]);
  }

  Future<void> test_await_for() async {
    const code =
        '''
$_state
  Future<void> listen(Stream<int> s) async {
    await for (final v in s) {
      setState(() => n = v);
    }
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'setState')]);
  }

  Future<void> test_future_callback() async {
    const code =
        '''
$_state
  void load(Future<int> f) {
    f.then((v) => setState(() => n = v));
    Future<void>.delayed(Duration.zero, () {
      if (mounted) setState(() => n = 0);
    });
  }
}
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        'setState',
        messageContainsAll: ['in a callback of a Future'],
      ),
    ]);
  }

  Future<void> test_await_in_nested_function() async {
    await assertNoDiagnostics('''
$_state
  void load() {
    Future<void> later() async => await Future<void>.value();
    setState(() => n = 1);
    later();
  }
}
''');
  }

  Future<void> test_sync() async {
    await assertNoDiagnostics('''
$_state
  void bump() => setState(() => n++);
}
''');
  }
}
