// Callout: a box lined in its kind's color with the icon and the title on
// its top edge, the text wrapped inside; [×] and Escape dismissing it; the
// actions at the right below the text; on plain output a line without the
// box; read as a status, or an alert for a warning or an error.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/plain_lines.dart';

/// [children] one below another at their left edge.
Column column(List<Widget> children) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: children,
);

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

void main() {
  testTwk("a box in the kind's color, its icon and name bold on the top "
      "edge, the text inside in the theme's", (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: column([
          const Callout.text('A newer version is out.'),
          const Callout.text('Disk full', kind: StatusKind.error),
        ]),
      ),
      size: (40, 6),
    );
    expect(t.lines, [
      '┌─ ℹ Info ────────────────┐',
      '│ A newer version is out. │',
      '└─────────────────────────┘',
      '┌─ ✗ Error ─┐',
      '│ Disk full │',
      '└───────────┘',
    ]);
    expect(
      t,
      styleAt(0, 0, allOf(hasFg(Color.cyan), isNot(hasAttr(Attr.bold)))),
    );
    expect(t, styleAt(3, 0, allOf(hasFg(Color.cyan), hasAttr(Attr.bold))));
    expect(t, styleAt(5, 0, allOf(hasFg(Color.cyan), hasAttr(Attr.bold))));
    expect(t, styleAt(26, 1, hasFg(Color.cyan)));
    expect(t, styleAt(2, 1, isNot(hasFg(Color.cyan))));
    expect(t, styleAt(0, 4, hasFg(Color.red)));
  });

  testTwk('a title and an icon of its own, any child, and text that wraps '
      'at the width it gets', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: column([
          const Callout.text('Ctrl+K searches.', title: 'Tip', icon: '*'),
          const Callout(
            kind: StatusKind.success,
            icon: '',
            child: Text('Built', style: Style(attrs: Attr.italic)),
          ),
          const SizedBox(
            width: 20,
            child: Callout.text(
              'a text long enough to wrap',
              kind: StatusKind.warning,
            ),
          ),
        ]),
      ),
      size: (40, 10),
    );
    expect(t.lines, [
      '┌─ * Tip ──────────┐',
      '│ Ctrl+K searches. │',
      '└──────────────────┘',
      '┌─ Success ─┐',
      '│ Built     │',
      '└───────────┘',
      '┌─ ⚠ Warning ──────┐',
      '│ a text long      │',
      '│ enough to wrap   │',
      '└──────────────────┘',
    ]);
    expect(t, styleAt(2, 4, hasAttr(Attr.italic)));
    expect(t, styleAt(0, 6, hasFg(Color.yellow)));
  });

  testTwk('with onDismissed, [×] at the right of the top edge, which a '
      'click dismisses; the mouse over it lights it', (t) async {
    var dismissed = 0;
    await t.pumpWidget(
      Theme.terminal(
        child: column([Callout.text('Saved', onDismissed: () => dismissed++)]),
      ),
      size: (30, 3),
    );
    expect(t.lines, [
      '┌─ ℹ Info ──[×]─┐',
      '│ Saved         │',
      '└───────────────┘',
    ]);
    expect(
      t,
      styleAt(12, 0, allOf(hasFg(Color.cyan), isNot(hasAttr(Attr.bold)))),
    );
    await t.mouse(MouseKind.move, 13, 0);
    await t.pump();
    expect(t, styleAt(12, 0, hasAttr(Attr.bold)));
    expect(t, styleAt(14, 0, hasAttr(Attr.bold)));
    await t.mouse(MouseKind.move, 3, 1);
    await t.pump();
    expect(t, styleAt(12, 0, isNot(hasAttr(Attr.bold))));
    await t.click(11, 0);
    await t.click(15, 0);
    await t.click(2, 1);
    await t.pump();
    expect(dismissed, 0);
    await t.click(13, 0);
    await t.pump();
    expect(dismissed, 1);
  });

  testTwk('Escape dismisses it while the focus is inside, hinted; not '
      'without onDismissed, nor with the focus outside', (t) async {
    var dismissed = 0;
    final inside = FocusNode(debugLabel: 'inside');
    final outside = FocusNode(debugLabel: 'outside');
    addTearDown(inside.dispose);
    addTearDown(outside.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: column([
          Callout.text(
            'Update?',
            onDismissed: () => dismissed++,
            actions: [Button('Later', focusNode: inside, onPressed: () {})],
          ),
          Button('Elsewhere', focusNode: outside, onPressed: () {}),
        ]),
      ),
      size: (30, 6),
    );
    inside.requestFocus();
    await t.pump();
    expect(hints(t), contains('escape dismiss'));
    await t.press('escape');
    await t.pump();
    expect(dismissed, 1);
    outside.requestFocus();
    await t.pump();
    expect(hints(t), isNot(contains('escape dismiss')));
    await t.press('escape');
    await t.pump();
    expect(dismissed, 1);

    await t.pumpWidget(
      Theme.terminal(
        child: column([
          Callout.text(
            'Update?',
            actions: [Button('Later', focusNode: inside, onPressed: () {})],
          ),
        ]),
      ),
    );
    inside.requestFocus();
    await t.pump();
    expect(t.lines.first, '┌─ ℹ Info ─┐');
    expect(hints(t), isNot(contains('escape dismiss')));
  });

  testTwk('the actions go below the text at the right, a blank apart, the '
      'box as wide as the wider', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: column([
          Callout.text(
            'Version 2.0 is out.',
            actions: [
              Button('Later', onPressed: () {}),
              Button('Update', onPressed: () {}),
            ],
          ),
          Callout.text(
            'Go?',
            kind: StatusKind.warning,
            actions: [Button('Yes', onPressed: () {})],
          ),
        ]),
      ),
      size: (40, 8),
    );
    expect(t.lines, [
      '┌─ ℹ Info ────────────┐',
      '│ Version 2.0 is out. │',
      '│     Later   Update  │',
      '└─────────────────────┘',
      '┌─ ⚠ Warning ─┐',
      '│ Go?         │',
      '│        Yes  │',
      '└─────────────┘',
    ]);
  });

  testTwk('a screen reader reads a status of its title, an alert for a '
      'warning or an error, then the text', (t) async {
    await t.pumpWidget(
      Theme.terminal(
        child: column([
          const Callout.text('New version', kind: StatusKind.success),
          const Callout.text('Low disk', kind: StatusKind.warning),
          const Callout.text('Failed', kind: StatusKind.error, title: 'Build'),
        ]),
      ),
      size: (30, 9),
    );
    expect(t.binding.semantics.lines, [
      'status Success',
      'New version',
      'alert Warning',
      'Low disk',
      'alert Build',
      'Failed',
    ]);
  });

  test('on plain output the icon, the title and the text on a line, no '
      'box, the text wrapping under itself; no [×]', () async {
    final lines = await plainLines(
      column([
        const Callout.text('A newer version is out.'),
        Callout.text(
          'The disk is almost full, clean it up',
          kind: StatusKind.warning,
          onDismissed: () {},
        ),
      ]),
      width: 30,
    );
    expect(lines, [
      'ℹ Info: A newer version is',
      '        out.',
      '⚠ Warning: The disk is almost',
      '           full, clean it up',
    ]);
  });
}
