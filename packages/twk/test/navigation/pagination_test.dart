// Pagination: the arrows, the first and the last page, the current one
// between brackets with its siblings and … for the gaps, the range of
// items; the arrows muted at the ends; fitted to narrower widths by the
// words of the arrows, then the siblings, then the range; one stop of
// Tab whose arrows, PageUp, PageDown, Home, End and digits typed with
// Enter change the page; clicks and the hover; a disabled row; the
// arrows left out; read as a list of buttons; where … and – are two
// columns wide.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

String? focused(TwkTester t) => t.binding.focusManager.primaryFocus?.debugLabel;

List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

/// Presses each key of [keys], pumping a frame after each.
Future<void> press(TwkTester t, String keys) async {
  for (final key in keys.split(' ')) {
    await t.press(key);
    await t.pump();
  }
}

Future<void> click(TwkTester t, int x, int y) async {
  await t.click(x, y);
  await t.pump();
}

/// The pages of 840 items, 20 a page, [width] columns wide, the one shown
/// kept in [page] and each change added to [changes]; then a button to
/// move the focus to.
Widget pages(
  ValueNotifier<int> page,
  int width, {
  List<int>? changes,
  int pageCount = 42,
  int? itemCount = 840,
  int? pageSize = 20,
  int siblings = 1,
  bool showFirstLast = true,
  bool showPrevNext = true,
  bool enabled = true,
  FocusNode? focusNode,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    SizedBox(
      width: width,
      child: ValueListenableBuilder(
        valueListenable: page,
        builder: (context, value, _) => Pagination(
          page: value,
          pageCount: pageCount,
          itemCount: itemCount,
          pageSize: pageSize,
          siblings: siblings,
          showFirstLast: showFirstLast,
          showPrevNext: showPrevNext,
          focusNode: focusNode,
          onChanged: enabled
              ? (value) {
                  changes?.add(value);
                  page.value = value;
                }
              : null,
        ),
      ),
    ),
    Button(
      'next',
      focusNode: FocusNode(debugLabel: 'next'),
      onPressed: () {},
    ),
  ],
);

/// The first line of [page] shown in a row of [width] columns.
Future<String> row(
  TwkTester t,
  int page, {
  int width = 70,
  int pageCount = 42,
  int siblings = 1,
  int? itemCount = 840,
  int? pageSize = 20,
}) async {
  await t.pumpWidget(
    Theme.terminal(
      child: pages(
        ValueNotifier(page),
        width,
        pageCount: pageCount,
        siblings: siblings,
        itemCount: itemCount,
        pageSize: pageSize,
      ),
    ),
    size: (width < 70 ? 70 : width, 3),
  );
  return t.lines.first.trimRight();
}

