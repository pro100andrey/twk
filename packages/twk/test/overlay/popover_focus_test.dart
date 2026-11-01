// A popover's content is in a focus scope of its own that requests nothing:
// an autofocus node in it gets the focus with a navigator above the
// popover as without one, content with no autofocus leaves the focus where
// it was, Tab inside stays among the popover's nodes, and onDismiss still
// comes as the focus leaves.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

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
      final go = FocusNode(debugLabel: 'go');
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
      final go = FocusNode(debugLabel: 'go');
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

  testTwk('Tab inside a popover stays among its nodes', (t) async {
    final field = FocusNode(debugLabel: 'field');
    final go = FocusNode(debugLabel: 'go');
    final other = FocusNode(debugLabel: 'other');
    await openFocused(
      t,
      (open) => page(
        Column(
          children: [
            Focus(focusNode: go, autofocus: true, child: const Text('go')),
            Focus(focusNode: other, child: const Text('other')),
          ],
        ),
        field: field,
        open: open,
      ),
      field: field,
      navigated: true,
    );
    expect(go.hasPrimaryFocus, isTrue);
    await t.press('tab');
    await t.pump();
    expect(other.hasPrimaryFocus, isTrue);
    await t.press('tab');
    await t.pump();
    expect(go.hasPrimaryFocus, isTrue);
  });

  testTwk('onDismiss still comes as the focus leaves the popover', (t) async {
    final field = FocusNode(debugLabel: 'field');
    final go = FocusNode(debugLabel: 'go');
    final outside = FocusNode(debugLabel: 'outside');
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
