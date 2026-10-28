// test_reflective_loader runs the methods named test_*
// ignore_for_file: non_constant_identifier_names

import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';
import 'package:twk_lints/src/fixes/elapse_fake_clock.dart';
import 'package:twk_lints/src/rules/wall_time_in_tests.dart';

import '../support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(WallTimeInTestsTest);
  });
}

/// The parts of twk_test the fixtures use.
const _twkTestStub = '''
import 'dart:async';

final class FakeClock {
  T run<T>(T Function() body) => body();
  Future<void> elapse(Duration by) async {}
}

final class TwkTester {
  FakeClock get clock => FakeClock();
  Future<void> act(void Function() fn) async {}
  Future<void> pump([Duration? by]) async {}
}

void testTwk(String description, Future<void> Function(TwkTester t) body) {}

Future<void> waitUntil(FutureOr<bool> Function() condition, String what) async {}
''';

@reflectiveTest
class WallTimeInTestsTest extends TwkRuleTest {
  @override
  String get testFilePath => '$testPackageTestPath/a_test.dart';

  @override
  void setUp() {
    rule = WallTimeInTests();
    newPackage('twk_test').addFile('lib/twk_test.dart', _twkTestStub);
    super.setUp();
    // what the analyzer's SDK of the tests lacks, as the SDK has it
    _sdk(
      'core/core.dart',
      '      int microseconds = 0});',
      '      int microseconds = 0}) : inMicroseconds = microseconds + '
          '1000 * (milliseconds + 1000 * (seconds + 60 * (minutes + '
          '60 * (hours + 24 * days))));\n'
          '  final int inMicroseconds;',
    );
    _sdk(
      'async/async.dart',
      '  static void run(void Function() callback) {}',
      '  static void run(void Function() callback) {}\n'
          '  factory Timer.periodic(Duration duration, '
          'void Function(Timer timer) callback) => throw 0;\n'
          '  void cancel();',
    );
    _sdk(
      'async/stream.dart',
      '  factory Stream.value(T value) => throw 0;',
      '  factory Stream.value(T value) => throw 0;\n'
          '  factory Stream.periodic(Duration period, '
          '[T Function(int count)? computation]) => throw 0;',
    );
    _sdk(
      'io/io.dart',
      'Never exit(int code) => throw code;',
      'Never exit(int code) => throw code;\n'
          'void sleep(Duration duration) {}',
    );
  }

  /// Replaces [from] with [to] in the SDK's [path], which has it.
  void _sdk(String path, String from, String to) {
    final file = getFile('${sdkRoot.path}/lib/$path');
    final content = file.readAsStringSync();
    if (!content.contains(from)) {
      throw StateError('no "$from" in the SDK\'s $path');
    }
    file.writeAsStringSync(content.replaceFirst(from, to));
  }

  Future<void> test_waits() async {
    const code = '''
import 'dart:async';
import 'dart:io';

Future<void> settle([int ms = 30]) async {
  await Future<void>.delayed(const Duration(milliseconds: 30));
  await Future.delayed(Duration(milliseconds: ms));
  sleep(const Duration(milliseconds: 5));
  Timer(const Duration(seconds: 1), () {});
  Timer.periodic(Duration.zero, (_) {}).cancel();
  await Stream<int>.periodic(const Duration(seconds: 1)).first;
}
''';
    await assertDiagnostics(code, [
      lintAt(
        code,
        'Future<void>.delayed',
        messageContainsAll: ["'Future.delayed' waits on the wall clock"],
      ),
      lintAt(code, 'Future.delayed'),
      lintAt(code, 'sleep', messageContainsAll: ["'sleep'"]),
      lintAt(code, 'Timer', messageContainsAll: ["'Timer'"]),
      lintAt(
        code,
        'Timer.periodic',
        messageContainsAll: ["'Timer.periodic'"],
      ),
      lintAt(
        code,
        'Stream<int>.periodic',
        messageContainsAll: ["'Stream.periodic'"],
      ),
    ]);
  }

  Future<void> test_zero() async {
    await assertNoDiagnostics('''
import 'dart:async';
import 'dart:io';

Future<void> yieldOnce() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration());
  await Future<void>.delayed(const Duration(milliseconds: 0));
  Timer(Duration.zero, () {});
  Timer.run(() {});
  sleep(Duration.zero);
}
''');
  }

  Future<void> test_in_a_test_body() async {
    const code = '''
import 'dart:async';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('a frame', (t) async {
    await t.pump();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
}
''';
    await assertDiagnostics(code, [lintAt(code, 'Future<void>.delayed')]);
  }

  Future<void> test_on_a_fake_clock() async {
    await assertNoDiagnostics('''
import 'dart:async';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('timers of the clock', (t) async {
    final clock = FakeClock();
    clock.run(() => Timer(const Duration(seconds: 1), () {}));
    await t.clock.run(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    clock.run(() => Future(() => Timer.periodic(
      const Duration(seconds: 1),
      (_) {},
    )));
    await t.act(() => Timer(const Duration(seconds: 1), () {}));
  });
}
''');
  }

  Future<void> test_a_run_not_of_the_clock() async {
    const code = '''
import 'dart:async';

final class Clock {
  T run<T>(T Function() body) => body();
}

void f(Clock clock) {
  clock.run(() => Timer(const Duration(seconds: 1), () {}));
}
''';
    await assertDiagnostics(code, [lintAt(code, 'Timer')]);
  }

