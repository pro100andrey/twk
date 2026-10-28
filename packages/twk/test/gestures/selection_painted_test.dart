// What a SelectionArea selects besides Texts and how: a render object of
// an app's own taking part (a Selectable: a log painted with a gutter of
// line numbers, left out of what is copied), a drag past the edge of the
// Scrollable it selects in scrolling it on, or past that of a view that
// scrolls itself, the key that clears the selection, and the blanks that
// end a line dropped from what is copied.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// [lines] painted after a gutter of their numbers, [rows] of them from
/// the one scrolled to on (all of them when null); scrolled by a drag past
/// its edge.
final class Log extends LeafRenderObjectWidget {
  const Log(this.lines, {this.rows, super.key});

  final List<String> lines;
  final int? rows;

  @override
  RenderLog createRenderObject(BuildContext context) =>
      lastLog = RenderLog(lines, rows);

  @override
  void updateRenderObject(BuildContext context, RenderLog renderObject) {}
}

/// The render object of the [Log] made last.
RenderLog? lastLog;

/// The gutter's width: the number in two columns, a blank.
const gutter = 3;

final class RenderLog extends RenderObject with Selectable {
  RenderLog(this.lines, this.rows) : text = lines.join('\n') {
    var at = 0;
    for (final l in lines) {
      starts.add(at);
      at += l.length + 1;
    }
  }

  final List<String> lines;
  final int? rows;
  final String text;
  final starts = <int>[];
  var top = 0;
  final scrolls = <int>[];

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
    final column = x - gutter;
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
    scrolls.add(rows);
    top = to;
    markNeedsPaint();
    return true;
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(gutter + 10);
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
      canvas.text(
        0,
        i,
        '${row + 1}'.padLeft(gutter - 1),
        const Style(attrs: Attr.dim).penIn(canvas.styles),
      );
      final line = lines[row];
      for (var c = 0; c < line.length; c++) {
        final style = selectionStyleAt(starts[row] + c, const Style());
        canvas.text(gutter + c, i, line[c], style.penIn(canvas.styles));
      }
    }
  }
}

