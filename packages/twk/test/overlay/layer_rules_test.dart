// The rules every layer follows: Escape is bound one way, so the layer
// nearest the focus hears it alone; a click outside a modal layer is
// swallowed by it, also where a non-modal layer is under it.
import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  test('only LayerEscape binds Escape in the overlay layers', () {
    final bound = <String>[];
    for (final file in Directory('lib/src/overlay').listSync()) {
      if (file is! File ||
          !file.path.endsWith('.dart') ||
          file.path.endsWith('layer_escape.dart')) {
        continue;
      }
      if (file.readAsStringSync().contains("'escape'")) {
        bound.add(file.path);
      }
    }
    expect(bound, isEmpty, reason: 'bind Escape with LayerEscape');
  });

  testTwk('Escape closes a menu over a dialog before the dialog', (t) async {
    final results = <Object?>[];
    await t.pumpWidget(
      App(
        child: Builder(
          builder: (context) => KeyBindings({
            'd': () => unawaited(
              showDialog<String>(
                context,
                (context) => Dialog(
                  child: KeyBindings({
                    'm': () => showContextMenu(
                      context,
                      [
                        MenuItem('Copy', onSelected: () {}),
                      ],
                      at: (2, 6),
                    ),
                  }, child: const Focus(autofocus: true, child: Text('body'))),
                ),
                fadeIn: Duration.zero,
              ).then(results.add),
            ),
          }, child: const Text('home')),
        ),
      ),
      size: (40, 10),
    );
    await t.pump();
    await t.press('d');
    await t.pump();
    await t.pump();
    await t.press('m');
    await t.pump();
    await t.pump();
    expect(t, containsLine(contains('Copy')));

    await t.press('escape');
    await t.pump();
    await t.pump();
    expect(t, isNot(containsLine(contains('Copy'))));
    expect(t, containsLine(contains('body')));
    expect(results, isEmpty, reason: 'the dialog is still open');

    await t.press('escape');
    await t.pump();
    await t.pump();
    expect(t, isNot(containsLine(contains('body'))));
    expect(results, [null]);
  });

  for (final navigated in [false, true]) {
    final where = navigated ? 'on a navigator' : 'without a navigator';

    testTwk(
      'a click outside a dialog over a popover $where closes the dialog only',
      (t) async {
        var open = true;
        var dismissed = 0;
        late BuildContext at;
        Widget home() => StatefulBuilder(
          builder: (context, setState) => Popover(
            open: open,
            onDismiss: () {
              dismissed++;
              setState(() => open = false);
            },
            popover: Builder(
              builder: (context) {
                at = context;
                return const Text('popover');
              },
            ),
            child: const Text('anchor'),
          ),
        );
        await t.pumpWidget(
          App(child: navigated ? Navigator(home: home()) : home()),
          size: (40, 10),
        );
        await t.pump();
        await t.pump();
        final results = <Object?>[];
        unawaited(
          showDialog<String>(
            at,
            (context) => const Dialog(child: Text('dialog')),
            alignment: Alignment.bottomCenter,
            fadeIn: Duration.zero,
          ).then(results.add),
        );
        await t.pump();
        await t.pump();
        expect(t, containsLine(contains('dialog')));

        // on the barrier, away from the popover and the dialog
        await t.click(35, 3);
        await t.pump();
        await t.pump();
        expect(results, [null], reason: 'the barrier closed the dialog');
        expect(dismissed, 0, reason: 'the click did not reach the popover');
        expect(t, containsLine(contains('popover')));
      },
    );
  }
}
