// A Scrollbar in an app: its thumb as long and as far along as the window
// is of the content, in eighths of a cell, exactly at the ends; dragged and
// its track pressed with the mouse; shown always, while it scrolls or never;
// the scrollable it takes among those inside it; over a ListView of a
// hundred thousand items.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A column of [count] rows, `item 0` on.
Widget column(int count) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [for (var i = 0; i < count; i++) Text('item $i')],
);

/// A cell as text: its glyph, after `~` when it is in reverse video.
String cellText(VtCell cell) =>
    '${cell.attrs & Attr.reverse != 0 ? '~' : ''}${cell.text}';

/// The cells of column [x], rows 0 to [rows] - 1.
List<String> down(TwkTester t, int x, int rows) => [
  for (var y = 0; y < rows; y++) cellText(t.cell(x, y)),
];

/// The cells of row [y], columns 0 to [columns] - 1.
List<String> across(TwkTester t, int y, int columns) => [
  for (var x = 0; x < columns; x++) cellText(t.cell(x, y)),
];

/// [blank] cells of the track, then [cells].
List<String> track(int blank, [List<String> cells = const []]) => [
  for (var i = 0; i < blank; i++) ' ',
  ...cells,
];

/// [n] cells of the thumb.
List<String> thumb(int n) => [for (var i = 0; i < n; i++) '~ '];

