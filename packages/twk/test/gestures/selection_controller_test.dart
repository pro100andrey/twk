// A SelectionArea driven from outside it and copying what an app wants: a
// SelectionAreaController that tells whether something is selected and its
// text, and clears it; copyTransform, which turns what is selected into
// what is copied; the blanks a Selectable's lines end in, dropped as a
// Text's are; and a drag past the left or right edge of a view that
// scrolls sideways, which scrolls it on.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [lines] from row `top` and column `left` on, [rows] by [columns] of
/// them; scrolled both ways by a drag past its edges.
final class Grid extends LeafRenderObjectWidget {
  const Grid(this.lines, {this.rows, this.columns, super.key});

  final List<String> lines;
  final int? rows;
  final int? columns;

  @override
  RenderGrid createRenderObject(BuildContext context) =>
      lastGrid = RenderGrid(lines, rows, columns);

  @override
  void updateRenderObject(BuildContext context, RenderGrid renderObject) {}
}

/// The render object of the [Grid] made last.
RenderGrid? lastGrid;

final class RenderGrid extends RenderObject with Selectable {
  RenderGrid(this.lines, this.rows, this.columns) : text = lines.join('\n') {
    var at = 0;
    for (final l in lines) {
      starts.add(at);
      at += l.length + 1;
    }
  }

  final List<String> lines;
  final int? rows;
  final int? columns;
  final String text;
  final starts = <int>[];
  var top = 0;
  var left = 0;
  final across = <int>[];

  @override
  String get selectableText => text;

  @override
  (int, int) selectableRangeAt(int x, int y) {
    final row = y + top;
    if (row < 0) {
      return (0, 0);
    }
    if (row >= lines.length) {
      return (text.length, text.length);
    }
    final start = starts[row];
    final column = x + left;
    if (column < 0) {
      return (start, start);
    }
    if (column >= lines[row].length) {
      final next = row + 1 < lines.length ? starts[row + 1] : text.length;
      return (next, next);
    }
    return (start + column, start + column + 1);
  }

  @override
  bool scrollSelectionBy(int rows) {
    final shown = this.rows;
    if (shown == null) {
      return false;
    }
    final max = lines.length - shown;
    final to = (top + rows).clamp(0, max < 0 ? 0 : max);
    if (to == top) {
      return false;
    }
    top = to;
    markNeedsPaint();
    return true;
  }

  @override
  bool scrollSelectionAcross(int columns) {
    final shown = this.columns;
    if (shown == null) {
      return false;
    }
    final widest = lines.fold(0, (w, l) => l.length > w ? l.length : w);
    final max = widest - shown;
    final to = (left + columns).clamp(0, max < 0 ? 0 : max);
    if (to == left) {
      return false;
    }
    across.add(columns);
    left = to;
    markNeedsPaint();
    return true;
  }

  @override
  void performLayout(BoxConstraints c) {
    final widest = lines.fold(0, (w, l) => l.length > w ? l.length : w);
    width = c.constrainW(columns ?? widest);
    height = c.constrainH(rows ?? lines.length);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    for (var i = 0; i < height; i++) {
      final row = i + top;
      if (row >= lines.length) {
        break;
      }
      final line = lines[row];
      for (var x = 0; x < width && x + left < line.length; x++) {
        final c = x + left;
        final style = selectionStyleAt(starts[row] + c, const Style());
        canvas.text(x, i, line[c], style.penIn(canvas.styles));
      }
    }
  }
}

/// [children] one below another from the left.
Widget column(List<Widget> children) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);

/// Presses the left button at [from], drags it through [through] and
/// releases it at the last of those.
Future<void> drag(
  TwkTester t,
  (int, int) from,
  List<(int, int)> through,
) async {
  await t.mouse(MouseKind.down, from.$1, from.$2);
  for (final (x, y) in through) {
    await t.mouse(MouseKind.drag, x, y);
  }
  final (x, y) = through.last;
  await t.mouse(MouseKind.up, x, y);
  await t.pump();
}

/// The columns of row [y] from 0 to [width] with the selection's background
/// video, as `x`, and without, as `.`.
String marked(TwkTester t, int y, int width) => [
  for (var x = 0; x < width; x++)
    if (t.vt.cell(x, y).bg == const Color.indexed(237).value) 'x' else '.',
].join();

/// The keys with hints a KeyHintsBar would show now.
List<String> hints(TwkTester t) => [
  for (final k in t.binding.focusManager.activeKeys)
    if (k.hint != null) '$k',
];

