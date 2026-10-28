// Tests whose printed frames recording_test.dart checks from outside: run
// by `dart test` in a process of their own.
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import 'ticker.dart';

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
  Widget build(BuildContext context) => const Text('tick 0');
}

const _ticker = TickingCounter(Duration(milliseconds: 100), to: 5);

void main() {
  testTwk('a test that passes', (t) async {
    await t.pumpWidget(_ticker, size: (10, 2));
    await t.pump(const Duration(milliseconds: 500));
  });

  testTwk('a test that fails', (t) async {
    await t.pumpWidget(_ticker, size: (10, 2));
    await t.pump(const Duration(milliseconds: 500));
    // a frame that leaves the screen as it was
    t.terminal.write(ascii.encode('\x1b[?25l'));
    fail('the test failed');
  });

  testTwk('a test that fails, printing one frame', framesOnFailure: 1, (
    t,
  ) async {
    await t.pumpWidget(_ticker, size: (10, 2));
    await t.pump(const Duration(milliseconds: 500));
    fail('the test failed');
  });

  testTwk('an app that fails as it ends', (t) async {
    await t.pumpWidget(const ThrowsOnDispose(), size: (10, 2));
  });

  testTwk('a test that fails, its app having shown nothing', (t) async {
    await t.pumpWidget(const SizedBox.shrink(), size: (10, 2));
    fail('the test failed');
  });

  testTwk('a test that fails before an app started', (t) {
    fail('the test failed');
  });
}
