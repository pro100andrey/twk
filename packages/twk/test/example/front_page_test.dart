// The fragment the repository's README shows, held to code that runs: its
// first ```dart block is the two regions below, the second without main's
// indent.
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

final _fence = RegExp(r'^```dart\n(.*?)^```$', multiLine: true, dotAll: true);

final _region = RegExp(
  r'^ *// #readme\n(.*?)^ *// #end$',
  multiLine: true,
  dotAll: true,
);

final class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

// #readme
final class _CounterState extends State<Counter> {
  var _n = 0;

  @override
  Widget build(BuildContext context) => KeyBindings({
    'up': () => setState(() => _n++),
  }, child: Text('Count: $_n'));
}
// #end

void main() {
  // #readme
  testTwk('Up counts', (t) async {
    await t.pumpWidget(const Counter(), size: (20, 3));
    await t.press('up up up');
    await t.pump();
    expect(t, containsLine('Count: 3'));
  });
  // #end

  test("the repository's README shows the regions of this file", () {
    final source = File(
      'test/example/front_page_test.dart',
    ).readAsStringSync();
    final [widget, test] = [
      for (final region in _region.allMatches(source)) region[1]!,
    ];
    final shown =
        '$widget\n${test.replaceAll(RegExp('^  ', multiLine: true), '')}';
    final block = _fence.firstMatch(File('../../README.md').readAsStringSync());
    expect(block, isNotNull, reason: 'no ```dart block in the README');
    expect(block![1], shown);
  });
}
