// Box(scrollbar:): the bar of the scrollable inside drawn on the box's
// right border between its corners, a heavier line for the thumb, the
// border's own line while there is nothing to scroll; the child keeps all
// the room inside; the thumb dragged scrolls the content.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A column of [count] rows, `item 0` on.
Widget column(int count) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [for (var i = 0; i < count; i++) Text('item $i')],
);

/// The glyphs of column [x], rows 0 to [rows] - 1.
List<String> down(TwkTester t, int x, int rows) => [
  for (var y = 0; y < rows; y++) t.cell(x, y).text,
];

/// A panel of [count] rows in a scroll view, its bar on its border.
Widget panel(int count, {ScrollController? controller}) => Box(
  border: const Border.all(),
  scrollbar: .always,
  child: SingleChildScrollView(controller: controller, child: column(count)),
);

void main() {
  axisTests();
  testTwk('the thumb on the right border, between its corners; the child '
      'keeps the room inside', (t) async {
    await t.pumpWidget(panel(32), size: (20, 10));
    // 8 cells of track inside the corners, 2 of thumb
    expect(down(t, 19, 10), [
      '┐',
      '┃',
      '┃',
      ...List.filled(6, '│'),
      '┘',
    ]);
    expect(t.lines[1], '│item 0            ┃');
    expect(
      t,
      styleAt(
        19,
        1,
        hasFg(const ThemeData.terminal(Brightness.dark).muted.fg!),
      ),
    );
  });

  testTwk("the border's own line while there is nothing to scroll", (
    t,
  ) async {
    await t.pumpWidget(panel(3), size: (20, 10));
    expect(down(t, 19, 10), ['┐', ...List.filled(8, '│'), '┘']);
  });

  testTwk('the thumb dragged scrolls the content', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await t.pumpWidget(panel(32, controller: controller), size: (20, 10));
    await t.mouse(MouseKind.down, 19, 1);
    await t.mouse(MouseKind.drag, 19, 5);
    await t.mouse(MouseKind.up, 19, 5);
    await t.pump();
    expect(controller.offset, greaterThan(0));
    expect(t.lines[1], isNot(contains('item 0')));
  });

  for (final (type, track, thumb, corner, bottom) in [
    (BorderType.double, '║', '┃', '╗', '╝'),
    (BorderType.heavy, '┃', '█', '┓', '┛'),
    (BorderType.ascii, '|', '#', '+', '+'),
  ]) {
    testTwk("a $type border: its own line for the track, the type's thumb", (
      t,
    ) async {
      await t.pumpWidget(
        Box(
          border: Border.all(type: type),
          scrollbar: .always,
          child: SingleChildScrollView(child: column(32)),
        ),
        size: (20, 10),
      );
      expect(down(t, 19, 10), [
        corner,
        thumb,
        thumb,
        ...List.filled(6, track),
        bottom,
      ]);
    });
  }

  testTwk('no background where the box gives none: the parent shows', (
    t,
  ) async {
    const bg = Color.rgb(10, 20, 30);
    await t.pumpWidget(
      Box(
        style: const Style(bg: bg),
        child: panel(32),
      ),
      size: (20, 10),
    );
    expect(t, styleAt(19, 5, hasBg(bg)));
    expect(t, styleAt(19, 1, hasBg(bg)));
  });
}

/// A panel whose scrollable is [axis], its bar on the border.
Widget panelAlong(
  Axis axis, {
  ScrollbarVisibility scrollbar = ScrollbarVisibility.always,
  List<BorderTitle> titles = const [],
  Border border = const Border.all(),
  ScrollController? controller,
}) => Box(
  border: border,
  titles: titles,
  scrollbar: scrollbar,
  child: SingleChildScrollView(
    scrollDirection: axis,
    controller: controller,
    child: axis == Axis.vertical ? column(32) : Text('0123456789' * 6),
  ),
);

/// The glyphs of row [y], columns 0 to [columns] - 1.
List<String> across(TwkTester t, int y, int columns) => [
  for (var x = 0; x < columns; x++) t.cell(x, y).text,
];

