// Tests whose end teardown_test.dart checks from outside: run by
// `dart test` in a process of their own.
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// Throws when its state is disposed.
final class ThrowsOnDispose extends StatefulWidget {
  const ThrowsOnDispose({super.key});

  @override
  State<ThrowsOnDispose> createState() => _ThrowsOnDisposeState();
}

final class _ThrowsOnDisposeState extends State<ThrowsOnDispose> {
  @override
  void dispose() {
    super.dispose();
    throw StateError('dispose failed');
  }

  @override
  Widget build(BuildContext context) => const Text('x');
}

/// Bytes the emulator does not take.
final _junk = Uint8List.fromList(ascii.encode('\x1b[?999h'));

void main() {
  // the app of the test that ran last, when it kept it here
  TwkTester? tester;
  setUp(() => tester = null);
  tearDown(() => expect(tester?.isRunning, isNot(isTrue)));

  testTwk('an app left running', (t) async {
    tester = t;
    await t.pumpWidget(const Text('x'));
  });

  testTwk('a test that fails, its app left running', (t) async {
    tester = t;
    await t.pumpWidget(const Text('x'));
    fail('the test failed');
  });

  testTwk('an app that fails as it ends', (t) async {
    await t.pumpWidget(const ThrowsOnDispose());
  });

  testTwk('bytes the emulator does not take', (t) async {
    await t.pumpWidget(const Text('x'));
    t.terminal.write(_junk);
  });

  testTwk('a test that fails, and bytes the emulator does not take', (
    t,
  ) async {
    await t.pumpWidget(const Text('x'));
    t.terminal.write(_junk);
    fail('the test failed');
  });
}
