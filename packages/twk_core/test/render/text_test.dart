// A paragraph paints its lines from the glyphs it keeps for all of them,
// without a copy per line: each line, the clusters as stored and the lines
// ordered for drawing alike, draws what the same text laid out on its own
// draws, after any edit, and the paragraph's arrays grow with its text.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

const red = Color.rgb(200, 0, 0);
const blue = Color.rgb(0, 0, 200);

/// A screen, an owner drawing text in `order` and an emulator.
final class View {
  View(this.width, this.height, {TextOrder order = TextOrder.logical})
    : screen = Screen(width, height),
      vt = Vt(width, height) {
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
      ..textOrder = order;
  }

  final int width;
  final int height;
  final Screen screen;
  final Vt vt;
  late final PipelineOwner owner;

  /// The rows [p] paints as wide as the screen, each cell's text followed
  /// by `r` or `b` where its foreground is red or blue; checked against
  /// what the emulator shows.
  List<String> show(RenderParagraph p) {
    if (p.parent == null) {
      owner.root = RenderFlex(
        direction: Axis.vertical,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [p],
      );
    }
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    final bytes = screen.render();
    if (bytes != null) {
      vt.feed(bytes);
    }
    expect(vt.errors, isEmpty, reason: 'what the emulator rejected');
    final cells = screen.surface.cells;
    final text = [
      for (var y = 0; y < height; y++)
        [
          for (var x = 0; x < width; x++)
            if ((cells[y * width + x] & kCont) == 0)
              screen.glyphs.stringOf(cells[y * width + x]),
        ].join().trimRight(),
    ];
    expect(
      [for (final r in vt.dump().split('\n')) r.trimRight()],
      text,
      reason: 'what the terminal shows',
    );
    return [
      for (var y = 0; y < p.height; y++)
        [
          for (var x = 0; x < width; x++)
            if ((cells[y * width + x] & kCont) == 0) _cell(y * width + x),
        ].join(),
    ];
  }

  /// The text of cell [i] and `r` or `b` where its foreground is red or
  /// blue.
  String _cell(int i) {
    final fg = screen.styles.fgOf(screen.surface.styles[i]);
    return '${screen.glyphs.stringOf(screen.surface.cells[i])}${_pen(fg)}';
  }
}

String _pen(Color fg) => fg == red
    ? 'r'
    : fg == blue
    ? 'b'
    : '';

/// The rows a fresh paragraph of [spans] paints [width] wide.
List<String> fresh(
  List<(String, Pen)> spans,
  int width,
  int height, {
  TextOrder order = TextOrder.logical,
}) => View(width, height, order: order).show(RenderParagraph(spans));

void main() {
  test('lines ordered for drawing each draw their own glyphs', () {
    // three lines, each with right-to-left text in two spans: every line's
    // pieces are gathered for drawing, so a line drawn from what the next
    // one gathered would show
    const lines = [
      [('abc אבג ', Pen(fg: red)), ('דהו xyz', Pen(fg: blue))],
      [('זחט 12 ', Pen(fg: red)), ('(יכל) mn', Pen(fg: blue))],
      [('מנס op ', Pen(fg: red)), ('עפצ קרש', Pen(fg: blue))],
    ];
    final spans = [
      for (var i = 0; i < lines.length; i++) ...[
        ...lines[i],
        if (i < lines.length - 1) ('\n', const Pen(fg: red)),
      ],
    ];
    final view = View(20, 6, order: TextOrder.visual);
    final rows = view.show(RenderParagraph(spans));
    expect(rows, [
      for (final l in lines) fresh(l, 20, 6, order: TextOrder.visual).single,
    ]);
    expect(rows[0], isNot(rows[1]));
  });

  test('a paragraph edited a character at a time draws what a fresh one '
      'does, longer and shorter again', () {
    const words =
        'one two three four five six seven eight nine ten eleven '
        'twelve 你好 thirteen fourteen fifteen';
    final view = View(16, 12);
    final p = RenderParagraph(const [('', Pen(fg: red))]);
    for (final k in [
      for (var k = 1; k <= words.length; k++) k,
      for (var k = words.length - 1; k > 0; k -= 3) k,
    ]) {
      final spans = [
        (words.substring(0, k ~/ 2), const Pen(fg: red)),
        (words.substring(k ~/ 2, k), const Pen(fg: blue)),
      ];
      p.spans = spans;
      expect(view.show(p), fresh(spans, 16, 12), reason: '$k characters');
    }
  });

  test('a paragraph moved to an owner that draws text in another order is '
      'laid out again in that order', () {
    const hebrew = '\u05D0\u05D1\u05D2';
    final p = RenderParagraph(const [('ab $hebrew', Pen())]);
    expect(View(6, 1).show(p), ['ab $hebrew']);
    (p.parent! as RenderFlex).remove(p);
    final visual = View(6, 1, order: TextOrder.visual);
    expect(visual.show(p), ['ab \u05D2\u05D1\u05D0']);
  });
}
