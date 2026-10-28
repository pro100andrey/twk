// In visual order a paragraph draws each line of right-to-left text in the
// order it is read (UAX #9): its runs reversed, their brackets mirrored,
// start and end alignment by the paragraph's direction, a cell telling the
// text drawn there. In logical order, the default, and for text without
// right-to-left characters, it draws the text as stored. Every frame goes
// through the terminal emulator too, which must show what the screen holds.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

const plain = Pen();
const red = Color.rgb(200, 0, 0);
const blue = Color.rgb(0, 0, 200);

/// A screen, an owner drawing text in `order` and an emulator.
final class View {
  View(this.width, this.height, {TextOrder order = TextOrder.visual})
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

  /// Lays the tree out, paints it and shows the frame to the emulator;
  /// returns the rows of the screen.
  List<String> frame() {
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
    final rows = [
      for (var y = 0; y < height; y++)
        [
          for (var x = 0; x < width; x++)
            if ((screen.surface.cells[y * width + x] & kCont) == 0)
              screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
        ].join().trimRight(),
    ];
    expect(
      [for (final r in vt.dump().split('\n')) r.trimRight()],
      rows,
      reason: 'what the terminal shows',
    );
    return rows;
  }

  /// The rows [p] paints as wide as the screen.
  List<String> show(RenderParagraph p) {
    owner.root = RenderFlex(
      direction: Axis.vertical,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [p],
    );
    return frame().sublist(0, p.height);
  }

  /// The foreground of the cell at [x], [y].
  Color fgAt(int x, int y) =>
      screen.styles.fgOf(screen.surface.styles[y * width + x]);
}

/// The rows [text] takes in a paragraph [width] wide, in [order].
List<String> lay(
  String text,
  int width, {
  TextOrder order = TextOrder.visual,
  TextWrap wrap = TextWrap.word,
  TextOverflow overflow = TextOverflow.clip,
  TextAlign align = TextAlign.left,
  int? maxLines,
}) => View(width, 8, order: order).show(
  RenderParagraph(
    [(text, plain)],
    wrap: wrap,
    overflow: overflow,
    align: align,
    maxLines: maxLines,
  ),
);

/// The ranges `textRangeAt` gives for the cells of row [y] of [p], from the
/// column left of it to the one right of it: `start-end`, or `start` when
/// empty.
List<String> ranges(RenderParagraph p, int y) => [
  for (var x = -1; x <= p.width; x++)
    switch (p.textRangeAt(x, y)) {
      (final s, final e) when s == e => '$s',
      (final s, final e) => '$s-$e',
    },
];

