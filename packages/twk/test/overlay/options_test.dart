// OptionList: the highlighted row's ▎, the thumb while not all rows show,
// and neither when turned off; the mouse: hover highlights, a click
// chooses, the wheel moves the highlight.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

const ThemeData dark = ThemeData.dark;

const fruit = [
  Option('apple'),
  Option('banana', detail: 'b'),
  Option('cherry'),
  Option('date'),
];

/// An OptionList of [fruit] the mouse moves the highlight in; what was
/// chosen goes to [chosen].
final class Picker extends StatefulWidget {
  const Picker({required this.chosen, this.rows = 8, super.key});

  final List<int> chosen;
  final int rows;

  @override
  State<Picker> createState() => _PickerState();
}

final class _PickerState extends State<Picker> {
  var _highlighted = 0;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: OptionList(
      options: fruit,
      highlighted: _highlighted,
      rows: widget.rows,
      onHighlight: (i) => setState(() => _highlighted = i),
      onSelected: widget.chosen.add,
    ),
  );
}

Widget themed(Widget child) => Theme(data: dark, child: child);

void main() {
  testTwk('the highlighted row is on the selection with a primary ▎ in its '
      'first column', (t) async {
    await t.pumpWidget(
      themed(
        const Align(
          alignment: Alignment.topLeft,
          child: OptionList(options: fruit, highlighted: 1),
        ),
      ),
      size: (14, 5),
    );
    expect(
      t,
      matchesScreen('''
 apple
▎banana  b
 cherry
 date'''),
    );
    expect(
      t,
      styleAt(0, 1, allOf(hasFg(dark.primary.fg!), hasBg(dark.selection.bg!))),
    );
    expect(t, styleAt(5, 1, hasBg(dark.selection.bg!)));
    expect(t, styleAt(0, 0, hasBg(dark.surface.bg!)));
  });

  testTwk('while not all rows show, a thumb in the border color says where '
      'those shown are', (t) async {
    await t.pumpWidget(
      themed(
        const Align(
          alignment: Alignment.topLeft,
          child: OptionList(options: fruit, highlighted: 3, rows: 2),
        ),
      ),
      size: (14, 3),
    );
    expect(
      t,
      matchesScreen('''
 cherry
▎date     ▐'''),
    );
    expect(t, styleAt(10, 1, hasFg(dark.border.fg!)));
    expect(t, styleAt(10, 1, hasBg(dark.selection.bg!)));
  });

  testTwk('without the bar and the thumb the highlighted row has no mark '
      'and no column shows where the rows are', (
    t,
  ) async {
    await t.pumpWidget(
      themed(
        const Align(
          alignment: Alignment.topLeft,
          child: OptionList(
            options: fruit,
            highlighted: 3,
            rows: 2,
            bar: false,
            thumb: false,
          ),
        ),
      ),
      size: (14, 3),
    );
    expect(t, matchesScreen(' cherry\n date'));
  });

  testTwk('the mouse moved onto a row highlights it, a click chooses it, '
      'the wheel moves the highlight', (t) async {
    final chosen = <int>[];
    await t.pumpWidget(themed(Picker(chosen: chosen)), size: (14, 5));
    await t.mouse(MouseKind.move, 3, 2);
    await t.pump();
    expect(t, hasTextAt(0, 2, '▎cherry'));
    expect(t, styleAt(3, 2, hasBg(dark.selection.bg!)));
    await t.mouse(MouseKind.wheelDown, 3, 2);
    await t.pump();
    expect(t, hasTextAt(0, 3, '▎date'));
    await t.mouse(MouseKind.wheelDown, 3, 2);
    await t.pump();
    expect(t, hasTextAt(0, 3, '▎date'));
    await t.mouse(MouseKind.wheelUp, 3, 2);
    await t.pump();
    await t.mouse(MouseKind.wheelUp, 3, 2);
    await t.pump();
    expect(t, hasTextAt(0, 1, '▎banana'));
    await t.mouse(MouseKind.down, 2, 0);
    await t.mouse(MouseKind.up, 2, 0);
    await t.pump();
    expect(chosen, [0]);
    // pressed on one row and released on another chooses none
    await t.mouse(MouseKind.down, 2, 0);
    await t.mouse(MouseKind.up, 2, 3);
    await t.pump();
    expect(chosen, [0]);
  });

  testTwk('the mouse finds the row shown, the list moved on', (t) async {
    final chosen = <int>[];
    await t.pumpWidget(themed(Picker(chosen: chosen, rows: 2)), size: (14, 3));
    await t.mouse(MouseKind.wheelDown, 1, 0);
    await t.pump();
    await t.mouse(MouseKind.wheelDown, 1, 0);
    await t.pump();
    expect(t, matchesScreen(' banana  b\n▎cherry   ▐'));
    await t.mouse(MouseKind.down, 1, 0);
    await t.mouse(MouseKind.up, 1, 0);
    await t.pump();
    expect(chosen, [1]);
  });

  test('options of the same label, marks and detail are equal, with equal '
      'hashes', () {
    const a = Option('Open file', marks: [0, 5], detail: 'ctrl+o');
    final b = Option('Open file', marks: [0, 5].toList(), detail: 'ctrl+o');
    expect(b, a);
    expect(b.hashCode, a.hashCode);
    expect(const Option('Open file', marks: [0], detail: 'ctrl+o'), isNot(a));
    expect(const Option('Open file', marks: [0, 5]), isNot(a));
  });

  testTwk('built with fewer rows, or without its thumb, the list shows them '
      'at once; with fewer options than it showed, it lists them from the '
      'first', (t) async {
    Widget list(List<Option> options, {int rows = 4, bool thumb = true}) =>
        themed(
          Align(
            alignment: Alignment.topLeft,
            child: OptionList(
              options: options,
              highlighted: options.length - 1,
              rows: rows,
              thumb: thumb,
            ),
          ),
        );
    await t.pumpWidget(list(fruit), size: (14, 5));
    expect(t.lines.take(4), [' apple', ' banana  b', ' cherry', '▎date']);
    await t.pumpWidget(list(fruit, rows: 2));
    expect(t.lines.take(3), [' cherry', '▎date     ▐', '']);
    await t.pumpWidget(list(fruit, rows: 2, thumb: false));
    expect(t.lines.take(2), [' cherry', '▎date']);
    await t.pumpWidget(list(fruit.take(1).toList(), rows: 2));
    expect(t.lines.take(2), ['▎apple', '']);
  });

  testTwk('its intrinsic width is that of its widest row, its height that '
      'of the rows it shows', (t) async {
    await t.pumpWidget(
      themed(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntrinsicWidth(
              child: IntrinsicHeight(
                child: OptionList(options: fruit, rows: 3),
              ),
            ),
            Text('end'),
          ],
        ),
      ),
      size: (20, 5),
    );
    final rect = t.rect(find.byType(OptionList));
    expect((rect.width, rect.height), (11, 3));
    expect(t.lines[3], 'end');
  });
}