void main() {
  group('slim', () {
    testTwk('a thin line at rest, the thumb a heavy one in whole cells; the '
        'whole cell in eighths while the mouse is over the bar, a line '
        'again once it leaves', (t) async {
      await t.pumpWidget(
        Scrollbar(
          slim: true,
          child: SingleChildScrollView(child: column(30)),
        ),
        size: (20, 10),
      );
      // 10 cells of track, 3 of thumb
      expect(down(t, 19, 10), [...List.filled(3, '┃'), ...List.filled(7, '│')]);
      expect(
        t,
        styleAt(
          19,
          5,
          hasFg(const ThemeData.terminal(Brightness.dark).faint.fg!),
        ),
      );
      await t.mouse(MouseKind.move, 19, 5);
      await t.pump();
      // the thumb wide over the line, which stays
      expect(down(t, 19, 10), [...thumb(3), '~▅', ...List.filled(6, '│')]);
      await t.mouse(MouseKind.move, 5, 5);
      await t.pump();
      expect(down(t, 19, 10), [...List.filled(3, '┃'), ...List.filled(7, '│')]);
    });

    testTwk("the track's line in trackStyle", (t) async {
      await t.pumpWidget(
        Scrollbar(
          slim: true,
          trackStyle: const Style(fg: Color.red),
          child: SingleChildScrollView(child: column(30)),
        ),
        size: (20, 10),
      );
      expect(t, styleAt(19, 5, hasFg(Color.red)));
    });

    testTwk('wide while its thumb is dragged, the mouse off the bar', (
      t,
    ) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          slim: true,
          child: SingleChildScrollView(
            controller: controller,
            child: column(30),
          ),
        ),
        size: (20, 10),
      );
      await t.mouse(MouseKind.move, 19, 1);
      await t.mouse(MouseKind.down, 19, 1);
      await t.mouse(MouseKind.drag, 10, 4);
      await t.pump();
      expect(controller.offset, greaterThan(0));
      expect(down(t, 19, 10).where((c) => c.startsWith('~')), isNotEmpty);
      // the release off the bar: slim again, without a move after it
      await t.mouse(MouseKind.up, 10, 4);
      await t.pump();
      expect(down(t, 19, 10), everyElement(isIn(['┃', '│'])));
      await t.mouse(MouseKind.move, 9, 4);
      await t.pump();
      expect(down(t, 19, 10), everyElement(isIn(['┃', '│'])));
    });
  });

  testTwk('slim again after it was not, with the mouse gone from the bar '
      'meanwhile: a line, not wide', (t) async {
    final slim = ValueNotifier(true);
    addTearDown(slim.dispose);
    await t.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: slim,
        builder: (context, on, _) => Scrollbar(
          slim: on,
          child: SingleChildScrollView(child: column(30)),
        ),
      ),
      size: (20, 10),
    );
    await t.mouse(MouseKind.move, 19, 5);
    await t.pump();
    expect(down(t, 19, 10).where((c) => c.startsWith('~')), isNotEmpty);
    slim.value = false;
    await t.pump();
    await t.mouse(MouseKind.move, 5, 5);
    await t.pump();
    slim.value = true;
    await t.pump();
    expect(down(t, 19, 10), [...List.filled(3, '┃'), ...List.filled(7, '│')]);
  });

  group('the thumb', () {
    testTwk('is as long as the window is of the content and as far along '
        'the track, in eighths of a cell: at its start at the start, at its '
        'end at the end', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: SingleChildScrollView(
            controller: controller,
            child: column(30),
          ),
        ),
        size: (20, 10),
      );
      // 80 eighths of track, 27 of thumb, 53 of room
      expect(down(t, 19, 10), [...thumb(3), '~▅', ...track(6)]);
      expect(t.lines.first, 'item 0');
      controller.jumpTo(10);
      await t.pump();
      expect(down(t, 19, 10), [
        ...track(3),
        '▅',
        ...thumb(2),
        '~▂',
        ...track(3),
      ]);
      controller.jumpTo(20);
      await t.pump();
      expect(down(t, 19, 10), [...track(6), '▃', ...thumb(3)]);
      expect(t.lines.last, 'item 29');
    });

    testTwk('is a cell at least', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: SingleChildScrollView(
            controller: controller,
            child: column(200),
          ),
        ),
        size: (20, 10),
      );
      expect(down(t, 19, 10), [...thumb(1), ...track(9)]);
      controller.jumpTo(95);
      await t.pump();
      expect(down(t, 19, 10), [...track(4), '▄', '~▄', ...track(4)]);
      controller.jumpTo(190);
      await t.pump();
      expect(down(t, 19, 10), [...track(9), ...thumb(1)]);
    });

    testTwk('along a horizontal axis is in a row below the child, from the '
        'left', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          axis: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: controller,
            child: Text('0123456789' * 4),
          ),
        ),
        size: (10, 2),
      );
      expect(t.lines.first, '0123456789');
      // 80 eighths of track, 20 of thumb, 60 of room
      expect(across(t, 1, 10), [...thumb(2), '▌', ...track(7)]);
      controller.jumpTo(15);
      await t.pump();
      expect(across(t, 1, 10), [
        ...track(3),
        '~▊',
        ...thumb(2),
        '▎',
        ...track(3),
      ]);
      controller.jumpTo(30);
      await t.pump();
      expect(across(t, 1, 10), [...track(7), '~▌', ...thumb(2)]);
    });

    testTwk('is drawn in the style, over the muted text and the background '
        'of the theme', (t) async {
      const thumbColor = Color.rgb(200, 0, 0);
      const trackColor = Color.rgb(0, 0, 200);
      await t.pumpWidget(
        Theme(
          data: ThemeData.dark,
          child: Row(
            children: [
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(child: column(30)),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  style: const Style(fg: thumbColor, bg: trackColor),
                  child: SingleChildScrollView(child: column(30)),
                ),
              ),
            ],
          ),
        ),
        size: (20, 10),
      );
      final muted = ThemeData.dark.muted.fg!;
      final background = ThemeData.dark.background.bg!;
      // in reverse video: the thumb's color is the background
      expect(t, styleAt(9, 0, allOf(hasFg(muted), hasBg(background))));
      expect(t, styleAt(9, 0, hasAttr(Attr.reverse)));
      expect(t, styleAt(9, 9, hasBg(background)));
      expect(t, styleAt(19, 0, allOf(hasFg(thumbColor), hasBg(trackColor))));
      expect(t, styleAt(19, 9, hasBg(trackColor)));
    });

    testTwk('shows the position of the outermost scrollable inside along '
        'its axis: one inside that one along the same axis is not shown, '
        'one along the other axis is to a scrollbar of that axis', (
      t,
    ) async {
      final outer = ScrollController();
      final inner = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: SingleChildScrollView(
            controller: outer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 4,
                  child: SingleChildScrollView(
                    controller: inner,
                    child: column(40),
                  ),
                ),
                column(16),
              ],
            ),
          ),
        ),
        size: (20, 10),
      );
      // 20 rows in 10: half the track
      expect(down(t, 19, 10), [...thumb(5), ...track(5)]);
      inner.jumpTo(36);
      await t.pump();
      expect(down(t, 19, 10), [...thumb(5), ...track(5)]);
      outer.jumpTo(10);
      await t.pump();
      expect(down(t, 19, 10), [...track(5), ...thumb(5)]);

      final h = ScrollController();
      final v = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          axis: Axis.horizontal,
          child: Scrollbar(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: h,
              child: SizedBox(
                width: 40,
                child: SingleChildScrollView(
                  controller: v,
                  child: column(36),
                ),
              ),
            ),
          ),
        ),
      );
      // the vertical bar in column 19 of rows 0 to 8, the horizontal one in
      // row 9; 9 rows of 36, 19 columns of 40
      expect(down(t, 19, 9), [...thumb(2), '~▆', ...track(6)]);
      expect(across(t, 9, 20), [...thumb(9), '▌', ...track(10)]);
      v.jumpTo(27);
      h.jumpTo(21);
      await t.pump();
      expect(down(t, 19, 9), [...track(6), '▂', ...thumb(2)]);
      expect(across(t, 9, 20), [...track(10), '~▌', ...thumb(9)]);
    });

    testTwk('follows the scrollable inside as it comes and goes', (t) async {
      Widget bar({required bool scrolls}) => Scrollbar(
        child: scrolls
            ? SingleChildScrollView(child: column(20))
            : const Text('none'),
      );
      await t.pumpWidget(bar(scrolls: true), size: (20, 10));
      expect(down(t, 19, 10), [...thumb(5), ...track(5)]);
      await t.pumpWidget(bar(scrolls: false));
      expect(down(t, 19, 10), track(10));
      await t.pumpWidget(bar(scrolls: true));
      expect(down(t, 19, 10), [...thumb(5), ...track(5)]);
    });

    testTwk('a move that leaves the thumb where it is does not paint it, a '
        'repaint boundary', (t) async {
      final list = ListController();
      await t.pumpWidget(
        Scrollbar(
          child: ListView.builder(
            itemCount: 1000,
            controller: list,
            autofocus: true,
            itemBuilder: (context, index) => Text('item $index'),
          ),
        ),
        size: (20, 10),
      );
      await t.press('down');
      await t.pump();
      expect(t.lines.first, 'item 1');
      expect(t.binding.twkApp.stats.lastRepaints, 1);
      list.jumpToIndex(500);
      await t.pump();
      await t.pump();
      expect(t.lines.first, 'item 500');
      expect(t.binding.twkApp.stats.lastRepaints, 2);
      expect(down(t, 19, 10), [...track(4), '▄', '~▄', ...track(4)]);
    });

    testTwk('a thumb hidden repaints the bar alone', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          visibility: ScrollbarVisibility.onScroll,
          hideAfter: const Duration(milliseconds: 100),
          child: SingleChildScrollView(
            controller: controller,
            child: column(30),
          ),
        ),
        size: (20, 10),
      );
      t.binding.debug.rainbow = true;
      controller.jumpTo(10);
      await t.pump();
      // the repaint rainbow tints what repaints
      final content = t.cell(2, 2).bg;
      final bar = t.cell(19, 0).bg;
      await t.pump(const Duration(milliseconds: 200));
      expect(down(t, 19, 10), track(10));
      expect(t.cell(2, 2).bg, content);
      expect(t.cell(19, 0).bg, isNot(bar));
    });
  });

  group('the mouse', () {
    testTwk('dragging the thumb scrolls the content as far as the thumb '
        'moves, wherever the mouse goes until the release', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: SingleChildScrollView(
            controller: controller,
            child: column(30),
          ),
        ),
        size: (20, 10),
      );
      await t.mouse(MouseKind.down, 19, 1);
      final offsets = <int>[];
      for (final (x, y) in [(19, 2), (5, 4), (0, 9), (19, 0), (12, 3)]) {
        await t.mouse(MouseKind.drag, x, y);
        offsets.add(controller.offset);
      }
      // 20 cells of content to 53 eighths of room
      expect(offsets, [3, 9, 20, 0, 6]);
      await t.mouse(MouseKind.drag, 19, 4);
      await t.pump();
      expect(controller.offset, 9);
      // the thumb moved three cells, as the mouse did
      expect(down(t, 19, 10), [...track(3), ...thumb(3), '~▅', ...track(3)]);
      await t.mouse(MouseKind.up, 19, 4);
      await t.mouse(MouseKind.drag, 19, 8);
      await t.mouse(MouseKind.move, 19, 9);
      expect(controller.offset, 9);
      expect(t.lines.first, 'item 9');
    });

    testTwk('pressing the track before or after the thumb scrolls a window '
        'that way; on the thumb, or with another button, it does not', (
      t,
    ) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: SingleChildScrollView(
            controller: controller,
            child: column(30),
          ),
        ),
        size: (20, 10),
      );
      final offsets = <int>[];
      for (final y in [7, 3, 1, 9, 9, 6, 0]) {
        await t.click(19, y);
        offsets.add(controller.offset);
      }
      expect(offsets, [10, 10, 0, 10, 20, 20, 10]);
      await t.click(19, 9, button: 2);
      expect(controller.offset, 10);
    });

    testTwk('a press of the bar is its own: a GestureDetector around it '
        'gets nothing of it', (t) async {
      var taps = 0;
      final controller = ScrollController();
      await t.pumpWidget(
        GestureDetector(
          onTap: (_) => taps++,
          child: Scrollbar(
            child: SingleChildScrollView(
              controller: controller,
              child: column(30),
            ),
          ),
        ),
        size: (20, 10),
      );
      await t.click(19, 8);
      await t.click(19, 4);
      expect((taps, controller.offset), (0, 10));
      await t.click(4, 1);
      expect(taps, 1);
    });

    testTwk('the wheel over the bar scrolls the scrollable', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          child: SingleChildScrollView(
            controller: controller,
            child: column(30),
          ),
        ),
        size: (20, 10),
      );
      await t.mouse(MouseKind.wheelDown, 19, 5);
      await t.mouse(MouseKind.wheelDown, 19, 5);
      await t.mouse(MouseKind.wheelUp, 19, 5);
      expect(controller.offset, 3);
    });

    testTwk('the wheel across over the bar of a list down goes to the view '
        'across around it', (t) async {
      final list = ScrollController();
      final view = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          controller: view,
          child: SizedBox(
            width: 40,
            child: Scrollbar(
              child: SingleChildScrollView(
                controller: list,
                child: column(30),
              ),
            ),
          ),
        ),
        size: (20, 10),
      );
      // the bar at the view's column 39: scrolled into the window first
      view.jumpTo(20);
      await t.pump();
      await t.mouse(MouseKind.wheelDown, 19, 5);
      expect((view.offset, list.offset), (20, 3));
      await t.mouse(MouseKind.wheelLeft, 19, 5);
      expect((view.offset, list.offset), (17, 3));
    });
  });

  group('visibility', () {
    testTwk('always: the track, and the thumb while there is something to '
        'scroll', (t) async {
      await t.pumpWidget(
        Scrollbar(child: SingleChildScrollView(child: column(5))),
        size: (20, 10),
      );
      expect(down(t, 19, 10), track(10));
      expect(t, styleAt(19, 0, isNot(hasAttr(Attr.reverse))));
    });

    testTwk('never: no bar, the child takes all the room', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          visibility: ScrollbarVisibility.never,
          child: SingleChildScrollView(
            controller: controller,
            child: Text('a' * 20),
          ),
        ),
        size: (20, 3),
      );
      expect(t.lines.first, 'a' * 20);
      await t.pumpWidget(
        Scrollbar(
          child: SingleChildScrollView(
            controller: controller,
            child: Text('a' * 20),
          ),
        ),
      );
      expect(t.lines.take(2), ['a' * 19, 'a']);
    });

    testTwk('onScroll: the thumb from a move until hideAfter after the last '
        'one on the clock of the app, and while it is dragged', (t) async {
      final controller = ScrollController();
      await t.pumpWidget(
        Scrollbar(
          visibility: ScrollbarVisibility.onScroll,
          hideAfter: const Duration(milliseconds: 500),
          child: SingleChildScrollView(
            controller: controller,
            child: column(30),
          ),
        ),
        size: (20, 10),
      );
      expect(down(t, 19, 10), track(10));
      controller.jumpTo(10);
      await t.pump();
      expect(down(t, 19, 10), [
        ...track(3),
        '▅',
        ...thumb(2),
        '~▂',
        ...track(3),
      ]);
      await t.pump(const Duration(milliseconds: 300));
      await t.mouse(MouseKind.wheelUp, 4, 4);
      await t.pump(const Duration(milliseconds: 400));
      expect(down(t, 19, 10), [
        ...track(2),
        '▅',
        ...thumb(2),
        '~▂',
        ...track(4),
      ]);
      await t.pump(const Duration(milliseconds: 150));
      expect(down(t, 19, 10), track(10));

      await t.mouse(MouseKind.down, 19, 3);
      await t.pump();
      expect(down(t, 19, 10), [
        ...track(2),
        '▅',
        ...thumb(2),
        '~▂',
        ...track(4),
      ]);
      await t.mouse(MouseKind.drag, 19, 4);
      await t.pump(const Duration(seconds: 2));
      expect(controller.offset, 10);
      expect(down(t, 19, 10)[3], '▅');
      await t.mouse(MouseKind.up, 19, 4);
      await t.pump(const Duration(milliseconds: 450));
      expect(down(t, 19, 10)[3], '▅');
      await t.pump(const Duration(milliseconds: 100));
      expect(down(t, 19, 10), track(10));
      await t.pumpUntilIdle();
    });
  });

  testTwk('over a ListView of a hundred thousand items, the thumb drags it '
      'to any of them, building those in view alone; the wheel speeds up '
      'there too', (t) async {
    var built = 0;
    final list = ListController();
    await t.pumpWidget(
      Scrollbar(
        child: ListView.builder(
          itemCount: 100000,
          controller: list,
          autofocus: true,
          wheelAcceleration: const WheelAcceleration(),
          itemBuilder: (context, index) {
            built++;
            return Text('item $index');
          },
        ),
      ),
      size: (20, 10),
    );
    expect(down(t, 19, 10), [...thumb(1), ...track(9)]);
    await t.press('end');
    await t.pump();
    expect(t.lines.last, 'item 99999');
    expect(down(t, 19, 10), [...track(9), ...thumb(1)]);
    built = 0;
    await t.mouse(MouseKind.down, 19, 9);
    await t.mouse(MouseKind.drag, 19, 4);
    await t.mouse(MouseKind.up, 19, 4);
    await t.pump();
    // 99990 rows to 72 eighths of room: 40 eighths back
    expect(list.offset, 44440);
    expect(t.lines.first, 'item 44440');
    expect(down(t, 19, 10), [...track(4), ...thumb(1), ...track(5)]);
    expect(built, lessThan(30));
    await t.mouse(MouseKind.wheelDown, 4, 4);
    await t.pump(const Duration(milliseconds: 10));
    await t.mouse(MouseKind.wheelDown, 4, 4);
    await t.pump();
    expect(t.lines.first, 'item 44461');
  });
}
