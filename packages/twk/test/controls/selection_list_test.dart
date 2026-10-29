// SelectionList and SelectionController: a single selection that follows
// the cursor, a multiple one that Space and clicks toggle; the keys that
// move the cursor and scroll it into view, passing disabled items by;
// the selection and the cursor staying with their keys as the list
// changes; a hundred thousand items built a window at a time; a disabled
// list out of the focus and the mouse.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

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

/// A list of [names] whose keys are the names, which [names] holds.
Widget names(
  ValueNotifier<List<String>> names, {
  SelectionController<String>? controller,
  FocusNode? node,
  void Function(String key)? onSubmitted,
  bool Function(String name)? disabled,
  bool enabled = true,
  int? itemExtent,
}) => ValueListenableBuilder<List<String>>(
  valueListenable: names,
  builder: (context, list, _) => SelectionList<String>(
    itemCount: list.length,
    keyOf: (i) => list[i],
    itemBuilder: (context, i) => Text(list[i]),
    controller: controller,
    focusNode: node,
    onSubmitted: onSubmitted,
    itemEnabled: disabled == null ? null : (i) => !disabled(list[i]),
    enabled: enabled,
    itemExtent: itemExtent,
  ),
);

List<String> letters(String s) => s.split('');

/// Shows the label it was first built with.
final class First extends StatefulWidget {
  const First(this.label, {super.key});

  final String label;

  @override
  State<First> createState() => _FirstState();
}

final class _FirstState extends State<First> {
  late final String _label = widget.label;

  @override
  Widget build(BuildContext context) => Text(_label);
}