  Future<void> test_app_code() async {
    await assertNoDiagnostics('''
import 'dart:async';
import 'package:twk/twk.dart';

final class Ticking extends StatefulWidget {
  const Ticking({super.key, this.onTick});
  final Future<void> Function()? onTick;
  @override
  State<Ticking> createState() => _TickingState();
}

final class _TickingState extends State<Ticking> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('');
}

Widget ticking() => Ticking(
  onTick: () => Future<void>.delayed(const Duration(seconds: 1)),
);

Widget made({required Future<void> Function() onTick}) =>
    Ticking(onTick: onTick);

Widget madeTicking() =>
    made(onTick: () => Future<void>.delayed(const Duration(seconds: 1)));

Widget column(void Function() onTick) => Column(
  children: [Ticking(onTick: () async => Timer(const Duration(seconds: 1), onTick))],
);
''');
  }

  Future<void> test_sleep_in_app_code() async {
    const code = '''
import 'dart:io';
import 'package:twk/twk.dart';

final class Slow extends StatefulWidget {
  const Slow({super.key});
  @override
  State<Slow> createState() => _SlowState();
}

final class _SlowState extends State<Slow> {
  @override
  void initState() {
    super.initState();
    sleep(const Duration(milliseconds: 50));
  }

  @override
  Widget build(BuildContext context) => Text('');
}
''';
    await assertDiagnostics(code, [lintAt(code, 'sleep')]);
  }

  Future<void> test_a_program_the_tests_start() async {
    newFile('$testPackageTestPath/fixture.dart', '''
import 'dart:async';

Future<void> main() async {
  await Future<void>.delayed(const Duration(seconds: 5));
}
''');
    await assertNoDiagnosticsInFile('$testPackageTestPath/fixture.dart');
  }

  Future<void> test_a_helper_of_the_tests() async {
    const code = '''
import 'dart:async';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
''';
    newFile('$testPackageTestPath/harness.dart', code);
    await assertDiagnosticsInFile('$testPackageTestPath/harness.dart', [
      lintAt(code, 'Future<void>.delayed'),
    ]);
  }

  Future<void> test_outside_test() async {
    newFile('$testPackageLibPath/wait.dart', '''
import 'dart:async';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
''');
    await assertNoDiagnosticsInFile('$testPackageLibPath/wait.dart');
  }

  Future<void> test_others_of_the_name() async {
    await assertNoDiagnostics('''
final class Future {
  Future.delayed(Duration d);
}

void sleep(Duration d) {}

void f() {
  Future.delayed(const Duration(seconds: 1));
  sleep(const Duration(seconds: 1));
}
''');
  }

  Future<void> test_fix_elapses_the_clock_in_scope() async {
    const code = '''
import 'dart:async';
import 'package:twk_test/twk_test.dart';

void main() {
  final clock = FakeClock();
  testTwk('a timer', (t) async {
    clock.run(() => Timer(const Duration(seconds: 1), () {}));
    await Future<void>.delayed(const Duration(seconds: 1));
  });
}

Future<void> settle(FakeClock fake) async {
  await Future.delayed(Duration(milliseconds: 30));
}
''';
    await assertDiagnostics(code, [
      lintAt(code, 'Future<void>.delayed'),
      lintAt(code, 'Future.delayed'),
    ]);
    expect(
      await fixed(ElapseFakeClock.new),
      code.replaceFirst(
        'await Future<void>.delayed(const Duration(seconds: 1));',
        'await clock.elapse(const Duration(seconds: 1));',
      ),
    );
    expect(
      await fixed(ElapseFakeClock.new, index: 1),
      code.replaceFirst(
        'await Future.delayed(Duration(milliseconds: 30));',
        'await fake.elapse(Duration(milliseconds: 30));',
      ),
    );
  }

  Future<void> test_no_fix_without_one_clock_or_an_await() async {
    const code = '''
import 'dart:async';
import 'dart:io';
import 'package:twk_test/twk_test.dart';

void main() {
  testTwk('the tester alone', (t) async {
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  final a = FakeClock();
  final b = FakeClock();
  testTwk('two clocks', (t) async {
    a.run(() {});
    b.run(() {});
    await Future<void>.delayed(const Duration(seconds: 1));
    unawaited(Future<void>.delayed(const Duration(seconds: 1)));
    await Future<int>.delayed(const Duration(seconds: 1), () => 1);
    sleep(const Duration(seconds: 1));
  });
}

void later() {
  testTwk('a clock made after', (t) async {
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  final clock = FakeClock();
  clock.run(() {});
}

Future<void> f(FakeClock clock) async {
  unawaited(Future<void>.delayed(const Duration(seconds: 1)));
  await Future<int>.delayed(const Duration(seconds: 1), () => 1);
  sleep(const Duration(seconds: 1));
}
''';
    await assertDiagnostics(code, [
      lintAt(code, 'Future<void>.delayed'),
      lintAt(code, 'Future<void>.delayed', occurrence: 1),
      lintAt(code, 'Future<void>.delayed', occurrence: 2),
      lintAt(code, 'Future<int>.delayed'),
      lintAt(code, 'sleep'),
      lintAt(code, 'Future<void>.delayed', occurrence: 3),
      lintAt(code, 'Future<void>.delayed', occurrence: 4),
      lintAt(code, 'Future<int>.delayed', occurrence: 1),
      lintAt(code, 'sleep', occurrence: 1),
    ]);
    for (var i = 0; i < 9; i++) {
      expect(await fixed(ElapseFakeClock.new, index: i), isNull, reason: '$i');
    }
  }
}
