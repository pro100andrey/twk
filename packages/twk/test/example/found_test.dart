// The apps behind the guides' paragraphs on constraints, swapping the
// root, the focus, nested taps and keys read together (doc/guides/).
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../../example/guides/batch.dart' show Counter;
import '../../example/guides/constraints.dart' show Constraints;
import '../../example/guides/root.dart' show Welcome;
import '../../example/guides/who.dart' show Who;

void main() {
  testTwk('ConstrainedBox: at most 30 wide in a room of 50', (t) async {
    await t.pumpWidget(const Constraints(), size: (50, 8));
    const screen = '''
room: 50 x 8
╭──────────────────────────╮
│A message that wraps at   │
│thirty cells, however wide│
│the terminal is.          │
╰──────────────────────────╯
''';
    expect(t.lines.take(6).join('\n'), screen.trimRight());
    expect(
      File('../../doc/guides/layout.md').readAsStringSync(),
      contains('```text\n$screen```'),
    );
    expect(t.rect(find.byType(ConstrainedBox)).width, inInclusiveRange(21, 30));
  });

  testTwk('ConstrainedBox: in a room of 20, the room is the limit too', (
    t,
  ) async {
    await t.pumpWidget(const Constraints(), size: (20, 8));
    expect(t.rect(find.byType(ConstrainedBox)).width, lessThanOrEqualTo(20));
  });

  testTwk('attachRootWidget: Enter replaces the app', (t) async {
    await t.pumpWidget(const Welcome(), size: (30, 3));
    expect(t, containsLine(contains('Welcome')));
    await t.press('enter');
    await t.pump();
    expect(t, containsLine(contains('Home. q quits.')));
    expect(find.byType(Welcome), findsNothing);
    await t.press('q');
    expect(t.isRunning, isFalse);
  });

  testTwk('primaryFocus: the node with the focus', (t) async {
    await t.pumpWidget(const Who(), size: (30, 10));
    await t.press('f2');
    await t.pump();
    expect(t, containsLine(contains('focus: search')));
  });

  testTwk('nested GestureDetectors: the deepest takes the tap', (t) async {
    await t.pumpWidget(const Who(), size: (30, 10));
    await t.clickOn(find.text('inner'));
    await t.pump();
    expect(t, containsLine(contains('inner')));
    expect(t.lines.first, contains('inner'));
    // on the outer card's border
    final outer = t.rect(find.byType(Box).first);
    await t.click(outer.x, outer.y);
    await t.pump();
    expect(t.lines.first, contains('outer'));
  });

  testTwk('keys read together: each sees the state the last made', (t) async {
    await t.pumpWidget(const Counter(), size: (20, 2));
    await t.type('+++');
    await t.pump();
    expect(t, containsLine(contains('count: 3')));
  });

  testTwk('keys read together: a count read from the build is stale', (
    t,
  ) async {
    await t.pumpWidget(const _Stale(), size: (20, 2));
    await t.type('+++');
    await t.pump();
    expect(t, containsLine(contains('count: 1')));
  });
}

/// [Counter] with the handler reading the build's `count`, not the state's.
final class _Stale extends StatefulWidget {
  const _Stale();

  @override
  State<_Stale> createState() => _StaleState();
}

final class _StaleState extends State<_Stale> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return KeyBindings(
      {'+': () => setState(() => _count = count + 1)},
      child: Focus(autofocus: true, child: Text('count: $count')),
    );
  }
}