void main() {
  testTwk('the arrows, the pages, the current one between brackets in the '
      'primary color and bold, … for a gap, the range; the arrows that go '
      'nowhere, the gap and the range muted', (t) async {
    final page = ValueNotifier(1);
    await t.pumpWidget(Theme.terminal(child: pages(page, 70)), size: (70, 3));
    expect(
      t.lines.first.trimRight(),
      '« First ‹ Prev 1 [2] 3 4 5 … 42 Next › Last »  (21–40 of 840)',
    );
    expect(t, styleAt(18, 0, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
    for (final x in [0, 8, 15, 21, 29, 32, 39]) {
      expect(
        t,
        styleAt(x, 0, isNot(hasFg(const Color.indexed(245)))),
        reason: 'at $x',
      );
    }
    expect(t, styleAt(27, 0, hasFg(const Color.indexed(245))));
    expect(t, styleAt(48, 0, hasFg(const Color.indexed(245))));
    page.value = 0;
    await t.pump();
    expect(t.lines.first, startsWith('« First ‹ Prev [1] 2 3 4 5 … 42'));
    expect(t, styleAt(0, 0, hasFg(const Color.indexed(245))));
    expect(t, styleAt(8, 0, hasFg(const Color.indexed(245))));
    page.value = 41;
    await t.pump();
    expect(
      t.lines.first.trimRight(),
      '« First ‹ Prev 1 … 38 39 40 41 [42] Next › Last »  (821–840 of 840)',
    );
    expect(t, styleAt(37, 0, hasFg(const Color.indexed(245))));
    expect(t, styleAt(44, 0, hasFg(const Color.indexed(245))));
    expect(t, styleAt(0, 0, isNot(hasFg(const Color.indexed(245)))));
  });

  testTwk('as many pages wherever the current one is: the first and the '
      'last, the siblings, … or the page a gap of one would hide', (t) async {
    String strip(String line) => line
        .replaceFirst('« First ‹ Prev ', '')
        .replaceFirst(RegExp(' Next › Last ».*'), '');
    final shown = {
      for (final p in [0, 2, 3, 4, 20, 37, 38, 41])
        p + 1: strip(await row(t, p)),
    };
    expect(shown, {
      1: '[1] 2 3 4 5 … 42',
      3: '1 2 [3] 4 5 … 42',
      4: '1 2 3 [4] 5 … 42',
      5: '1 … 4 [5] 6 … 42',
      21: '1 … 20 [21] 22 … 42',
      38: '1 … 37 [38] 39 … 42',
      39: '1 … 38 [39] 40 41 42',
      42: '1 … 38 39 40 41 [42]',
    });
    expect(
      strip(await row(t, 20, siblings: 2, width: 80)),
      '1 … 19 20 [21] 22 23 … 42',
    );
    expect(strip(await row(t, 20, siblings: 0)), '1 … [21] … 42');
    expect(strip(await row(t, 0, pageCount: 1)), '[1]');
    expect(strip(await row(t, 1, pageCount: 3)), '1 [2] 3');
    expect(strip(await row(t, 3, pageCount: 7)), '1 2 3 [4] 5 6 7');
    expect(
      await row(t, 0, pageCount: 0, itemCount: null),
      '« First ‹ Prev Next › Last »',
    );
  });

  testTwk('the range of the last page ends at the items; none without both '
      'the count and the size', (t) async {
    expect(
      await row(t, 41, itemCount: 830),
      endsWith('Last »  (821–830 of 830)'),
    );
    expect(await row(t, 0, itemCount: 0, pageCount: 0), endsWith('(0 of 0)'));
    expect(await row(t, 1, pageSize: null), endsWith('Last »'));
    expect(await row(t, 1, itemCount: null), endsWith('Last »'));
  });

  testTwk('fits the width: the words of the arrows go first, then the '
      'siblings, then the range; past that it is cut off', (t) async {
    final shown = {
      for (final width in [65, 64, 44, 43, 40, 39, 36, 35, 15])
        width: await row(t, 1, width: width, siblings: 2),
    };
    expect(shown, {
      65: '« First ‹ Prev 1 [2] 3 4 5 6 7 … 42 Next › Last »  (21–40 of 840)',
      64: '« ‹ 1 [2] 3 4 5 6 7 … 42 › »  (21–40 of 840)',
      44: '« ‹ 1 [2] 3 4 5 6 7 … 42 › »  (21–40 of 840)',
      43: '« ‹ 1 [2] 3 4 5 … 42 › »  (21–40 of 840)',
      40: '« ‹ 1 [2] 3 4 5 … 42 › »  (21–40 of 840)',
      39: '« ‹ 1 [2] 3 … 42 › »  (21–40 of 840)',
      36: '« ‹ 1 [2] 3 … 42 › »  (21–40 of 840)',
      35: '« ‹ 1 [2] 3 … 42 › »',
      15: '« ‹ 1 [2] 3 … 4',
    });
  });

  testTwk('one stop of Tab: Left and Right go to the page before and after, '
      'PageUp and PageDown ten back and on, Home and End to the ends, '
      'nothing past them; hinted', (t) async {
    final page = ValueNotifier(1);
    final changes = <int>[];
    final node = FocusNode(debugLabel: 'pages');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: pages(page, 70, changes: changes, focusNode: node),
      ),
      size: (70, 3),
    );
    await press(t, 'tab');
    expect(focused(t), 'pages');
    expect(hints(t), ['left previous', 'right next', '0 …9 page']);
    // the current page highlighted while it has the focus
    expect(t, styleAt(18, 0, hasBg(const Color.indexed(237))));
    await press(t, 'right right left');
    expect(changes, [2, 3, 2]);
    await press(t, 'pagedown pageup pageup');
    expect(changes, [2, 3, 2, 12, 2, 0]);
    await press(t, 'left home');
    expect(changes, hasLength(6));
    await press(t, 'end right pagedown');
    expect(changes, [2, 3, 2, 12, 2, 0, 41]);
    await press(t, 'tab');
    expect(focused(t), 'next');
    expect(t.lines.first, contains('[42]'));
  });

  testTwk('digits typed show after the row, Enter goes to that page, the '
      'last where there are fewer; Backspace takes one back, Escape and '
      'the focus leaving drop them', (t) async {
    final page = ValueNotifier(0);
    final changes = <int>[];
    final node = FocusNode(debugLabel: 'pages');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: pages(
          page,
          70,
          changes: changes,
          focusNode: node,
          itemCount: null,
        ),
      ),
      size: (70, 3),
    );
    node.requestFocus();
    await t.pump();
    await press(t, '1 2');
    expect(t.lines.first.trimRight(), endsWith('Last »  → 12'));
    expect(hints(t), contains('enter go'));
    await press(t, 'enter');
    expect(changes, [11]);
    expect(t.lines.first.trimRight(), endsWith('Last »'));
    // no more digits than the last page has
    await press(t, '9 9 9');
    expect(t.lines.first.trimRight(), endsWith('→ 99'));
    await press(t, 'enter');
    expect(changes, [11, 41]);
    await press(t, '3 4 backspace');
    expect(t.lines.first.trimRight(), endsWith('→ 3'));
    await press(t, 'escape');
    expect(t.lines.first.trimRight(), endsWith('Last »'));
    await press(t, 'enter');
    expect(changes, [11, 41]);
    await press(t, '0 enter');
    expect(changes, [11, 41, 0]);
    await press(t, '5 tab');
    expect(t.lines.first.trimRight(), endsWith('Last »'));
    node.requestFocus();
    await t.pump();
    await press(t, 'enter');
    expect(changes, [11, 41, 0]);
  });

  testTwk('a click on a page or an arrow goes there and focuses the row; '
      'the current page, the gap, the range and the arrows that go nowhere '
      'do nothing', (t) async {
    final page = ValueNotifier(0);
    final changes = <int>[];
    final node = FocusNode(debugLabel: 'pages');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: pages(page, 70, changes: changes, focusNode: node),
      ),
      size: (70, 3),
    );
    // « First ‹ Prev [1] 2 3 4 5 … 42 Next › Last »  (1–20 of 840)
    for (final x in [1, 9, 16, 27, 50]) {
      await click(t, x, 0);
    }
    expect(changes, isEmpty);
    await click(t, 19, 0);
    expect(changes, [1]);
    expect(focused(t), 'pages');
    // « First ‹ Prev 1 [2] 3 4 5 … 42 Next › Last »  (21–40 of 840)
    await click(t, 34, 0);
    await click(t, 9, 0);
    await click(t, 42, 0);
    await click(t, 2, 0);
    await click(t, 29, 0);
    expect(changes, [1, 2, 1, 41, 0, 41]);
  });

  testTwk('the mouse over a page or an arrow underlines it', (t) async {
    await t.pumpWidget(
      Theme.terminal(child: pages(ValueNotifier(1), 70)),
      size: (70, 3),
    );
    await t.mouse(MouseKind.move, 21, 0);
    await t.pump();
    expect(t, styleAt(21, 0, hasAttr(Attr.underline)));
    await t.mouse(MouseKind.move, 33, 0);
    await t.pump();
    expect(t, styleAt(21, 0, isNot(hasAttr(Attr.underline))));
    expect(t, styleAt(33, 0, hasAttr(Attr.underline)));
    await t.mouse(MouseKind.move, 18, 0);
    await t.pump();
    expect(t, styleAt(18, 0, isNot(hasAttr(Attr.underline))));
  });

  testTwk('without onChanged it takes neither the focus nor the mouse, all '
      'of it muted', (t) async {
    final page = ValueNotifier(1);
    final node = FocusNode(debugLabel: 'pages');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: pages(page, 70, enabled: false, focusNode: node)),
      size: (70, 3),
    );
    for (final x in [0, 15, 18, 21, 32]) {
      expect(
        t,
        styleAt(x, 0, hasFg(const Color.indexed(245))),
        reason: 'at $x',
      );
    }
    await click(t, 21, 0);
    expect(page.value, 1);
    await press(t, 'tab');
    expect(focused(t), 'next');
  });

  testTwk('without showFirstLast or showPrevNext those arrows are left out', (
    t,
  ) async {
    await t.pumpWidget(
      Theme.terminal(child: pages(ValueNotifier(1), 70, showFirstLast: false)),
      size: (70, 3),
    );
    expect(
      t.lines.first.trimRight(),
      '‹ Prev 1 [2] 3 4 5 … 42 Next ›  (21–40 of 840)',
    );
    await t.pumpWidget(
      Theme.terminal(child: pages(ValueNotifier(1), 70, showPrevNext: false)),
      size: (70, 3),
    );
    expect(
      t.lines.first.trimRight(),
      '« First 1 [2] 3 4 5 … 42 Last »  (21–40 of 840)',
    );
  });

  testTwk('read as a list of buttons, those that go nowhere disabled, the '
      'current page selected and focused, then the range', (t) async {
    final node = FocusNode(debugLabel: 'pages');
    addTearDown(node.dispose);
    final page = ValueNotifier(0);
    await t.pumpWidget(
      Theme.terminal(
        child: pages(page, 70, focusNode: node, pageCount: 3, itemCount: 50),
      ),
      size: (70, 3),
    );
    node.requestFocus();
    await t.pump();
    expect(t.binding.semantics.lines.take(9), [
      'list',
      'button First page, disabled',
      'button Previous page, disabled',
      'button Page 1, selected',
      'button Page 2',
      'button Page 3',
      'button Next page',
      'button Last page',
      '1–20 of 50',
    ]);
    expect(t.binding.semantics.focusedLine, 3);
    await press(t, 'right');
    expect(t.binding.semantics.focusedLine, 4);
  });

  group('where … and – are two columns wide (ambiguous width 2)', () {
    test('a click hits the page drawn where it is, not one a column off '
        'after the …', () async {
      final page = ValueNotifier(0);
      final changes = <int>[];
      final app = await WideApp.start(
        pages(page, 70, changes: changes),
        width: 70,
      );
      expect(
        app.lines().first,
        '« First ‹ Prev [1] 2 3 4 5 … 42 Next › Last »  (1–20 of 840)',
      );
      // the blank after the …, then the 2 of 42
      await app.click(29, 0);
      expect(changes, isEmpty);
      await app.click(31, 0);
      expect(changes, [41]);
      await app.quit();
    });

    test('fits the row as drawn: where the whole row is two columns too '
        'wide, the words of the arrows go', () async {
      const whole =
          '« First ‹ Prev [1] 2 3 4 5 … 42 Next › Last »  (1–20 of 840)';
      final app = await WideApp.start(
        pages(ValueNotifier(0), stringWidth(whole), changes: []),
        width: 70,
      );
      expect(app.lines().first, '« ‹ [1] 2 3 4 5 … 42 › »  (1–20 of 840)');
      await app.quit();
    });
  });
}
