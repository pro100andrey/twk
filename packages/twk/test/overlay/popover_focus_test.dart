// A popover's content is in a focus scope of its own that requests nothing:
// an autofocus node in it gets the focus with a navigator above the
// popover as without one, content with no autofocus leaves the focus where
// it was, Tab inside stays among the popover's nodes, and onDismiss still
// comes as the focus leaves.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../disposing.dart';

/// A page: a popover by an anchor, under a focus node [field] and a
/// focus node [outside].
Widget page(
  Widget popover, {
  required FocusNode field,
  FocusNode? outside,
  VoidCallback? onDismiss,
  bool open = true,
}) => Column(
  children: [
    Focus(focusNode: outside, child: const Text('outside')),
    Popover(
      open: open,
      onDismiss: onDismiss,
      popover: popover,
      child: Focus(focusNode: field, child: const Text('anchor')),
    ),
  ],
);

/// Pumps the page closed, focuses [field], then opens the popover.
Future<void> openFocused(
  TwkTester t,
  Widget Function(bool open) build, {
  required FocusNode field,
  required bool navigated,
}) async {
  Widget app(bool open) =>
      App(child: navigated ? Navigator(home: build(open)) : build(open));
  await t.pumpWidget(app(false), size: (30, 8));
  await t.pump();
  field.requestFocus();
  await t.pump();
  expect(field.hasPrimaryFocus, isTrue);
  await t.pumpWidget(app(true), size: (30, 8));
  await t.pump();
  await t.pump();
}

void main() {
  for (final navigated in [false, true]) {
    final where = navigated ? 'on a navigator page' : 'without a navigator';

    testTwk('autofocus in a popover $where gets the focus', (t) async {
      final field = FocusNode(debugLabel: 'field');
      addTearDown(field.dispose);
      final go = FocusNode(debugLabel: 'go');
      addTearDown(go.dispose);
      await openFocused(
        t,
        (open) => page(
          Focus(focusNode: go, autofocus: true, child: const Text('go')),
          field: field,
          open: open,
        ),
        field: field,
        navigated: navigated,
      );
      expect(go.hasPrimaryFocus, isTrue);
    });

    testTwk('a popover with no autofocus $where leaves the focus', (t) async {
      final field = FocusNode(debugLabel: 'field');
      addTearDown(field.dispose);
      final go = FocusNode(debugLabel: 'go');
      addTearDown(go.dispose);
      await openFocused(
        t,
        (open) => page(
          Focus(focusNode: go, child: const Text('go')),
          field: field,
          open: open,
        ),
        field: field,
        navigated: navigated,
      );
      expect(t, containsLine(contains('go')));
      expect(field.hasPrimaryFocus, isTrue);
    });
  }

  /// Opens a popover of nodes [go] (autofocus) and [other], by [field],
  /// with [after] following it in the page.
  Future<void> openTwo(
    TwkTester t, {
    required FocusNode field,
    required FocusNode go,
    required FocusNode other,
    required FocusNode after,
    required VoidCallback onDismiss,
  }) async {
    Widget app(bool open) => App(
      child: Navigator(
        home: Column(
          children: [
            Popover(
              open: open,
              onDismiss: onDismiss,
              popover: Column(
                children: [
                  Focus(
                    focusNode: go,
                    autofocus: true,
                    child: const Text('go'),
                  ),
                  Focus(focusNode: other, child: const Text('other')),
                ],
              ),
              child: Focus(focusNode: field, child: const Text('anchor')),
            ),
            Focus(focusNode: after, child: const Text('after')),
          ],
        ),
      ),
    );
    await t.pumpWidget(app(false), size: (30, 8));
    await t.pump();
    field.requestFocus();
    await t.pump();
    await t.pumpWidget(app(true), size: (30, 8));
    await t.pump();
    await t.pump();
  }

  testTwk('Tab inside a popover moves between its nodes', (t) async {
    final go = FocusNode(debugLabel: 'go');
    addTearDown(go.dispose);
    final other = FocusNode(debugLabel: 'other');
    addTearDown(other.dispose);
    var dismissed = 0;
    await openTwo(
      t,
      field: disposing(FocusNode(debugLabel: 'field')),
      go: go,
      other: other,
      after: disposing(FocusNode(debugLabel: 'after')),
      onDismiss: () => dismissed++,
    );
    expect(go.hasPrimaryFocus, isTrue);
    await t.press('tab');
    await t.pump();
    expect(other.hasPrimaryFocus, isTrue);
    await t.press('shift+tab');
    await t.pump();
    expect(go.hasPrimaryFocus, isTrue);
    expect(dismissed, 0);
  });

  testTwk('Tab from the last node leaves to the node after the anchor', (
    t,
  ) async {
    final other = FocusNode(debugLabel: 'other');
    addTearDown(other.dispose);
    final after = FocusNode(debugLabel: 'after');
    addTearDown(after.dispose);
    var dismissed = 0;
    await openTwo(
      t,
      field: disposing(FocusNode(debugLabel: 'field')),
      go: disposing(FocusNode(debugLabel: 'go')),
      other: other,
      after: after,
      onDismiss: () => dismissed++,
    );
    await t.press('tab');
    await t.pump();
    expect(other.hasPrimaryFocus, isTrue);
    await t.press('tab');
    await t.pump();
    expect(after.hasPrimaryFocus, isTrue);
    expect(dismissed, 1);
  });

  testTwk('Shift+Tab from the first node leaves to the anchor', (t) async {
    final field = FocusNode(debugLabel: 'field');
    addTearDown(field.dispose);
    final go = FocusNode(debugLabel: 'go');
    addTearDown(go.dispose);
    var dismissed = 0;
    await openTwo(
      t,
      field: field,
      go: go,
      other: disposing(FocusNode(debugLabel: 'other')),
      after: disposing(FocusNode(debugLabel: 'after')),
      onDismiss: () => dismissed++,
    );
    expect(go.hasPrimaryFocus, isTrue);
    await t.press('shift+tab');
    await t.pump();
    expect(field.hasPrimaryFocus, isTrue);
    // the focus is still in the anchor, which keeps the popover open
    expect(dismissed, 0);
  });

  testTwk('onDismiss still comes as the focus leaves the popover', (t) async {
    final field = FocusNode(debugLabel: 'field');
    addTearDown(field.dispose);
    final go = FocusNode(debugLabel: 'go');
    addTearDown(go.dispose);
    final outside = FocusNode(debugLabel: 'outside');
    addTearDown(outside.dispose);
    var dismissed = 0;
    await openFocused(
      t,
      (open) => page(
        Focus(focusNode: go, autofocus: true, child: const Text('go')),
        field: field,
        outside: outside,
        onDismiss: () => dismissed++,
        open: open,
      ),
      field: field,
      navigated: true,
    );
    expect(go.hasPrimaryFocus, isTrue);
    expect(dismissed, 0);
    outside.requestFocus();
    await t.pump();
    expect(dismissed, 1);
  });
}
