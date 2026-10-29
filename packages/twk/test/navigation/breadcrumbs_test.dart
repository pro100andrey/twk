// Breadcrumbs: the path on one row, the links in the primary color, the
// current one bold; the middle collapsed into … at narrower widths,
// keeping the leading ones and as many of the last as fit, then the
// leading ones too, then the last cut off; one stop of Tab whose arrows,
// Home and End move a highlight and Enter selects; a menu of the hidden
// ones from the …; clicks and the hover; crumbs shown only; a current one
// in the middle; read as a list of links; where │ and … are two columns
// wide.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

import '../text/ambiguous.dart';

const path = ['Root', 'Projects', 'my_app', 'lib', 'src', 'widgets'];

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

/// The crumbs of [items] [width] columns wide in an overlay, each one
/// selected added to [selected], then a button to move the focus to.
Widget crumbs(
  int width, {
  List<int>? selected,
  List<String> items = path,
  int? current,
  int keepLeading = 1,
  bool enabled = true,
  FocusNode? focusNode,
}) => Overlay(
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: width,
        child: Breadcrumbs(
          items: items,
          current: current,
          keepLeading: keepLeading,
          focusNode: focusNode,
          onSelected: enabled ? (i) => selected?.add(i) : null,
        ),
      ),
      Button(
        'next',
        focusNode: FocusNode(debugLabel: 'next'),
        onPressed: () {},
      ),
    ],
  ),
);

