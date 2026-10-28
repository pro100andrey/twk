// Tests written when the tester was TuiTester, started by testTui (before
// 6d4f947).
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  testTui('Enter submits what was typed', (t) async {
    await t.pumpWidget(const Text('ready'));
    await submit(t, 'hello');
    expect(t.lines.first, contains('ready'));
  });

  testTui('a typed tester', (TuiTester t) async {
    await t.pumpWidget(const Text('typed'));
  }, timeout: const Timeout(Duration(seconds: 5)));

  group('in a group', () {
    testTui('still renamed', body);
  });
}

Future<void> submit(TuiTester t, String text) async {
  await t.type(text);
  await t.press('enter');
}

Future<void> body(TuiTester t) => t.pumpWidget(const Text('torn off'));

extension Lines on TuiTester {
  String get top => lines.first;
}

final void Function(String, Future<void> Function(TuiTester)) run = testTui;