void main() {
  test('in logical order, the default, right-to-left text is drawn as '
      'stored', () {
    expect(PipelineOwner(() {}).textOrder, TextOrder.logical);
    expect(lay('abc אבג def', 20, order: TextOrder.logical), ['abc אבג def']);
    expect(
      lay('שלום', 8, order: TextOrder.logical, align: TextAlign.start),
      ['שלום'],
    );
  });

  group('in visual order', () {
    test('a right-to-left run in a left-to-right paragraph is reversed', () {
      expect(lay('abc אבג def', 20), ['abc גבא def']);
      expect(lay('مرحبا بالعالم', 20), ['ملاعلاب ابحرم']);
    });

    test('a paragraph whose first strong character is right to left runs '
        'right to left, the left-to-right text in it kept as it reads', () {
      expect(lay('שלום world', 20), ['world םולש']);
      expect(lay('123 שלום', 20), ['םולש 123']);
    });

    test('numbers keep their order, brackets are mirrored', () {
      expect(lay('אב 123', 10), ['123 בא']);
      expect(lay('אב (גד)', 10), ['(דג) בא']);
      expect(lay('a (אב) b', 10), ['a (בא) b']);
    });

    test('a grapheme is reversed whole: marks stay on their letters', () {
      expect(lay('שָׁלוֹם', 10), ['םוֹלשָׁ']);
    });

    test('an override reverses what it holds', () {
      expect(lay('x\u202Eabc\u202Cy', 10), ['xcbay']);
    });

    test('lines are broken as stored, then each is reordered', () {
      expect(lay('אבג דהו', 4), ['גבא', 'והד']);
      expect(lay('abc אבג דהו', 8), ['abc גבא', 'והד']);
    });

    test('start and end follow the paragraph of each line; left and right '
        'stay put', () {
      expect(lay('שלום', 8, align: TextAlign.start), ['    םולש']);
      expect(lay('שלום', 8, align: TextAlign.end), ['םולש']);
      expect(lay('שלום', 8), ['םולש']);
      expect(lay('שלום', 8, align: TextAlign.right), ['    םולש']);
      expect(lay('abc\nשלום', 8, align: TextAlign.start), [
        'abc',
        '    םולש',
      ]);
      expect(lay('abc\nשלום', 8, align: TextAlign.end), [
        '     abc',
        'םולש',
      ]);
    });

    test('a justified right-to-left line is stretched from the right, its '
        'last line at the right', () {
      expect(lay('ab cd ef gh', 9, align: TextAlign.justify), [
        'ab  cd ef',
        'gh',
      ]);
      expect(lay('אב גד הו זח', 9, align: TextAlign.justify), [
        'וה דג  בא',
        '       חז',
      ]);
    });

    test('a right-to-left line wider than the paragraph keeps its start, at '
        'the right', () {
      expect(lay('אבגדה', 3, wrap: TextWrap.none), ['גבא']);
      expect(lay('abcde', 3, wrap: TextWrap.none), ['abc']);
    });

    test('an ellipsis stands where the text is cut off as it reads', () {
      expect(
        lay(
          'שלום עולם יפה',
          8,
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
        ),
        ['…וע םולש'],
      );
      expect(
        lay(
          'שלום עולם יפה',
          8,
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsisStart,
        ),
        ['הפי םלו…'],
      );
      expect(
        lay(
          'abc שלום',
          6,
          wrap: TextWrap.none,
          overflow: TextOverflow.ellipsis,
        ),
        ['abc ש…'],
      );
    });

    test('each cluster keeps the pen of its span', () {
      final v = View(10, 1);
      final p = RenderParagraph([
        ('ab ', plain),
        ('אב', const Pen(fg: red)),
        ('ג', const Pen(fg: blue)),
      ]);
      expect(v.show(p), ['ab גבא']);
      expect(v.fgAt(1, 0), Color.defaultColor);
      expect(v.fgAt(3, 0), blue);
      expect(v.fgAt(4, 0), red);
      expect(v.fgAt(5, 0), red);
    });

    test('a cell tells the cluster drawn there; left of the text the start, '
        'right of it the end', () {
      final v = View(10, 2);
      final p = RenderParagraph([('ab אבג', plain)]);
      expect(v.show(p), ['ab גבא']);
      expect(ranges(p, 0), [
        '0',
        '0-1',
        '1-2',
        '2-3',
        '5-6',
        '4-5',
        '3-4',
        '6',
        '6',
        '6',
        '6',
        '6',
      ]);
      final q = RenderParagraph([('שלום', plain)], align: TextAlign.start);
      expect(View(10, 1).show(q), ['      םולש']);
      expect(ranges(q, 0), [
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        '3-4',
        '2-3',
        '1-2',
        '0-1',
        '4',
      ]);
    });

    test('a cell of an ellipsis tells what it stands for', () {
      final v = View(8, 2);
      final p = RenderParagraph(
        [('שלום עולם יפה', plain)],
        wrap: TextWrap.none,
        overflow: TextOverflow.ellipsis,
      );
      expect(v.show(p), ['…וע םולש']);
      expect(ranges(p, 0).sublist(1, 3), ['7-13', '6-7']);
    });

    test('a gap a justified right-to-left line stretches goes with the space '
        'it widens', () {
      final v = View(9, 2);
      final p = RenderParagraph([
        ('אב גד הו זח', plain),
      ], align: TextAlign.justify);
      expect(v.show(p), ['וה דג  בא', '       חז']);
      expect(ranges(p, 0).sublist(1, 10), [
        '7-8',
        '6-7',
        '5-6',
        '4-5',
        '3-4',
        '2-3',
        '2-3',
        '1-2',
        '0-1',
      ]);
    });

    test('text without right-to-left characters is drawn as stored without '
        'being resolved', () {
      final v = View(20, 1);
      final p = RenderParagraph([('abc (def) 123 é', plain)]);
      expect(v.show(p), ['abc (def) 123 é']);
      expect(p.debugOffsetsFound, 0);
      final q = RenderParagraph([('abc אבג', plain)]);
      expect(View(20, 1).show(q), ['abc גבא']);
      expect(q.debugOffsetsFound, 1);
    });

    test('set on an owner whose tree is laid out, it lays the text out '
        'again', () {
      final v = View(12, 1, order: TextOrder.logical);
      final p = RenderParagraph([('abc אבג', plain)]);
      expect(v.show(p), ['abc אבג']);
      v.owner.textOrder = TextOrder.visual;
      expect(v.frame(), ['abc גבא']);
      p.spans = [('abc אבגד', plain)];
      expect(v.frame(), ['abc דגבא']);
      v.owner.textOrder = TextOrder.logical;
      expect(v.frame(), ['abc אבגד']);
    });
  });
}