void main() {
  testTwk('the whole path where it fits, the links in the primary color, '
      'the current one bold, the separators muted', (t) async {
    await t.pumpWidget(Theme.terminal(child: crumbs(50)), size: (50, 8));
    expect(t.lines.first, 'Root › Projects › my_app › lib › src › widgets');
    expect(
      t,
      styleAt(0, 0, allOf(hasFg(Color.blue), isNot(hasAttr(Attr.bold)))),
    );
    expect(t, styleAt(5, 0, hasFg(const Color.indexed(245))));
    expect(
      t,
      styleAt(40, 0, allOf(hasAttr(Attr.bold), isNot(hasFg(Color.blue)))),
    );
  });

  testTwk('the middle collapsed into … from the inside out, the leading ones '
      'kept and as many of the last as fit; then the leading ones go, then '
      'the last is cut off', (t) async {
    final shown = <int, String>{};
    for (final width in [46, 45, 30, 25, 18, 12, 8]) {
      await t.pumpWidget(Theme.terminal(child: crumbs(width)), size: (50, 8));
      shown[width] = t.lines.first.trimRight();
    }
    expect(shown, {
      46: 'Root › Projects › my_app › lib › src › widgets',
      45: 'Root › … › my_app › lib › src › widgets',
      30: 'Root › … › lib › src › widgets',
      25: 'Root › … › src › widgets',
      18: 'Root › … › widgets',
      12: '… › widgets',
      8: '… › wid…',
    });
    await t.pumpWidget(
      Theme.terminal(child: crumbs(30, keepLeading: 2)),
      size: (50, 8),
    );
    expect(t.lines.first.trimRight(), 'Root › Projects › … › widgets');
  });

  testTwk('one stop of Tab, at first the crumb before the current one '
      'highlighted; Left and Right move it over the links and the …, not '
      'round, Home and End; Enter selects; hinted', (t) async {
    final selected = <int>[];
    final node = FocusNode(debugLabel: 'crumbs');
    addTearDown(node.dispose);
    // Root › … › src › widgets
    await t.pumpWidget(
      Theme.terminal(
        child: crumbs(25, selected: selected, focusNode: node),
      ),
      size: (50, 8),
    );
    await press(t, 'tab');
    expect(focused(t), 'crumbs');
    expect(hints(t), ['left previous', 'right next', 'enter open']);
    expect(t, styleAt(11, 0, hasBg(const Color.indexed(237))));
    await press(t, 'left');
    expect(t, styleAt(7, 0, hasBg(const Color.indexed(237))));
    expect(t, styleAt(11, 0, isNot(hasBg(const Color.indexed(237)))));
    await press(t, 'left left');
    expect(t, styleAt(0, 0, hasBg(const Color.indexed(237))));
    await press(t, 'enter');
    expect(selected, [0]);
    // the current one is no stop
    await press(t, 'end right');
    expect(t, styleAt(11, 0, hasBg(const Color.indexed(237))));
    expect(t, styleAt(17, 0, isNot(hasBg(const Color.indexed(237)))));
    await press(t, 'enter home');
    expect(selected, [0, 4]);
    expect(t, styleAt(0, 0, hasBg(const Color.indexed(237))));
    await press(t, 'tab');
    expect(focused(t), 'next');
    expect(t, styleAt(0, 0, isNot(hasBg(const Color.indexed(237)))));
  });

  testTwk('the hidden cursor rests on the highlighted crumb as it moves', (
    t,
  ) async {
    final node = FocusNode(debugLabel: 'crumbs');
    addTearDown(node.dispose);
    // Root › … › src › widgets
    await t.pumpWidget(
      Theme.terminal(child: crumbs(25, focusNode: node)),
      size: (50, 8),
    );
    node.requestFocus();
    await t.pump();
    expect(t.cursorVisible, isFalse);
    expect(t.cursor, (11, 0));
    await press(t, 'left');
    expect(t.cursor, (7, 0));
    await press(t, 'home');
    expect(t.cursor, (0, 0));
    await press(t, 'tab');
    expect(focused(t), 'next');
    expect(t.cursor, (0, 1));
  });

  testTwk('Enter on the … opens a menu of the items it hides under the row, '
      'the first highlighted, whose items select them', (t) async {
    final selected = <int>[];
    final node = FocusNode(debugLabel: 'crumbs');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: crumbs(25, selected: selected, focusNode: node),
      ),
      size: (50, 8),
    );
    node.requestFocus();
    await t.pump();
    await press(t, 'left enter');
    // the menu fades in
    await t.pump(const Duration(milliseconds: 100));
    final menu = t.lines.skip(1).take(5).join('\n');
    expect(menu, contains('Projects'));
    expect(menu, contains('my_app'));
    expect(menu, contains('lib'));
    expect(menu, isNot(contains('Root')));
    await press(t, 'down enter');
    expect(selected, [2]);
    expect(t.lines.skip(1).join('\n'), isNot(contains('Projects')));
  });

  testTwk('a click selects a link and focuses the row; one on the … opens '
      'the menu under it; the current one and the separators do nothing', (
    t,
  ) async {
    final selected = <int>[];
    final node = FocusNode(debugLabel: 'crumbs');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: crumbs(25, selected: selected, focusNode: node),
      ),
      size: (50, 8),
    );
    for (final x in [4, 5, 9, 17, 23]) {
      await click(t, x, 0);
    }
    expect(selected, isEmpty);
    await click(t, 12, 0);
    expect(selected, [4]);
    expect(focused(t), 'crumbs');
    await click(t, 7, 0);
    await t.pump(const Duration(milliseconds: 100));
    final rows = t.lines.skip(1).take(6).toList();
    final at = rows.indexWhere((r) => r.contains('my_app'));
    expect(at, isNot(-1));
    expect(rows[at].indexOf('my_app'), greaterThanOrEqualTo(7));
    await click(t, rows[at].indexOf('my_app'), at + 1);
    expect(selected, [4, 2]);
  });

  testTwk('the mouse over a link underlines it, not the current one', (
    t,
  ) async {
    await t.pumpWidget(Theme.terminal(child: crumbs(25)), size: (50, 8));
    await t.mouse(MouseKind.move, 1, 0);
    await t.pump();
    expect(t, styleAt(0, 0, hasAttr(Attr.underline)));
    await t.mouse(MouseKind.move, 19, 0);
    await t.pump();
    expect(t, styleAt(0, 0, isNot(hasAttr(Attr.underline))));
    expect(t, styleAt(19, 0, isNot(hasAttr(Attr.underline))));
  });

  testTwk('without onSelected the crumbs are shown only: in the text color, '
      'the current one bold, taking neither the focus nor the mouse', (
    t,
  ) async {
    final node = FocusNode(debugLabel: 'crumbs');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(child: crumbs(25, enabled: false, focusNode: node)),
      size: (50, 8),
    );
    expect(t.lines.first.trimRight(), 'Root › … › src › widgets');
    expect(t, styleAt(0, 0, isNot(hasFg(Color.blue))));
    expect(t, styleAt(17, 0, hasAttr(Attr.bold)));
    await click(t, 7, 0);
    expect(t.lines.skip(1).join('\n'), isNot(contains('Projects')));
    await press(t, 'tab');
    expect(focused(t), 'next');
  });

  testTwk('a current one in the middle is bold and no link; those after it '
      'are links', (t) async {
    final selected = <int>[];
    final node = FocusNode(debugLabel: 'crumbs');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: crumbs(50, selected: selected, current: 2, focusNode: node),
      ),
      size: (50, 8),
    );
    // Root › Projects › my_app › lib › src › widgets
    expect(
      t,
      styleAt(18, 0, allOf(hasAttr(Attr.bold), isNot(hasFg(Color.blue)))),
    );
    expect(t, styleAt(40, 0, hasFg(Color.blue)));
    node.requestFocus();
    await t.pump();
    expect(t, styleAt(7, 0, hasBg(const Color.indexed(237))));
    await press(t, 'right');
    expect(t, styleAt(27, 0, hasBg(const Color.indexed(237))));
    await click(t, 18, 0);
    expect(selected, isEmpty);
    await click(t, 40, 0);
    expect(selected, [5]);
  });

  testTwk('read as a list of every item, the hidden ones too, links but the '
      'current one; the highlighted one focused', (t) async {
    final node = FocusNode(debugLabel: 'crumbs');
    addTearDown(node.dispose);
    await t.pumpWidget(
      Theme.terminal(
        child: crumbs(25, selected: [], focusNode: node),
      ),
      size: (50, 8),
    );
    node.requestFocus();
    await t.pump();
    final lines = t.binding.semantics.lines;
    expect(lines.take(7), [
      'list',
      'link Root',
      'link Projects',
      'link my_app',
      'link lib',
      'link src',
      'listitem widgets, selected',
    ]);
    expect(t.binding.semantics.focusedLine, 5);
    await press(t, 'left');
    expect(t.binding.semantics.focusedLine, 4);
  });

  group('where │ and … are two columns wide (ambiguous width 2)', () {
    test('a click hits the crumb drawn where it is, not one a column off '
        'for each │ before it', () async {
      final selected = <int>[];
      final app = await WideApp.start(
        Breadcrumbs(
          items: path,
          separator: ' │ ',
          onSelected: selected.add,
        ),
      );
      expect(
        app.lines().first,
        'Root │ Projects │ my_app │ lib │ src │ widgets',
      );
      // the blank after the first │, then the last s of Projects
      await app.click(7, 0);
      expect(selected, isEmpty);
      await app.click(15, 0);
      expect(selected, [1]);
      await app.quit();
    });

    test('the path collapsed fits the row, the … two columns', () async {
      final app = await WideApp.start(crumbs(30));
      expect(app.lines().first, 'Root › … › src › widgets');
      await app.quit();
    });
  });
}