/// [child] in a [SelectionArea] that tells [copies] what it copied.
Widget area(
  List<String> copies,
  Widget child, {
  String? clearKey = 'escape',
  bool trimTrailingBlanks = true,
}) => SelectionArea(
  onCopy: copies.add,
  clearKey: clearKey,
  trimTrailingBlanks: trimTrailingBlanks,
  child: child,
);

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
  group('a Selectable', () {
    testTwk('is selected across in the order of the tree with the Texts, '
        'its gutter left out of what is copied and painted', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            column(const [
              Text('head'),
              Log(['one two', 'three']),
              Text('tail'),
            ]),
          ),
        ),
        size: (14, 5),
      );
      expect(t.lines.take(4), ['head', ' 1 one two', ' 2 three', 'tail']);
      await drag(t, (2, 0), [(5, 1), (1, 3)]);
      expect(copies, ['ad\none two\nthree\nta']);
      expect(marked(t, 0, 6), '..xx..');
      expect(marked(t, 1, 12), '...xxxxxxx..');
      expect(marked(t, 2, 12), '...xxxxx....');
      expect(marked(t, 3, 6), 'xx....');
    });

    testTwk('from its gutter: from the start of the row; by words and lines '
        'as a Text', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(child: area(copies, const Log(['one two', 'three']))),
        size: (14, 3),
      );
      await drag(t, (0, 1), [(4, 1)]);
      expect(copies, ['th']);
      expect(marked(t, 1, 10), '...xx.....');
      await t.pump(const Duration(milliseconds: 400));
      await t.click(8, 0);
      await t.click(8, 0);
      expect(copies.last, 'two');
      await t.pump(const Duration(milliseconds: 400));
      await t.click(5, 1);
      await t.click(5, 1);
      await t.click(5, 1);
      expect(copies.last, 'three');
      await t.pump(const Duration(milliseconds: 400));
      await t.click(4, 0);
      await t.pump();
      expect(marked(t, 1, 10), '..........');
    });
  });

  group('a drag past the edge', () {
    testTwk('of the Scrollable it selects in scrolls it on while it stays '
        'there, by the rows it is past, the selection following', (t) async {
      final copies = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            column([
              SizedBox(
                height: 3,
                child: SingleChildScrollView(
                  controller: controller,
                  child: column([
                    for (var i = 0; i < 10; i++) Text('line $i'),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        size: (10, 6),
      );
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 1, 4);
      await t.pump();
      expect(controller.offset, 2, reason: 'two rows past it: two rows on');
      await t.pump(const Duration(milliseconds: 50));
      expect(controller.offset, 4);
      expect(t.lines.take(3), ['line 4', 'line 5', 'line 6']);
      expect(marked(t, 1, 7), 'xxxxxx.');
      expect(marked(t, 2, 7), 'xx.....');
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 50));
      expect(controller.offset, 7, reason: 'at its end');
      await t.mouse(MouseKind.up, 1, 4);
      await t.pump();
      expect(copies, [
        [for (var i = 0; i < 10; i++) 'line $i'].join('\n'),
      ]);
      expect(marked(t, 2, 7), 'xxxxxx.');
      await t.pump(const Duration(milliseconds: 200));
      expect(controller.offset, 7);
    });

    testTwk('back within it stops the scrolling', (t) async {
      final copies = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            column([
              SizedBox(
                height: 3,
                child: SingleChildScrollView(
                  controller: controller,
                  child: column([
                    for (var i = 0; i < 10; i++) Text('line $i'),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        size: (10, 6),
      );
      await t.mouse(MouseKind.down, 0, 0);
      await t.mouse(MouseKind.drag, 1, 3);
      await t.pump();
      expect(controller.offset, 1);
      await t.mouse(MouseKind.drag, 1, 2);
      await t.pump(const Duration(milliseconds: 200));
      expect(controller.offset, 1);
      await t.mouse(MouseKind.up, 1, 2);
      await t.pump();
      expect(copies, ['line 0\nline 1\nline 2\nli']);
    });

    for (final around in [false, true]) {
      testTwk('on the last row of the screen, where the mouse can go no '
          'further, scrolls a view that ends there'
          '${around ? ', the area inside it' : ''}', (t) async {
        final copies = <String>[];
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final lines = column([for (var i = 0; i < 10; i++) Text('line $i')]);
        await t.pumpWidget(
          Theme.terminal(
            child: around
                ? SingleChildScrollView(
                    controller: controller,
                    child: area(copies, lines),
                  )
                : area(
                    copies,
                    SingleChildScrollView(controller: controller, child: lines),
                  ),
          ),
          size: (10, 3),
        );
        await t.mouse(MouseKind.down, 0, 0);
        await t.mouse(MouseKind.drag, 1, 2);
        await t.pump();
        expect(controller.offset, 1);
        await t.pump(const Duration(milliseconds: 50));
        expect(controller.offset, 2);
        await t.mouse(MouseKind.up, 1, 2);
        await t.pump();
        expect(copies, ['line 0\nline 1\nline 2\nline 3\nli']);
      });
    }

    testTwk('of a Selectable that scrolls itself scrolls it', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            column(const [
              Log(['a', 'b', 'c', 'd', 'e'], rows: 2),
            ]),
          ),
        ),
        size: (14, 5),
      );
      final log = lastLog!;
      await t.mouse(MouseKind.down, 3, 0);
      await t.mouse(MouseKind.drag, 3, 3);
      await t.pump();
      expect(log.scrolls, [2]);
      await t.pump(const Duration(milliseconds: 50));
      expect(log.top, 3);
      await t.mouse(MouseKind.up, 3, 3);
      await t.pump();
      expect(copies, ['a\nb\nc\nd\ne']);
      expect(t.lines.take(2), [' 4 d', ' 5 e']);
    });

    testTwk('of a Selectable that does not scroll itself scrolls the '
        'Scrollable it is in', (t) async {
      final copies = <String>[];
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            column([
              SizedBox(
                height: 2,
                child: SingleChildScrollView(
                  controller: controller,
                  child: column(const [_Word('word'), SizedBox(height: 5)]),
                ),
              ),
            ]),
          ),
        ),
        size: (10, 5),
      );
      await t.mouse(MouseKind.down, 1, 0);
      await t.mouse(MouseKind.drag, 1, 2);
      await t.pump();
      expect(controller.offset, 1);
      await t.mouse(MouseKind.up, 1, 2);
      await t.pump();
      expect(copies, ['ord']);
    });
  });

  group('the clear key', () {
    testTwk('Escape clears the selection, among the hints while there is '
        'one; with none it passes on', (t) async {
      final copies = <String>[];
      var outer = 0;
      await t.pumpWidget(
        Theme.terminal(
          child: KeyBindings(
            {'escape': () => outer++},
            child: area(copies, const Text('hello')),
          ),
        ),
        size: (7, 2),
      );
      expect(hints(t), isNot(contains('escape clear')));
      await drag(t, (1, 0), [(3, 0)]);
      expect(marked(t, 0, 5), '.xxx.');
      expect(hints(t), contains('escape clear'));
      await t.press('escape');
      await t.pump();
      expect(marked(t, 0, 5), '.....');
      expect(outer, 0);
      expect(hints(t), isNot(contains('escape clear')));
      await t.press('escape');
      await t.pump();
      expect(outer, 1);
      expect(copies, ['ell']);
    });

    testTwk('clearKey: another key; null for none', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(copies, const Text('hello'), clearKey: 'ctrl+x'),
        ),
        size: (7, 2),
      );
      await drag(t, (1, 0), [(3, 0)]);
      await t.press('escape');
      await t.pump();
      expect(marked(t, 0, 5), '.xxx.');
      expect(hints(t), contains('ctrl+x clear'));
      await t.press('ctrl+x');
      await t.pump();
      expect(marked(t, 0, 5), '.....');
      await t.pumpWidget(
        Theme.terminal(
          child: area(copies, const Text('hello'), clearKey: null),
        ),
      );
      await drag(t, (1, 0), [(3, 0)]);
      expect(hints(t), isEmpty);
    });
  });

  group('what is copied', () {
    testTwk('leaves out the blanks that end a line, those of a Selectable '
        'too', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            column(const [
              Text('ab  \ncd  '),
              Log(['x  ', 'y']),
            ]),
          ),
        ),
        size: (14, 5),
      );
      await drag(t, (0, 0), [(4, 3)]);
      expect(copies, ['ab\ncd\nx\ny']);
      await t.pump(const Duration(milliseconds: 400));
      await drag(t, (3, 2), [(4, 2)]);
      expect(marked(t, 2, 6), '...xx.');
      expect(copies.last, 'x', reason: 'only blanks follow to the line end');
    });

    testTwk('keeps the blanks within a line', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(child: area(copies, const Text('a  b'))),
        size: (7, 2),
      );
      await drag(t, (0, 0), [(2, 0)]);
      expect(copies, ['a  ']);
    });

    testTwk('with trimTrailingBlanks false, keeps them', (t) async {
      final copies = <String>[];
      await t.pumpWidget(
        Theme.terminal(
          child: area(
            copies,
            const Text('ab  \ncd  '),
            trimTrailingBlanks: false,
          ),
        ),
        size: (7, 3),
      );
      await drag(t, (0, 0), [(4, 1)]);
      expect(copies, ['ab  \ncd  ']);
    });
  });
}

/// [word] on a row, selected as a [Selectable] that does not scroll.
final class _Word extends LeafRenderObjectWidget {
  const _Word(this.word);

  final String word;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWord(word);
}

final class _RenderWord extends RenderObject with Selectable {
  _RenderWord(this.word);

  final String word;

  @override
  String get selectableText => word;

  @override
  (int, int) selectableRangeAt(int x, int y) {
    if (y < 0) {
      return (0, 0);
    }
    if (y > 0 || x >= word.length) {
      return (word.length, word.length);
    }
    final at = x < 0 ? 0 : x;
    return (at, at + 1);
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(word.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    for (var c = 0; c < word.length; c++) {
      final style = selectionStyleAt(c, const Style());
      ctx.canvas.text(c, 0, word[c], style.penIn(ctx.canvas.styles));
    }
  }
}
