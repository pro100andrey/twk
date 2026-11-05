// Dialog extras: a trailing widget in the title row, a child that is
// bounded and scrolls, showConfirm.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ms = Duration(milliseconds: 1);

/// Opens [dialog] on `d` over a field.
Widget app(Dialog dialog) => Overlay(
  child: Builder(
    builder: (context) => KeyBindings({
      'd': () => unawaited(showDialog<void>(context, (_) => dialog)),
    }, child: const Text('under')),
  ),
);

void main() {
  testTwk('trailing sits at the right end of the raised title row', (t) async {
    await t.pumpWidget(
      app(
        const Dialog(
          title: 'Item',
          trailing: Text('2/5 <>'),
          child: Text('Some long text here'),
        ),
      ),
      size: (30, 7),
    );
    await t.press('d');
    await t.pump(ms * 200);
    expect(t.lines.sublist(1, 5), [
      '',
      '     Item         2/5 <>',
      '     Some long text here',
      '',
    ]);
  });

  testTwk('trailing without a title, and in the bordered look', (t) async {
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: Dialog(trailing: Text('x'), child: Text('abcd')),
      ),
      size: (10, 4),
    );
    expect(t.lines.take(3), ['', '     x', '  abcd']);
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: Dialog(
          look: PanelLook.bordered,
          title: 'T',
          trailing: Text('2/5'),
          child: Text('abcdef'),
        ),
      ),
      size: (12, 5),
    );
    expect(
      t,
      matchesScreen('┌ T ─ 2/5 ─┐\n│ abcdef   │\n└──────────┘'),
    );
  });

  testTwk('a bordered dialog is as tall with trailing as without, and as '
      'wide as title and trailing need on the edge', (t) async {
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: Dialog(
          look: PanelLook.bordered,
          title: 'Title',
          trailing: Text('2/5'),
          child: Text('ab'),
        ),
      ),
      size: (20, 5),
    );
    expect(
      t,
      matchesScreen(
        '┌ Title ─ 2/5 ─┐\n'
        '│ ab           │\n'
        '└──────────────┘',
      ),
    );
  });

  testTwk('a bordered dialog builds its trailing once: one state', (t) async {
    var built = 0;
    await t.pumpWidget(
      Align(
        alignment: Alignment.topLeft,
        child: Dialog(
          look: PanelLook.bordered,
          title: 'Title',
          trailing: _Probe(() => built++),
          child: const Text('ab'),
        ),
      ),
      size: (24, 5),
    );
    expect(built, 1);
    expect(
      t,
      matchesScreen(
        '┌ Title ─ [x] ─┐\n'
        '│ ab           │\n'
        '└──────────────┘',
      ),
    );
  });

  testTwk('a bordered dialog with trailing or scrollable shrinks to its '
      'content, as the raised one', (t) async {
    await t.pumpWidget(
      app(
        const Dialog(
          look: PanelLook.bordered,
          title: 'T',
          trailing: Text('2/5'),
          child: Text('abcdef'),
        ),
      ),
      size: (40, 8),
    );
    await t.press('d');
    await t.pump(ms * 200);
    final trailing = t.lines.where((l) => l.contains('2/5')).single;
    expect(trailing.trim().length, lessThan(14), reason: t.lines.join('\n'));
    await t.pumpWidget(
      app(
        const Dialog(
          look: PanelLook.bordered,
          title: 'T',
          scrollable: true,
          child: Text('abcdef'),
        ),
      ),
      size: (40, 8),
    );
    await t.press('d');
    await t.pump(ms * 200);
    final row = t.lines.where((l) => l.contains('abcdef')).single;
    expect(row.trim().length, lessThan(14), reason: t.lines.join('\n'));
  });

  testTwk('the raised title keeps a gap before trailing', (t) async {
    await t.pumpWidget(
      app(
        const Dialog(
          title: 'Title',
          trailing: Text('1/2'),
          child: Text('abc'),
        ),
      ),
      size: (30, 7),
    );
    await t.press('d');
    await t.pump(ms * 200);
    expect(t, containsLine(contains('Title 1/2')));
  });

  testTwk('a scrollable child is bounded by the screen and scrolls', (
    t,
  ) async {
    await t.pumpWidget(
      app(
        Dialog(
          title: 'Long',
          scrollable: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [for (var i = 1; i <= 30; i++) Text('line $i')],
          ),
        ),
      ),
      size: (20, 10),
    );
    await t.press('d');
    await t.pump(ms * 200);
    expect(t.lines.length, 10);
    expect(t.lines[1], '      Long');
    expect(t.lines[2], '      line 1');
    expect(t, isNot(containsLine(contains('line 30'))));
    expect(t, containsLine(contains('line 6')));
  });

  testTwk('without scrollable the child is laid out as before', (t) async {
    await t.pumpWidget(
      app(const Dialog(title: 'Delete', child: Text('Delete 3 files?'))),
      size: (21, 7),
    );
    await t.press('d');
    await t.pump(ms * 200);
    expect(t.lines.sublist(1, 4), ['', '   Delete', '   Delete 3 files?']);
  });

  group('showConfirm', () {
    Future<void> open(TwkTester t, List<bool?> answers, {bool def = true}) =>
        t.pumpWidget(
          Overlay(
            child: Builder(
              builder: (context) => KeyBindings({
                'd': () => unawaited(
                  showConfirm(
                    context,
                    'Delete?',
                    defaultValue: def,
                  ).then(answers.add),
                ),
              }, child: const Text('under')),
            ),
          ),
          size: (30, 6),
        );

    testTwk('y answers true, n false, Enter the default', (t) async {
      final answers = <bool?>[];
      await open(t, answers);
      for (final (key, _) in [('y', true), ('n', false), ('enter', true)]) {
        await t.press('d');
        await t.pump(ms * 200);
        expect(t, containsLine(contains('Delete?')));
        await t.press(key);
        await t.pump(ms * 200);
      }
      expect(answers, [true, false, true]);
      expect(t, isNot(containsLine(contains('Delete?'))));
    });

    testTwk('Escape answers null; defaultValue false gives false on Enter', (
      t,
    ) async {
      final answers = <bool?>[];
      await open(t, answers, def: false);
      await t.press('d');
      await t.pump(ms * 200);
      await t.press('escape');
      await t.pump(ms * 200);
      await t.press('d');
      await t.pump(ms * 200);
      await t.press('enter');
      await t.pump(ms * 200);
      expect(answers, [null, false]);
    });
  });
}

/// A widget that counts the states it makes.
final class _Probe extends StatefulWidget {
  const _Probe(this.onInit);

  final void Function() onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

final class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Text('[x]');
}
