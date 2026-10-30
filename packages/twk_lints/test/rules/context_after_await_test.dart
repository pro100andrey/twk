// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/fixes/add_mounted_check.dart';
import 'package:twk_lints/src/rules/context_after_await.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ContextAfterAwaitTest);
  });
}

const _state = r'''
import 'package:twk/twk.dart';

void use(BuildContext context) {}

Future<bool?> ask(BuildContext context) async => true;

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
class ContextAfterAwaitTest extends TwkRuleTest {
  @override
  void setUp() {
    rule = ContextAfterAwait();
    super.setUp();
  }

  Future<void> test_state_context_after_await() async {
    const code =
        '''
$_state
  Future<void> save() async {
    use(context);
    await Future<void>.value();
    use(context);
  }
}
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        'context',
        occurrence: 4,
        messageContainsAll: [
          "'context' may be used after its widget left the tree",
          "follows an 'await'",
          "no check of 'mounted'",
        ],
      ),
    ]);
    expect(
      await fixed(AddMountedCheck.new),
      code.replaceFirst(
        '''
    await Future<void>.value();
    use(context);''',
        '''
    await Future<void>.value();
    if (!mounted) return;
    use(context);''',
      ),
    );
  }

  Future<void> test_parameter_after_await() async {
    const code =
        '''
$_state
}

Future<void> go(BuildContext ctx) async {
  await Future<void>.value();
  use(ctx);
}
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        'ctx',
        occurrence: 1,
        messageContainsAll: ["no check of 'ctx.mounted'"],
      ),
    ]);
    expect(
      await fixed(AddMountedCheck.new),
      code.replaceFirst(
        '  use(ctx);',
        '  if (!ctx.mounted) return;\n  use(ctx);',
      ),
    );
  }

  Future<void> test_checked() async {
    await assertNoDiagnostics('''
$_state
  Future<void> save(BuildContext other) async {
    await Future<void>.value();
    if (!mounted) return;
    use(context);
    await Future<void>.value();
    if (mounted) {
      use(context);
    }
    await Future<void>.value();
    if (!other.mounted || n > 2) {
      return;
    }
    use(other);
    await Future<void>.value();
    n > 0 && context.mounted ? use(context) : null;
  }
}
''');
  }

  Future<void> test_a_flag_of_its_own_named_mounted_checks_nothing() async {
    const code =
        '''
$_state
  final _other = _Flag();

  Future<void> save() async {
    var mounted = n > 1;
    await Future<void>.value();
    if (!mounted) return;
    use(context);
    await Future<void>.value();
    if (!_other.mounted) return;
    use(context);
    mounted = false;
  }
}

final class _Flag {
  bool mounted = false;
}
''';
    await assertDiagnostics(code, [
      lintAt(code, 'context', occurrence: 3),
      lintAt(code, 'context', occurrence: 4),
    ]);
  }

  Future<void> test_argument_of_the_awaited_call() async {
    await assertNoDiagnostics('''
$_state
  Future<void> save() async {
    await ask(context);
  }

  Future<void> load() async {
    final ok = await ask(context) ?? false;
    n = ok ? 1 : 0;
  }
}
''');
  }

  Future<void> test_checked_in_the_branch_that_awaited() async {
    await assertNoDiagnostics('''
$_state
  Future<void> save(bool asking) async {
    if (asking) {
      final ok = await ask(context);
      if (ok == null || !mounted) return;
    }
    use(context);
  }
}
''');
  }

  Future<void> test_unchecked_in_one_branch() async {
    const code =
        '''