void axisTests() {
  testTwk("the axis is the scrollable's: a horizontal one has its bar on "
      'the bottom border, the right side keeps its line', (t) async {
    await t.pumpWidget(panelAlong(Axis.horizontal), size: (20, 6));
    // 18 cells of track inside the corners, 5 of thumb
    expect(across(t, 5, 20), [
      '└',
      ...List.filled(5, '━'),
      ...List.filled(13, '─'),
      '┘',
    ]);
    expect(down(t, 19, 6), ['┐', '│', '│', '│', '│', '┘']);
    expect(t.lines[1], '│012345678901234567│');
  });

  testTwk('a child that turns from vertical to horizontal moves the bar '
      'from the right border to the bottom', (t) async {
    final axis = ValueNotifier(Axis.vertical);
    addTearDown(axis.dispose);
    await t.pumpWidget(
      ValueListenableBuilder<Axis>(
        valueListenable: axis,
        builder: (context, a, _) => panelAlong(a),
      ),
      size: (20, 6),
    );
    expect(down(t, 19, 6)[1], '┃');
    expect(across(t, 5, 20)[1], '─');
    axis.value = Axis.horizontal;
    await t.pump();
    expect(down(t, 19, 6), ['┐', '│', '│', '│', '│', '┘']);
    expect(across(t, 5, 20)[1], '━');
    axis.value = Axis.vertical;
    await t.pump();
    expect(down(t, 19, 6)[1], '┃');
    expect(across(t, 5, 20)[1], '─');
  });

  testTwk('content that scrolls both ways has the bar of the outermost '
      'scrollable, the one inside it of the other axis not taking it', (
    t,
  ) async {
    await t.pumpWidget(
      Box(
        border: const Border.all(),
        scrollbar: ScrollbarVisibility.always,
        child: SingleChildScrollView(
          child: SizedBox(
            height: 40,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text('0123456789' * 6),
            ),
          ),
        ),
      ),
      size: (20, 6),
    );
    expect(down(t, 19, 6)[1], '┃');
    expect(across(t, 5, 20)[1], '─');
  });

  testTwk('a horizontal scrollable first built while the child is laid '
      'out (in a LayoutBuilder): its bar on the bottom border in the first '
      'frame', (t) async {
    await t.pumpWidget(
      Box(
        border: const Border.all(),
        scrollbar: ScrollbarVisibility.always,
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text('0123456789' * 6),
          ),
        ),
      ),
      size: (20, 6),
    );
    expect(across(t, 5, 20)[1], '━');
    expect(down(t, 19, 6), ['┐', '│', '│', '│', '│', '┘']);
  });

  testTwk("onScroll: the border's own line while the thumb is hidden, the "
      'thumb from a move until hideAfter after it', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      panelAlong(
        Axis.vertical,
        scrollbar: ScrollbarVisibility.onScroll,
        controller: controller,
      ),
      size: (20, 10),
    );
    expect(down(t, 19, 10), ['┐', ...List.filled(8, '│'), '┘']);
    controller.jumpTo(4);
    await t.pump();
    expect(down(t, 19, 10).where((g) => g == '┃'), isNotEmpty);
    await t.pump(const Duration(milliseconds: 900));
    expect(down(t, 19, 10).where((g) => g == '┃'), isNotEmpty);
    await t.pump(const Duration(milliseconds: 200));
    expect(down(t, 19, 10), ['┐', ...List.filled(8, '│'), '┘']);
  });

  testTwk('never: no bar, the border as it is', (t) async {
    await t.pumpWidget(
      panelAlong(Axis.vertical, scrollbar: ScrollbarVisibility.never),
      size: (20, 10),
    );
    expect(down(t, 19, 10), ['┐', ...List.filled(8, '│'), '┘']);
  });

  testTwk("no scrollable inside: the border's line, nothing to scroll", (
    t,
  ) async {
    await t.pumpWidget(
      const Box(
        border: Border.all(),
        scrollbar: ScrollbarVisibility.always,
        child: Text('plain'),
      ),
      size: (20, 6),
    );
    expect(down(t, 19, 6), ['┐', '│', '│', '│', '│', '┘']);
    expect(across(t, 5, 20), ['└', ...List.filled(18, '─'), '┘']);
  });

  testTwk('a horizontal scrollable and a bottom title: asserted', (t) async {
    await t.pumpWidget(
      panelAlong(
        Axis.horizontal,
        titles: const [BorderTitle(' 12 ', alignment: Alignment.bottomRight)],
      ),
      size: (20, 6),
    );
    expect(t.lines.join(), contains('Failed assertion'));
  });

  testTwk('a vertical scrollable and a bottom title: the bar on the right '
      'and the title where it is', (t) async {
    await t.pumpWidget(
      panelAlong(
        Axis.vertical,
        titles: const [BorderTitle(' 12 ', alignment: Alignment.bottomRight)],
      ),
      size: (20, 10),
    );
    expect(t.lines.join(), isNot(contains('Failed assertion')));
    expect(t.lines[9], contains(' 12 '));
  });

  testTwk('a scrollable whose side the border has not: asserted', (t) async {
    await t.pumpWidget(
      panelAlong(
        Axis.vertical,
        border: const Border(left: Style(), top: Style(), bottom: Style()),
      ),
      size: (20, 10),
    );
    expect(t.lines.join(), contains('Failed assertion'));
  });

  testTwk('a bar without a border: asserted', (t) async {
    await t.pumpWidget(
      Box(
        scrollbar: ScrollbarVisibility.always,
        child: SingleChildScrollView(child: column(32)),
      ),
      size: (20, 10),
    );
    expect(t.lines.join(), contains('Failed assertion'));
  });
}
