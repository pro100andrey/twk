// A modal layer opened above a non-modal one does not close it, and a
// non-modal one inside a modal layer works: a dialog opened from a Popover
// leaves the popover open, closed it gives the focus back to the node in
// the popover that had it; a Popover in a dialog opens, takes no focus
// unless it has autofocus inside, and Escape closes it before the dialog.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  for (final navigated in [false, true]) {
    final where = navigated ? 'on a navigator' : 'without a navigator';

    testTwk('a dialog opened from a popover $where leaves it open', (t) async {
      final field = FocusNode(debugLabel: 'field');
      final inside = FocusNode(debugLabel: 'inside');
      final ok = FocusNode(debugLabel: 'ok');
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
              return Focus(
                focusNode: inside,
                autofocus: true,
                child: const Text('popover'),
              );
            },
          ),
          child: Focus(focusNode: field, child: const Text('anchor')),
        ),
      );
      await t.pumpWidget(
        App(child: navigated ? Navigator(home: home()) : home()),
        size: (40, 10),
      );
      await t.pump();
      await t.pump();
      expect(inside.hasPrimaryFocus, isTrue);

      unawaited(
        showDialog<void>(
          at,
          (context) => Dialog(
            child: Focus(
              focusNode: ok,
              autofocus: true,
              child: const Text('dialog'),
            ),
          ),
          fadeIn: Duration.zero,
        ),
      );
      await t.pump();
      await t.pump();
      expect(ok.hasPrimaryFocus, isTrue);
      expect(dismissed, 0, reason: 'the popover is not dismissed');
      expect(t, containsLine(contains('popover')));

      await t.press('escape');
      await t.pump();
      await t.pump();
      expect(t, isNot(containsLine(contains('dialog'))));
      expect(dismissed, 0);
      expect(t, containsLine(contains('popover')));
      expect(inside.hasPrimaryFocus, isTrue);
    });

    testTwk('a popover in a dialog $where opens and Escape closes it first', (
      t,
    ) async {
      final inside = FocusNode(debugLabel: 'inside');
      final ok = FocusNode(debugLabel: 'ok');
      var open = false;
      var dismissed = 0;
      late void Function(void Function()) set;
      final results = <Object?>[];
      Widget home() => Builder(
        builder: (context) => KeyBindings({
          'd': () => unawaited(
            showDialog<String>(
              context,
              (context) => Dialog(
                child: StatefulBuilder(
                  builder: (context, setState) {
                    set = setState;
                    return Popover(
                      open: open,
                      onDismiss: () {
                        dismissed++;
                        setState(() => open = false);
                      },
                      popover: Focus(
                        focusNode: inside,
                        autofocus: true,
                        child: const Text('pop'),
                      ),
                      child: Focus(
                        focusNode: ok,
                        autofocus: true,
                        child: const Text('anchor'),
                      ),
                    );
                  },
                ),
              ),
              fadeIn: Duration.zero,
            ).then(results.add),
          ),
        }, child: const Text('home')),
      );
      await t.pumpWidget(
        App(child: navigated ? Navigator(home: home()) : home()),
        size: (40, 10),
      );
      await t.pump();
      await t.press('d');
      await t.pump();
      await t.pump();
      expect(ok.hasPrimaryFocus, isTrue);
      set(() => open = true);
      await t.pump();
      await t.pump();
      await t.pump();
      expect(t, containsLine(contains('pop')));
      expect(inside.hasPrimaryFocus, isTrue);

      await t.press('escape');
      await t.pump();
      await t.pump();
      expect(dismissed, 1);
      expect(results, isEmpty, reason: 'the dialog is still open');
      expect(t, containsLine(contains('anchor')));
      expect(t, isNot(containsLine(contains('pop'))));
    });
  }

  testTwk('a popover closes when a dialog over it cannot give it the focus '
      'back', (t) async {
    final inside = FocusNode(debugLabel: 'inside');
    final other = FocusNode(debugLabel: 'other');
    final ok = FocusNode(debugLabel: 'ok');
    var open = true;
    var kept = true;
    var dismissed = 0;
    late StateSetter set;
    late BuildContext at;
    await t.pumpWidget(
      App(
        child: StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            at = context;
            return Column(
              children: [
                Popover(
                  open: open,
                  onDismiss: () {
                    dismissed++;
                    setState(() => open = false);
                  },
                  popover: kept
                      ? Focus(
                          focusNode: inside,
                          autofocus: true,
                          child: const Text('popover'),
                        )
                      : const Text('popover'),
                  child: const Text('anchor'),
                ),
                Focus(focusNode: other, child: const Text('other')),
              ],
            );
          },
        ),
      ),
      size: (40, 10),
    );
    await t.pump();
    await t.pump();
    expect(inside.hasPrimaryFocus, isTrue);

    unawaited(
      showDialog<void>(
        at,
        (context) => Dialog(
          child: Focus(
            focusNode: ok,
            autofocus: true,
            child: const Text('dialog'),
          ),
        ),
        fadeIn: Duration.zero,
      ),
    );
    await t.pump();
    await t.pump();
    expect(ok.hasPrimaryFocus, isTrue);
    expect(dismissed, 0);

    // what the dialog remembered goes while it is open
    set(() => kept = false);
    await t.pump();
    await t.press('escape');
    await t.pump();
    await t.pump();

    expect(ok.hasPrimaryFocus, isFalse);
    expect(dismissed, 1, reason: 'no focus came back to the popover');
  });

  testTwk('a closed popover does not watch a dialog over it', (t) async {
    final field = FocusNode(debugLabel: 'field');
    final ok = FocusNode(debugLabel: 'ok');
    late BuildContext at;
    await t.pumpWidget(
      App(
        child: Builder(
          builder: (context) {
            at = context;
            return Popover(
              open: false,
              onDismiss: () {},
              popover: const Text('popover'),
              child: Focus(
                focusNode: field,
                autofocus: true,
                child: const Text('anchor'),
              ),
            );
          },
        ),
      ),
      size: (40, 10),
    );
    await t.pump();
    expect(field.hasPrimaryFocus, isTrue);
    final keys = field.manager!.keysChanged as ChangeNotifier;
    expect(keys.hasListeners, isFalse);

    unawaited(
      showDialog<void>(
        at,
        (context) => Dialog(
          child: Focus(
            focusNode: ok,
            autofocus: true,
            child: const Text('dialog'),
          ),
        ),
        fadeIn: Duration.zero,
      ),
    );
    await t.pump();
    await t.pump();
    expect(ok.hasPrimaryFocus, isTrue);
    expect(keys.hasListeners, isFalse);
  });

  testTwk('a menu opened from a popover leaves it open', (t) async {
    final inside = FocusNode(debugLabel: 'inside');
    var open = true;
    var dismissed = 0;
    late BuildContext at;
    await t.pumpWidget(
      App(
        child: StatefulBuilder(
          builder: (context, setState) => Popover(
            open: open,
            onDismiss: () {
              dismissed++;
              setState(() => open = false);
            },
            popover: Builder(
              builder: (context) {
                at = context;
                return Focus(
                  focusNode: inside,
                  autofocus: true,
                  child: const Text('popover'),
                );
              },
            ),
            child: const Text('anchor'),
          ),
        ),
      ),
      size: (40, 10),
    );
    await t.pump();
    await t.pump();
    expect(inside.hasPrimaryFocus, isTrue);

    showContextMenu(at, [MenuItem('Copy', onSelected: () {})], at: (2, 4));
    await t.pump();
    await t.pump();
    expect(t, containsLine(contains('Copy')));
    expect(dismissed, 0, reason: 'the popover is not dismissed');

    await t.press('escape');
    await t.pump();
    await t.pump();
    expect(t, isNot(containsLine(contains('Copy'))));
    expect(dismissed, 0);
    expect(t, containsLine(contains('popover')));
    expect(inside.hasPrimaryFocus, isTrue);
  });
}