$_state
  Future<void> save(bool asking) async {
    if (asking) {
      await ask(context);
      if (!mounted) return;
    } else {
      await Future<void>.value();
    }
    use(context);
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'context', occurrence: 4)]);
  }

  Future<void> test_variable_assigned_after_the_await() async {
    const code =
        '''
$_state
  Future<void> visit(List<BuildContext> Function() found) async {
    await Future<void>.value();
    for (final c in found()) {
      use(c);
    }
    BuildContext later = found().first;
    await Future<void>.value();
    use(later);
    later = found().last;
    use(later);
  }
}
''';
    await assertDiagnostics(code, [
      lintAt(code, 'later', occurrence: 1),
    ]);
  }

  Future<void> test_variable_a_function_assigns() async {
    await assertNoDiagnostics('''
$_state
  Future<void> keep(void Function(void Function(BuildContext)) run) async {
    late BuildContext kept;
    run((c) => kept = c);
    await Future<void>.value();
    use(kept);
  }
}
''');
  }

  Future<void> test_future_callback() async {
    const code =
        '''
$_state
  void save(Future<int> f) {
    f.then((_) => use(context));
    f.then((_) {
      if (!mounted) return;
      use(context);
    });
  }
}
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        'context',
        occurrence: 3,
        messageContainsAll: ['in a callback of a Future'],
      ),
    ]);
    // an arrow function has no statement to put the check before
    expect(await fixed(AddMountedCheck.new), isNull);
  }

  Future<void> test_loop() async {
    const code =
        '''
$_state
  Future<void> poll() async {
    while (n < 3) {
      use(context);
      await Future<void>.value();
    }
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'context', occurrence: 3)]);
  }

  Future<void> test_catch_after_await_in_try() async {
    const code =
        '''
$_state
  Future<int> save() async {
    try {
      await Future<void>.value();
      if (!mounted) return 0;
      use(context);
    } on Exception {
      use(context);
    }
    return 1;
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'context', occurrence: 4)]);
    // `return;` does not compile where the function returns a value
    expect(await fixed(AddMountedCheck.new), isNull);
  }

  Future<void> test_switch() async {
    const code =
        '''
$_state
  Future<void> each(int k) async {
    await Future<void>.value();
    switch (k) {
      case 0:
        if (!mounted) return;
      default:
        if (!mounted) return;
    }
    use(context);
  }

  Future<void> some(int k) async {
    await Future<void>.value();
    switch (k) {
      case 0:
      case 1:
        if (!mounted) return;
    }
    use(context);
  }

  Future<void> empty(int k) async {
    await Future<void>.value();
    switch (k) {
      case 0:
        if (!mounted) return;
      default:
    }
    use(context);
  }
}
''';
    await assertDiagnostics(code, [
      lintAt(code, 'context', occurrence: 4),
      lintAt(code, 'context', occurrence: 5),
    ]);
  }

  Future<void> test_in_tests_only_classes() async {
    const code =
        '''
$_state
  Future<void> save() async {
    await Future<void>.value();
    use(context);
  }
}

Future<void> drive(BuildContext context) async {
  await Future<void>.value();
  use(context);
}
''';
    final path = '$testPackageRootPath/test/a_test.dart';
    newFile(path, code);
    await assertDiagnosticsInFile(path, [
      lintAt(code, 'context', occurrence: 3),
    ]);
  }

  Future<void> test_break_out_of_a_switch() async {
    const code =
        '''
$_state
  Future<void> save(int k) async {
    switch (k) {
      case 1:
        await Future<void>.value();
        break;
      default:
        break;
    }
    use(context);
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'context', occurrence: 3)]);
  }

  Future<void> test_break_out_of_a_loop() async {
    const code =
        '''
$_state
  Future<void> save(bool c) async {
    while (true) {
      if (c) {
        await Future<void>.value();
        break;
      }
    }
    use(context);
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'context', occurrence: 3)]);
  }

  Future<void> test_continue_to_the_next_round() async {
    const code =
        '''
$_state
  Future<void> save(List<int> xs) async {
    for (final x in xs) {
      use(context);
      if (x > 1) {
        await Future<void>.value();
        continue;
      }
    }
  }
}
''';
    await assertDiagnostics(code, [lintAt(code, 'context', occurrence: 3)]);
  }

  Future<void> test_break_where_not_mounted() async {
    await assertNoDiagnostics('''
$_state
  Future<void> save() async {
    for (;;) {
      await Future<void>.value();
      if (!mounted) break;
      use(context);
    }
  }
}
''');
  }

  Future<void> test_sync_and_nested_functions() async {
    await assertNoDiagnostics('''
$_state
  void save() {
    Future<void> later() async => await Future<void>.value();
    use(context);
    later();
  }
}
''');
  }
}