void main() {
  group('a SelectionAreaController', () {
    testTwk('tells whether something is selected, when that changes, and '
        'what as copied; clears it from outside', (t) async {
      final copies = <String>[];
      final controller = SelectionAreaController();
      addTearDown(controller.dispose);
      var told = 0;
      controller.addListener(() => told++);
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            controller: controller,
            onCopy: copies.add,
            child: column(const [Text('hello  '), Text('world')]),
          ),
        ),
        size: (8, 3),
      );
      expect(controller.hasSelection, isFalse);
      expect(controller.text, '');
      await drag(t, (1, 0), [(2, 0), (3, 0), (6, 0), (2, 1)]);
      expect(controller.hasSelection, isTrue);
      expect(told, 1, reason: 'told when something came to be selected');
      expect(controller.text, 'ello\nwor');
      expect(copies, ['ello\nwor']);
      controller.clear();
      await t.pump();
      expect(controller.hasSelection, isFalse);
      expect(controller.text, '');
      expect(told, 2);
      expect(marked(t, 0, 7), '.......');
      expect(marked(t, 1, 5), '.....');
      expect(hints(t), isNot(contains('escape clear')));
      controller.clear();
      expect(told, 2, reason: 'nothing to clear: nothing changed');
    });

    testTwk('clears a Selectable it selected in, and a drag under way, '
        'which then selects and copies nothing more', (t) async {
      final copies = <String>[];
      final controller = SelectionAreaController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            controller: controller,
            onCopy: copies.add,
            child: const Grid(['one two', 'three']),
          ),
        ),
        size: (8, 3),
      );
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 2, 1);
      await t.pump();
      expect(lastGrid!.selection, (0, 11));
      controller.clear();
      await t.pump();
      expect(lastGrid!.selection, isNull);
      expect(marked(t, 0, 7), '.......');
      await t.mouse(MouseKind.drag, 4, 1);
      await t.mouse(MouseKind.up, 4, 1);
      await t.pump();
      expect(lastGrid!.selection, isNull);
      expect(controller.hasSelection, isFalse);
      expect(copies, isEmpty);
    });

    testTwk('given to another area: the one before lets it go', (t) async {
      final first = SelectionAreaController();
      final second = SelectionAreaController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget build(SelectionAreaController c) => SelectionArea(
        controller: c,
        child: const Text('hello'),
      );
      await t.pumpWidget(Theme.terminal(child: build(first)), size: (7, 2));
      await drag(t, (1, 0), [(3, 0)]);
      expect(first.hasSelection, isTrue);
      await t.pumpWidget(Theme.terminal(child: build(second)));
      expect(first.hasSelection, isFalse);
      expect(first.text, '');
      expect(second.hasSelection, isTrue);
      expect(second.text, 'ell');
      first.clear();
      await t.pump();
      expect(marked(t, 0, 5), '.xxx.');
      second.clear();
      await t.pump();
      expect(marked(t, 0, 5), '.....');
    });
  });

  group('copyTransform', () {
    testTwk('turns what is selected into what is copied: on the release, by '
        "the copy key, and as the controller's text", (t) async {
      final copies = <String>[];
      final controller = SelectionAreaController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            controller: controller,
            copyKey: 'ctrl+y',
            onCopy: copies.add,
            copyTransform: (text) => text.toUpperCase(),
            child: const Text('hello world'),
          ),
        ),
        size: (12, 2),
      );
      await drag(t, (0, 0), [(4, 0)]);
      expect(copies, ['HELLO']);
      expect(controller.text, 'HELLO');
      await t.press('ctrl+y');
      await t.pump();
      expect(copies, ['HELLO', 'HELLO']);
    });

    testTwk('gets the text trimmed; what it makes empty is not copied', (
      t,
    ) async {
      final copies = <String>[];
      final got = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            copyTransform: (text) {
              got.add(text);
              return text.startsWith('a') ? '' : text;
            },
            child: const Text('ab  \ncd'),
          ),
        ),
        size: (6, 3),
      );
      await drag(t, (0, 0), [(1, 1)]);
      expect(got, ['ab\ncd']);
      expect(copies, isEmpty);
      await t.pump(const Duration(milliseconds: 400));
      await drag(t, (0, 1), [(1, 1)]);
      expect(copies, ['cd']);
    });
  });

  group('the blanks that end a line', () {
    testTwk("are left out of a Selectable's copy as out of a Text's, those "
        'within a line kept', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: column(const [
              Text('ab  cd  \nef  '),
              Grid(['ab  cd  ', 'ef  ']),
            ]),
          ),
        ),
        size: (10, 5),
      );
      for (final top in [0, 2]) {
        await t.pump(const Duration(milliseconds: 400));
        await drag(t, (0, top), [(9, top + 1)]);
        await t.pump(const Duration(milliseconds: 400));
        await drag(t, (0, top), [(2, top)]);
      }
      expect(copies, ['ab  cd\nef', 'ab ', 'ab  cd\nef', 'ab ']);
    });
  });

  group('a drag past the left or right edge', () {
    Widget sideways(List<String> copies, ScrollController controller) =>
        SelectionArea(
          onCopy: copies.add,
          child: column([
            SizedBox(
              width: 6,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: controller,
                child: const Text('abcdefghijklmn'),
              ),
            ),
          ]),
        );

    testTwk('of a Scrollable that scrolls sideways scrolls it on while it '
        'stays there, by the columns it is past, the selection '
        'following', (t) async {
      final copies = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Theme.terminal(child: sideways(copies, controller)),
        size: (12, 2),
      );
      expect(t.lines.first, 'abcdef');
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 7, 0);
      await t.pump();
      expect(controller.offset, 2, reason: 'two columns past it: two on');
      await t.pump(const Duration(milliseconds: 50));
      expect(controller.offset, 4);
      expect(t.lines.first, 'efghij');
      expect(marked(t, 0, 7), 'xxxxxx.');
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 50));
      expect(controller.offset, 8, reason: 'at its end');
      await t.mouse(MouseKind.up, 7, 0);
      await t.pump();
      expect(copies, ['abcdefghijklmn']);
      // and past its left edge, back
      await t.pump(const Duration(milliseconds: 400));
      await t.mouse(MouseKind.down, 5, 0);
      await t.mouse(MouseKind.drag, 3, 0);
      // the screen's first column counts as past it
      await t.mouse(MouseKind.drag, 0, 0);
      await t.pump(const Duration(milliseconds: 500));
      await t.mouse(MouseKind.up, 0, 0);
      await t.pump();
      expect(controller.offset, 0);
      expect(copies.last, 'abcdefghijklmn');
    });

    testTwk('back within it stops the scrolling', (t) async {
      final copies = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Theme.terminal(child: sideways(copies, controller)),
        size: (12, 2),
      );
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 6, 0);
      await t.pump();
      expect(controller.offset, 1);
      await t.mouse(MouseKind.drag, 4, 0);
      await t.pump(const Duration(milliseconds: 200));
      expect(controller.offset, 1);
      await t.mouse(MouseKind.up, 4, 0);
      await t.pump();
      expect(copies, ['abcdef']);
    });

    testTwk('at the last column of the screen, where the mouse can go no '
        'further, scrolls a view that ends there', (t) async {
      final copies = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Theme.terminal(child: sideways(copies, controller)),
        size: (6, 2),
      );
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 5, 0);
      await t.pump();
      expect(controller.offset, 1);
      await t.mouse(MouseKind.up, 5, 0);
      await t.pump();
      expect(copies, ['abcdefg']);
    });

    testTwk('and the bottom, of a view in a view, scrolls both', (t) async {
      final copies = <String>[];
      final down = ScrollController();
      final across = ScrollController();
      addTearDown(down.dispose);
      addTearDown(across.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: column([
              SizedBox(
                width: 4,
                height: 2,
                child: SingleChildScrollView(
                  controller: down,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: across,
                    child: column([
                      for (var i = 0; i < 4; i++) Text('$i-abcdefgh'),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
        size: (8, 4),
      );
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 4, 2);
      await t.pump();
      expect((down.offset, across.offset), (1, 1));
      await t.mouse(MouseKind.up, 4, 2);
      await t.pump();
      // the row under the mouse shows the fourth line now
      expect(copies, ['0-abcdefgh\n1-abcdefgh\n2-abcdefgh\n3-abcd']);
    });

    testTwk('of a Selectable that scrolls itself sideways scrolls it', (
      t,
    ) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: column(const [
              Grid(['abcdefghij', 'klmnopqrst'], columns: 4),
            ]),
          ),
        ),
        size: (8, 3),
      );
      final grid = lastGrid!;
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 6, 0);
      await t.pump();
      expect(grid.across, [3]);
      await t.pump(const Duration(milliseconds: 50));
      expect(grid.left, 6);
      await t.mouse(MouseKind.up, 6, 0);
      await t.pump();
      // right of the row: up to where the next starts
      expect(copies, ['abcdefghij\n']);
      expect(t.lines.first, 'ghij');
    });
  });
}
