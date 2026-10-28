// A drag in a SelectionArea that what is under the mouse scrolls under
// without the mouse moving (the wheel, while the button is held): the
// selection goes on to what is under the mouse now, as a terminal's does,
// in a Scrollable and in a Selectable that scrolls itself.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [lines] from the one scrolled to (`top`) on, scrolled by the wheel over
/// them, a row a notch.
final class Lines extends LeafRenderObjectWidget {
  const Lines(this.lines, {super.key});

  final List<String> lines;

  @override
  RenderLines createRenderObject(BuildContext context) => RenderLines(lines);

  @override
  void updateRenderObject(BuildContext context, RenderLines renderObject) {}
}

final class RenderLines extends RenderObject with Selectable {
  RenderLines(this.lines) : text = lines.join('\n') {
    var at = 0;
    for (final l in lines) {
      starts.add(at);
      at += l.length + 1;
    }
  }

  final List<String> lines;
  final String text;
  final starts = <int>[];
  var top = 0;

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
    if (x < 0) {
      return (start, start);
    }
    if (x >= lines[row].length) {
      final next = row + 1 < lines.length ? starts[row + 1] : text.length;
      return (next, next);
    }
    return (start + x, start + x + 1);
  }

  @override
  bool hitTestSelf(int x, int y) => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(10);
    height = c.constrainH(3);
  }

  @override
  void paint(PaintContext ctx) {
    final canvas = ctx.canvas;
    for (var i = 0; i < height && i + top < lines.length; i++) {
      final row = i + top;
      final line = lines[row];
      for (var c = 0; c < line.length; c++) {
        final style = selectionStyleAt(starts[row] + c, const Style());
        canvas.text(c, i, line[c], style.penIn(canvas.styles));
      }
    }
  }
}

/// The columns of row [y] from 0 to [width] with the selection's background
/// video, as `x`, and without, as `.`.
String marked(TwkTester t, int y, int width) => [
  for (var x = 0; x < width; x++)
    if (t.vt.cell(x, y).bg == const Color.indexed(237).value) 'x' else '.',
].join();

final List<String> ten = [for (var i = 0; i < 10; i++) 'line $i'];

void main() {
  group('the wheel during a drag', () {
    testTwk('in a Scrollable: the selection goes on to the line under the '
        'mouse, before the release', (t) async {
      final copies = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: SizedBox(
              height: 3,
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final l in ten) Text(l)],
                ),
              ),
            ),
          ),
        ),
        size: (10, 6),
      );
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 3, 1);
      await t.pump();
      expect(marked(t, 1, 7), 'xxxx...');
      await t.mouse(MouseKind.wheelDown, 3, 1);
      await t.pump();
      final scrolled = controller.offset;
      expect(scrolled, greaterThan(0));
      await t.pump(const Duration(milliseconds: 60));
      // row 1 shows line 1 + scrolled now, selected up to the mouse
      expect(t.lines[1], 'line ${1 + scrolled}');
      expect(marked(t, 1, 7), 'xxxx...');
      expect(marked(t, 0, 7), 'xxxxxx.');
      await t.mouse(MouseKind.up, 3, 1);
      await t.pump();
      expect(copies, [
        [...ten.take(1 + scrolled), 'line'].join('\n'),
      ]);
    });

    testTwk('in a Selectable that scrolls itself, released at once: what '
        'is copied goes on to the line under the mouse', (t) async {
      final copies = <String>[];
      RenderLines? lines;
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: Builder(
              builder: (context) => Listener(
                onScroll: (e) {
                  (lines ??= _find(context))
                    ..top += e.kind == MouseKind.wheelDown ? 1 : -1
                    ..markNeedsPaint();
                },
                child: Lines(ten),
              ),
            ),
          ),
        ),
        size: (10, 6),
      );
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 3, 1);
      await t.mouse(MouseKind.wheelDown, 3, 1);
      await t.mouse(MouseKind.wheelDown, 3, 1);
      await t.mouse(MouseKind.up, 3, 1);
      await t.pump();
      // row 1 shows line 3
      expect(copies, ['line 0\nline 1\nline 2\nline']);
    });

    testTwk('a press that selected nothing selects nothing by it', (t) async {
      final copies = <String>[];
      RenderLines? lines;
      await t.pumpWidget(
        Theme.terminal(
          child: SelectionArea(
            onCopy: copies.add,
            child: Builder(
              builder: (context) => Listener(
                onScroll: (e) {
                  (lines ??= _find(context))
                    ..top += 1
                    ..markNeedsPaint();
                },
                child: Lines(ten),
              ),
            ),
          ),
        ),
        size: (10, 6),
      );
      await t.mouse(MouseKind.down, 2, 1);
      await t.mouse(MouseKind.wheelDown, 2, 1);
      await t.pump(const Duration(milliseconds: 120));
      expect(marked(t, 1, 7), '.......');
      await t.mouse(MouseKind.up, 2, 1);
      await t.pump();
      expect(copies, isEmpty);
    });
  });
}

/// The [RenderLines] below [context].
RenderLines _find(BuildContext context) {
  RenderLines? found;
  void visit(Element e) {
    if (e is RenderObjectElement && e.renderObject is RenderLines) {
      found = e.renderObject as RenderLines;
    }
    if (found == null) {
      e.visitChildren(visit);
    }
  }

  (context as Element).visitChildren(visit);
  return found!;
}