void main() {
  group('SelectionController', () {
    test('a single selection holds one key, a multiple one any number, in '
        'the order selected; each change told once', () {
      final single = SelectionController<int>(selected: [2]);
      var told = 0;
      single
        ..addListener(() => told++)
        ..select(2)
        ..select(3);
      expect(single.selected, {3});
      expect(told, 1);
      single
        ..toggle(3)
        ..toggle(4)
        ..cursor = 4
        ..cursor = 4;
      expect(single.selected, {4});
      expect(single.cursor, 4);
      expect(told, 4);
      var toldMultiple = 0;
      final multiple = SelectionController<int>(multiple: true)
        ..addListener(() => toldMultiple++)
        ..select(5)
        ..select(1)
        ..selectAll([1, 7])
        ..selectAll([7])
        ..deselect(5)
        ..deselect(5);
      expect(multiple.selected.toList(), [1, 7]);
      expect(toldMultiple, 4);
      expect(multiple.isSelected(7), isTrue);
      expect(() => multiple.selected.add(2), throwsUnsupportedError);
      multiple
        ..clear()
        ..clear();
      expect(multiple.selected, isEmpty);
      expect(
        () => SelectionController<int>(selected: [1, 2]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('describes itself by the keys selected and the cursor', () {
      final c = SelectionController<String>(
        multiple: true,
        selected: ['b', 'a'],
        cursor: 'c',
      );
      expect('$c', 'SelectionController({b, a}, cursor c)');
    });
  });

  group('SelectionList', () {
    testTwk('single: Down and Up move the cursor and select its item, the '
        'list scrolling to show it; PageDown and PageUp a window, End and '
        'Home to the ends; Enter submits; the cursor reversed while '
        'focused, a primary bar before it, the selected item bold; '
        'unfocused, the item selected idle, its bar muted', (t) async {
      final list = ValueNotifier([for (var i = 0; i < 20; i++) 'item $i']);
      addTearDown(list.dispose);
      final c = SelectionController<String>();
      addTearDown(c.dispose);
      final node = FocusNode(debugLabel: 'list');
      addTearDown(node.dispose);
      final submitted = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: names(
            list,
            controller: c,
            node: node,
            onSubmitted: submitted.add,
          ),
        ),
        size: (10, 4),
      );
      expect(t.lines, [' item 0', ' item 1', ' item 2', ' item 3']);
      expect(t, styleAt(1, 0, isNot(hasBg(const Color.indexed(237)))));
      node.requestFocus();
      await t.pump();
      // the cursor on the first item, none selected yet
      expect(t.lines.first, '▎item 0');
      expect(
        t,
        styleAt(
          0,
          0,
          allOf(hasBg(const Color.indexed(237)), hasFg(Color.blue)),
        ),
      );
      expect(t, styleAt(1, 0, hasBg(const Color.indexed(237))));
      expect(t, styleAt(9, 0, hasBg(const Color.indexed(237))));
      expect(c.selected, isEmpty);
      await press(t, 'down down down down');
      expect(c.selected, {'item 4'});
      expect(c.cursor, 'item 4');
      expect(t.lines, [' item 1', ' item 2', ' item 3', '▎item 4']);
      expect(
        t,
        styleAt(
          1,
          3,
          allOf(hasBg(const Color.indexed(237)), hasAttr(Attr.bold)),
        ),
      );
      expect(t, styleAt(1, 3, isNot(hasFg(Color.blue))));
      expect(t, styleAt(1, 2, isNot(hasBg(const Color.indexed(237)))));
      await press(t, 'pagedown');
      expect(c.cursor, 'item 8');
      expect(t.lines.last, '▎item 8');
      await press(t, 'end');
      expect(c.selected, {'item 19'});
      expect(t.lines, [' item 16', ' item 17', ' item 18', '▎item 19']);
      await press(t, 'down pageup');
      expect(c.cursor, 'item 15');
      expect(t.lines.first, '▎item 15');
      await press(t, 'enter');
      expect(submitted, ['item 15']);
      await press(t, 'home up');
      expect(c.selected, {'item 0'});
      expect(t.lines.first, '▎item 0');
      node.unfocus();
      await t.pump();
      // the item selected idle (the terminal theme's grey a step nearer
      // the background than its selection), its bar muted
      expect(t.lines.first, '▎item 0');
      expect(
        t,
        styleAt(
          0,
          0,
          allOf(
            hasFg(const Color.indexed(245)),
            hasBg(const Color.indexed(235)),
          ),
        ),
      );
      expect(
        t,
        styleAt(
          1,
          0,
          allOf(hasAttr(Attr.bold), hasBg(const Color.indexed(235))),
        ),
      );
      expect(t, styleAt(1, 1, isNot(hasAttr(Attr.bold))));
      expect(t.lines[1], ' item 1');
    });

    testTwk("in a theme's colors: the selected row on selectionIdle with a "
        'muted bar while the list has not the focus, on selection with a '
        'primary bar while it has', (t) async {
      const dark = ThemeData.dark;
      final list = ValueNotifier(letters('abc'));
      addTearDown(list.dispose);
      final c = SelectionController<String>(selected: ['b']);
      addTearDown(c.dispose);
      final node = FocusNode(debugLabel: 'list');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Theme(
            data: dark,
            child: names(list, controller: c, node: node),
          ),
        ),
        size: (8, 3),
      );
      expect(t.lines, [' a', '▎b', ' c']);
      expect(t.cell(0, 1).fg, dark.muted.fg);
      // the bar not bold as the item selected is
      expect(t, styleAt(0, 1, isNot(hasAttr(Attr.bold))));
      expect(t.cell(1, 1).bg, dark.selectionIdle.bg);
      expect(t.cell(7, 1).bg, dark.selectionIdle.bg);
      expect(t, styleAt(1, 1, hasAttr(Attr.bold)));
      expect(t.cell(1, 1).fg, dark.text.fg);
      expect(t.cell(1, 0).bg, isNot(dark.selectionIdle.bg));
      node.requestFocus();
      await t.pump();
      expect(t.cell(0, 1).fg, dark.primary.fg);
      expect(t.cell(1, 1).bg, dark.selection.bg);
    });

    testTwk('bar, selectedStyle, idleStyle and bracketStyle give a '
        'plain look', (t) async {
      final list = ValueNotifier(letters('abc'));
      addTearDown(list.dispose);
      Widget of(SelectionController<String> c) => ValueListenableBuilder(
        valueListenable: list,
        builder: (context, items, _) => SelectionList<String>(
          itemCount: items.length,
          keyOf: (i) => items[i],
          itemBuilder: (context, i) => Text(items[i]),
          controller: c,
          bar: false,
          selectedStyle: const Style(fg: Color.blue),
          idleStyle: const Style(),
          bracketStyle: const Style(),
        ),
      );
      final single = SelectionController<String>(selected: ['b']);
      addTearDown(single.dispose);
      await t.pumpWidget(Theme.terminal(child: of(single)), size: (8, 3));
      expect(t.lines, ['a', 'b', 'c']);
      expect(
        t,
        styleAt(0, 1, allOf(hasFg(Color.blue), isNot(hasAttr(Attr.bold)))),
      );
      expect(t, styleAt(0, 1, isNot(hasBg(const Color.indexed(237)))));
      final multiple = SelectionController<String>(
        multiple: true,
        selected: ['b'],
      );
      addTearDown(multiple.dispose);
      await t.pumpWidget(Theme.terminal(child: of(multiple)), size: (8, 3));
      expect(t.lines, ['[ ] a', '[x] b', '[ ] c']);
      expect(t, styleAt(0, 1, isNot(hasFg(const Color.indexed(245)))));
    });

    testTwk('single: the cursor starts on the item selected', (t) async {
      final list = ValueNotifier(letters('abcd'));
      addTearDown(list.dispose);
      final c = SelectionController<String>(selected: ['c']);
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: names(
            list,
            controller: c,
            node: FocusNode(debugLabel: 'list'),
          ),
        ),
        size: (8, 4),
      );
      await press(t, 'tab');
      expect(t, styleAt(1, 2, hasBg(const Color.indexed(237))));
      await press(t, 'down');
      expect(c.selected, {'d'});
    });

    testTwk("the hidden cursor rests on the cursor's row as it moves and "
        'the list scrolls', (t) async {
      final list = ValueNotifier([for (var i = 0; i < 10; i++) 'item $i']);
      addTearDown(list.dispose);
      final c = SelectionController<String>(selected: ['item 1']);
      addTearDown(c.dispose);
      final node = FocusNode(debugLabel: 'list');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: names(list, controller: c, node: node),
        ),
        size: (10, 4),
      );
      node.requestFocus();
      await t.pump();
      expect(t.cursorVisible, isFalse);
      expect(t.cursor, (0, 1));
      await press(t, 'down down');
      expect(t.cursor, (0, 3));
      // scrolled: the cursor's row is the last one in view
      await press(t, 'down down');
      expect(t.lines.last, '▎item 5');
      expect(t.cursor, (0, 3));
      await press(t, 'home');
      expect(t.cursor, (0, 0));
    });

    testTwk('the items keep their State by their keys as the list changes', (
      t,
    ) async {
      final list = ValueNotifier(letters('abc'));
      addTearDown(list.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: ValueListenableBuilder<List<String>>(
            valueListenable: list,
            builder: (context, items, _) => SelectionList<String>(
              itemCount: items.length,
              keyOf: (i) => items[i],
              itemBuilder: (context, i) => First(items[i]),
            ),
          ),
        ),
        size: (8, 4),
      );
      expect(t.lines, [' a', ' b', ' c', '']);
      list.value = letters('xcab');
      await t.pump();
      expect(t.lines, [' x', ' c', ' a', ' b']);
    });

    testTwk('a click puts the cursor on an item and selects it, focusing the '
        'list; the wheel scrolls it', (t) async {
      final list = ValueNotifier([for (var i = 0; i < 20; i++) 'item $i']);
      addTearDown(list.dispose);
      final c = SelectionController<String>();
      addTearDown(c.dispose);
      final node = FocusNode(debugLabel: 'list');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: names(list, controller: c, node: node),
        ),
        size: (10, 4),
      );
      await click(t, 2, 2);
      expect(c.selected, {'item 2'});
      expect(focused(t), 'list');
      expect(t, styleAt(1, 2, hasBg(const Color.indexed(237))));
      await t.mouse(MouseKind.wheelDown, 2, 1);
      await t.pump();
      expect(t.lines.first, ' item 3');
      await click(t, 2, 0);
      expect(c.selected, {'item 3'});
      await press(t, 'down');
      expect(c.selected, {'item 4'});
    });

    testTwk('multiple: [x] marks the items selected, [ ] the others; Space '
        "selects or deselects the cursor's item, hinted, as a click does; "
        'moving the cursor selects nothing; the brackets muted, the x '
        'primary and bold', (t) async {
      final list = ValueNotifier(letters('abcde'));
      addTearDown(list.dispose);
      final c = SelectionController<String>(multiple: true, selected: ['b']);
      addTearDown(c.dispose);
      final node = FocusNode(debugLabel: 'list');
      addTearDown(node.dispose);
      var entered = 0;
      await t.pumpWidget(
        Theme.terminal(
          child: KeyBindings(
            {'enter': () => entered++},
            child: names(list, controller: c, node: node),
          ),
        ),
        size: (8, 5),
      );
      expect(t.lines, [' [ ] a', ' [x] b', ' [ ] c', ' [ ] d', ' [ ] e']);
      expect(t, styleAt(2, 1, allOf(hasFg(Color.blue), hasAttr(Attr.bold))));
      expect(t, styleAt(1, 1, hasFg(const Color.indexed(245))));
      expect(t, styleAt(3, 1, hasFg(const Color.indexed(245))));
      // the item selected not bold: its mark says it is
      expect(t, styleAt(5, 1, isNot(hasAttr(Attr.bold))));
      // unfocused, no row stands out
      expect(t, styleAt(5, 1, isNot(hasBg(const Color.indexed(237)))));
      node.requestFocus();
      await t.pump();
      expect(hints(t), ['space toggle']);
      await press(t, 'space');
      expect(c.cursor, 'a');
      await press(t, 'down down space down');
      expect(c.selected, {'b', 'a', 'c'});
      expect(c.cursor, 'd');
      expect(t.lines, [' [x] a', ' [x] b', ' [x] c', '▎[ ] d', ' [ ] e']);
      expect(t, styleAt(1, 3, hasBg(const Color.indexed(237))));
      await click(t, 4, 1);
      await click(t, 4, 4);
      expect(c.selected, {'a', 'c', 'e'});
      expect(c.cursor, 'e');
      await press(t, 'enter');
      expect(c.selected, {'a', 'c', 'e'});
      expect(entered, 1);
    });

    testTwk('the selection and the cursor stay with their keys as items are '
        "added, moved and removed; the cursor's item gone, it goes to the "
        'item at its place', (t) async {
      final list = ValueNotifier(letters('abcde'));
      addTearDown(list.dispose);
      final c = SelectionController<String>(multiple: true);
      addTearDown(c.dispose);
      final node = FocusNode(debugLabel: 'list');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: names(list, controller: c, node: node),
        ),
        size: (8, 6),
      );
      node.requestFocus();
      await t.pump();
      await press(t, 'down space down down space');
      expect(c.selected, {'b', 'd'});
      expect(c.cursor, 'd');
      list.value = letters('xyabcde');
      await t.pump();
      expect(t.lines, [
        ' [ ] x',
        ' [ ] y',
        ' [ ] a',
        ' [x] b',
        ' [ ] c',
        '▎[x] d',
      ]);
      expect(t, styleAt(1, 5, hasBg(const Color.indexed(237))));
      await press(t, 'up');
      expect(c.cursor, 'c');
      list.value = letters('dcbxya');
      await t.pump();
      expect(t.lines, [
        ' [x] d',
        '▎[ ] c',
        ' [x] b',
        ' [ ] x',
        ' [ ] y',
        ' [ ] a',
      ]);
      expect(t, styleAt(1, 1, hasBg(const Color.indexed(237))));
      list.value = letters('dbxya');
      await t.pump();
      // c gone: the cursor on b, now at its place
      expect(t, styleAt(1, 1, hasBg(const Color.indexed(237))));
      await press(t, 'space');
      expect(c.selected, {'d'});
      expect(c.cursor, 'b');
      list.value = letters('d');
      await t.pump();
      expect(t, styleAt(1, 0, hasBg(const Color.indexed(237))));
      await press(t, 'space');
      expect(c.selected, isEmpty);
    });

    testTwk('disabled items are muted, passed by by the keys and deaf to '
        'clicks', (t) async {
      final list = ValueNotifier(letters('abcde'));
      addTearDown(list.dispose);
      final c = SelectionController<String>();
      addTearDown(c.dispose);
      final node = FocusNode(debugLabel: 'list');
      addTearDown(node.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: names(
            list,
            controller: c,
            node: node,
            disabled: (name) => 'acd'.contains(name),
          ),
        ),
        size: (8, 5),
      );
      expect(t, styleAt(1, 0, hasFg(const Color.indexed(245))));
      expect(t, styleAt(1, 1, isNot(hasFg(const Color.indexed(245)))));
      await click(t, 1, 2);
      expect(c.selected, isEmpty);
      node.requestFocus();
      await t.pump();
      // the cursor starts on the first enabled item
      expect(t, styleAt(1, 1, hasBg(const Color.indexed(237))));
      await press(t, 'down');
      expect(c.selected, {'e'});
      await press(t, 'up');
      expect(c.selected, {'b'});
      await press(t, 'up home');
      expect(c.selected, {'b'});
      await press(t, 'end');
      expect(c.selected, {'e'});
      // e gone: the cursor goes back past the disabled items to b
      list.value = letters('abcd');
      await t.pump();
      expect(t, styleAt(1, 1, hasBg(const Color.indexed(237))));
    });

    testTwk('an empty list: the keys do nothing', (t) async {
      final submitted = <String>[];
      final c = SelectionController<String>(multiple: true);
      addTearDown(c.dispose);
      final list = ValueNotifier(<String>[]);
      addTearDown(list.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: names(
            list,
            controller: c,
            node: FocusNode(debugLabel: 'list'),
            onSubmitted: submitted.add,
          ),
        ),
        size: (8, 4),
      );
      await press(t, 'tab down up pagedown home end space enter');
      expect(focused(t), 'list');
      expect(c.selected, isEmpty);
      expect(c.cursor, isNull);
      expect(submitted, isEmpty);
    });

    testTwk('a window down onto disabled items to the end stops at the last '
        'enabled one before them', (t) async {
      final list = ValueNotifier(letters('abcdef'));
      addTearDown(list.dispose);
      final c = SelectionController<String>();
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: names(
            list,
            controller: c,
            node: FocusNode(debugLabel: 'list'),
            disabled: (name) => 'def'.contains(name),
          ),
        ),
        size: (8, 4),
      );
      await press(t, 'tab pagedown');
      expect(c.selected, {'c'});
      await press(t, 'pageup down down');
      expect(c.selected, {'c'});
    });

    testTwk('disabled: passed by by Tab, deaf to clicks', (t) async {
      final list = ValueNotifier(letters('ab'));
      addTearDown(list.dispose);
      final c = SelectionController<String>();
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: Column(
            children: [
              Expanded(
                child: names(
                  list,
                  controller: c,
                  node: FocusNode(debugLabel: 'list'),
                  enabled: false,
                ),
              ),
              const Focus(debugLabel: 'next', child: Text('next')),
            ],
          ),
        ),
        size: (8, 3),
      );
      expect(t, styleAt(1, 0, hasFg(const Color.indexed(245))));
      await press(t, 'tab');
      expect(focused(t), 'next');
      await click(t, 0, 1);
      expect(c.selected, isEmpty);
      expect(focused(t), 'next');
    });

    testTwk('of a hundred thousand items it builds a window at a time; End '
        'goes to the last', (t) async {
      final built = <int>[];
      final c = SelectionController<int>();
      addTearDown(c.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionList<int>(
            itemCount: 100000,
            keyOf: (i) => i,
            itemBuilder: (context, i) {
              built.add(i);
              return Text('item $i');
            },
            itemExtent: 1,
            controller: c,
            autofocus: true,
          ),
        ),
        size: (12, 5),
      );
      expect(built.length, lessThan(20));
      built.clear();
      await press(t, 'end');
      expect(c.selected, {99999});
      expect(t.lines.last, '▎item 99999');
      expect(built.length, lessThan(40));
      // the window it left built again once, as the list is; none between
      expect(built, everyElement(anyOf(lessThan(20), greaterThan(99900))));
    });
  });
}
