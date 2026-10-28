// Boxes with a background, a border of each type on any sides, titles on
// their top and bottom edges and padding inside; dividers across. Every
// frame goes through the terminal emulator too, which must show what the
// screen holds.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

const red = Color.rgb(200, 0, 0);
const green = Color.rgb(0, 200, 0);
const blue = Color.rgb(0, 0, 200);
const gray = Color.rgb(90, 90, 90);

/// A screen and a terminal emulator that splits text as the screen does.
final class View {
  View(
    this.width,
    this.height, {
    TextMode mode = TextMode.graphemes,
    int ambiguousWidth = 1,
  }) : screen = Screen(
         width,
         height,
         textMode: mode,
         ambiguousWidth: ambiguousWidth,
       ),
       vt = Vt(
         width,
         height,
         segmenter: TextSegmenter(mode: mode, ambiguousWidth: ambiguousWidth),
       ) {
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter);
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

  /// A paragraph of [text].
  RenderParagraph text(String text) => RenderParagraph([(text, const Pen())]);

  /// What [root] paints on the whole screen.
  List<String> show(RenderObject root) {
    owner.root = root;
    return frame();
  }

  /// The text color of the cell at [x], [y].
  Color fgAt(int x, int y) {
    final fg = screen.styles.fgOf(screen.surface.styles[y * width + x]);
    expect(vt.cell(x, y).fg, fg.value, reason: 'the color the terminal shows');
    return fg;
  }

  /// The background of the cell at [x], [y].
  Color bgAt(int x, int y) {
    final bg = screen.styles.bgOf(screen.surface.styles[y * width + x]);
    expect(vt.cell(x, y).bg, bg.value, reason: 'the color the terminal shows');
    return bg;
  }
}

/// Fills all the room it gets with [char]; asks for nothing.
final class Fill extends RenderObject {
  Fill([this.char = '.']);

  final String char;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) => ctx.canvas.fill(
    0,
    0,
    width,
    height,
    ctx.canvas.styles.pen(const Pen()),
    char.codeUnitAt(0),
  );
}

/// [w] × [h] cells of '#', as far as the constraints allow; asks for that.
final class Block extends RenderObject {
  Block(this.w, this.h);

  final int w;
  final int h;
  BoxConstraints? got;

  @override
  void performLayout(BoxConstraints c) {
    got = c;
    width = c.constrainW(w);
    height = c.constrainH(h);
  }

  @override
  int computeMinIntrinsicWidth(int height) => w;

  @override
  int computeMaxIntrinsicWidth(int height) => 2 * w;

  @override
  int computeMinIntrinsicHeight(int width) => h;

  @override
  int computeMaxIntrinsicHeight(int width) => 2 * h;

  @override
  void paint(PaintContext ctx) => ctx.canvas.fill(
    0,
    0,
    width,
    height,
    ctx.canvas.styles.pen(const Pen()),
    0x23,
  );
}

/// Fills itself with 'x' and lays its child out at its top left within
/// [limits] (its own constraints when null), using its size; counts its
/// layouts.
final class Holder extends RenderObject with RenderObjectWithChildMixin {
  Holder(RenderObject child, [this.limits]) {
    this.child = child;
  }

  BoxConstraints? limits;
  var layouts = 0;

  @override
  void performLayout(BoxConstraints c) {
    layouts++;
    width = c.maxW;
    height = c.maxH;
    child!.layout(
      limits ?? BoxConstraints(0, c.maxW, 0, c.maxH),
      parentUsesSize: true,
    );
  }

  @override
  void paint(PaintContext ctx) {
    ctx.canvas.fill(
      0,
      0,
      width,
      height,
      ctx.canvas.styles.pen(const Pen()),
      0x78,
    );
    paintChild(ctx, child!);
  }
}

/// [single] with each of its pieces replaced by the piece of [type].
List<String> drawnWith(BorderType type, List<String> single) {
  final to = <String, String>{};
  for (var arms = 1; arms < 16; arms++) {
    to[String.fromCharCode(piece(BorderType.single, arms))] =
        String.fromCharCode(piece(type, arms));
  }
  return [
    for (final row in single)
      [for (final c in row.split('')) to[c] ?? c].join().trimRight(),
  ];
}

/// The piece of [type] that reaches out in [arms]: up 1, right 2, down 4,
/// left 8.
int piece(BorderType type, int arms) => type.glyph(
  up: arms & 1 != 0,
  right: arms & 2 != 0,
  down: arms & 4 != 0,
  left: arms & 8 != 0,
);

/// What a 5 × 4 box shows around a child of dots, for each set of sides
/// with a border (t, r, b, l), drawn with [BorderType.single].
const sides = {
  '': ['.....', '.....', '.....', '.....'],
  't': ['─────', '.....', '.....', '.....'],
  'r': ['....│', '....│', '....│', '....│'],
  'b': ['.....', '.....', '.....', '─────'],
  'l': ['│....', '│....', '│....', '│....'],
  'tr': ['────┐', '....│', '....│', '....│'],
  'tb': ['─────', '.....', '.....', '─────'],
  'tl': ['┌────', '│....', '│....', '│....'],
  'rb': ['....│', '....│', '....│', '────┘'],
  'rl': ['│...│', '│...│', '│...│', '│...│'],
  'bl': ['│....', '│....', '│....', '└────'],
  'trb': ['────┐', '....│', '....│', '────┘'],
  'trl': ['┌───┐', '│...│', '│...│', '│...│'],
  'tbl': ['┌────', '│....', '│....', '└────'],
  'rbl': ['│...│', '│...│', '│...│', '└───┘'],
  'trbl': ['┌───┐', '│...│', '│...│', '└───┘'],
};

/// A border of [type] on the sides named in [on] (t, r, b, l), in [pen].
BoxBorder border(
  String on, {
  BorderType type = .single,
  Pen pen = const Pen(),
}) => BoxBorder(
  type: type,
  top: on.contains('t') ? pen : null,
  right: on.contains('r') ? pen : null,
  bottom: on.contains('b') ? pen : null,
  left: on.contains('l') ? pen : null,
);

/// The top row of a box [width] wide with a border on every side and
/// [titles].
String top(int width, List<BoxTitle> titles, {View? view}) {
  final v = view ?? View(width, 3);
  return v.show(
    RenderDecoratedBox(border: const BoxBorder.all(), titles: titles),
  )[0];
}

void main() {
  group('BorderType', () {
    test('has a piece for every set of directions a line reaches out in', () {
      // the straight lines, the half lines, the corners, the joints
      const pieces = [5, 10, 1, 2, 4, 8, 6, 12, 3, 9, 7, 13, 14, 11, 15];
      String all(BorderType t) =>
          String.fromCharCodes([for (final a in pieces) piece(t, a)]);
      expect(all(.single), '│─╵╶╷╴┌┐└┘├┤┬┴┼');
      expect(all(.rounded), '│─╵╶╷╴╭╮╰╯├┤┬┴┼');
      expect(all(.double), '║═║═║═╔╗╚╝╠╣╦╩╬');
      expect(all(.heavy), '┃━╹╺╻╸┏┓┗┛┣┫┳┻╋');
      expect(all(.ascii), '|-|-|-+++++++++');
      expect(all(.none), ' ' * 15);
      for (final t in BorderType.values) {
        expect(piece(t, 0), 0x20, reason: '$t without arms');
      }
    });
  });

  group('RenderDecoratedBox', () {
    test('draws each type on every set of sides', () {
      for (final type in BorderType.values) {
        for (final MapEntry(key: on, value: rows) in sides.entries) {
          final v = View(5, 4);
          expect(
            v.show(
              RenderDecoratedBox(
                border: border(on, type: type),
                child: Fill(),
              ),
            ),
            drawnWith(type, rows),
            reason: '$type on "$on"',
          );
        }
      }
    });

    test('draws ASCII where the canvas draws box drawing two columns wide', () {
      for (final mode in TextMode.values) {
        for (final type in BorderType.values) {
          final v = View(5, 4, mode: mode, ambiguousWidth: 2);
          expect(
            v.show(
              RenderDecoratedBox(
                border: border('trbl', type: type),
                child: Fill(),
              ),
            ),
            type == .none
                ? ['', ' ...', ' ...', '']
                : ['+---+', '|...|', '|...|', '+---+'],
            reason: '$type in $mode',
          );
        }
      }
    });

    test('draws each side in its pen, a corner in its top or bottom one', () {
      final v = View(4, 3)
        ..show(
          RenderDecoratedBox(
            border: const BoxBorder(
              top: Pen(fg: red),
              right: Pen(fg: green),
              bottom: Pen(fg: blue),
              left: Pen(fg: gray),
            ),
          ),
        );
      expect(
        [v.fgAt(1, 0), v.fgAt(3, 1), v.fgAt(1, 2), v.fgAt(0, 1)],
        [red, green, blue, gray],
      );
      expect(
        [v.fgAt(0, 0), v.fgAt(3, 0), v.fgAt(0, 2), v.fgAt(3, 2)],
        [red, red, blue, blue],
      );
    });

    test('a side whose neighbour has no border runs on to the corner', () {
      final v = View(4, 3)
        ..show(
          RenderDecoratedBox(
            border: const BoxBorder(
              right: Pen(fg: green),
              bottom: Pen(fg: blue),
              left: Pen(fg: gray),
            ),
          ),
        );
      expect([v.fgAt(0, 0), v.fgAt(3, 0)], [gray, green]);
      expect([v.fgAt(0, 2), v.fgAt(3, 2)], [blue, blue]);
    });

    test('blank lines of type none show the background of their pen', () {
      final v = View(4, 3);
      expect(
        v.show(
          RenderDecoratedBox(
            border: const BoxBorder.all(
              type: .none,
              pen: Pen(bg: blue),
            ),
            child: Fill(),
          ),
        ),
        ['', ' ..', ''],
      );
      expect(
        [v.bgAt(0, 0), v.bgAt(3, 1), v.bgAt(1, 1)],
        [
          blue,
          blue,
          Color.defaultColor,
        ],
      );
    });

    test('fills itself with its background, under the border and child', () {
      final v = View(6, 4);
      final box = RenderDecoratedBox(
        background: const Pen(bg: blue),
        border: const BoxBorder.all(pen: Pen(fg: red)),
        padding: const EdgeInsets.only(right: 1),
        child: Block(1, 1),
      );
      expect(v.show(Holder(box)), [
        '┌──┐xx',
        '│# │xx',
        '└──┘xx',
        'xxxxxx',
      ]);
      expect(
        [v.bgAt(0, 0), v.bgAt(2, 1), v.bgAt(1, 1), v.fgAt(0, 0), v.bgAt(4, 0)],
        [blue, blue, blue, red, Color.defaultColor],
      );
    });

    test('without a background leaves what is under it', () {
      final v = View(5, 2);
      expect(
        v.show(
          Holder(
            RenderDecoratedBox(
              border: border('l'),
              padding: const EdgeInsets.only(right: 1),
              child: Block(1, 1),
            ),
          ),
        ),
        ['│#xxx', 'xxxxx'],
      );
    });

    test('a border pen without colors takes those of the background', () {
      final v = View(3, 3)
        ..show(
          RenderDecoratedBox(
            background: const Pen(fg: red, bg: blue),
            border: const BoxBorder.all(),
          ),
        );
      expect([v.fgAt(0, 0), v.bgAt(0, 0)], [red, blue]);
    });
  });

  group('titles', () {
    test('go at the left, in the middle or at the right of their edge', () {
      const titles = [
        BoxTitle('L'),
        BoxTitle('C', alignment: .topCenter),
        BoxTitle('R', alignment: .topRight),
        BoxTitle('l', alignment: .bottomLeft),
        BoxTitle('c', alignment: .bottomCenter),
        BoxTitle('r', alignment: .bottomRight),
      ];
      expect(
        View(12, 3).show(
          RenderDecoratedBox(border: const BoxBorder.all(), titles: titles),
        ),
        ['┌L───C────R┐', '│          │', '└l───c────r┘'],
      );
      // the odd cell after the middle one
      expect(
        top(11, [const BoxTitle('C', alignment: .topCenter)]),
        '┌────C────┐',
      );
      expect(
        top(11, [const BoxTitle('CC', alignment: .topCenter)]),
        '┌───CC────┐',
      );
    });

    test('of one alignment follow one another a cell apart', () {
      const titles = [
        BoxTitle('ab'),
        BoxTitle('cd'),
        BoxTitle('ef', alignment: .topRight),
        BoxTitle('gh', alignment: .topRight),
        BoxTitle('i', alignment: .topCenter),
        BoxTitle('j', alignment: .topCenter),
      ];
      expect(top(18, titles), '┌ab─cd─i─j──ef─gh┐');
    });

    test('in the middle stay between those at the ends', () {
      expect(
        top(12, [
          const BoxTitle('abcd'),
          const BoxTitle('XY', alignment: .topCenter),
        ]),
        '┌abcd─XY───┐',
      );
      expect(
        top(12, [
          const BoxTitle('XY', alignment: .topCenter),
          const BoxTitle('abcd', alignment: .topRight),
        ]),
        '┌───XY─abcd┐',
      );
      // no room between them
      expect(
        top(12, [
          const BoxTitle('abcd'),
          const BoxTitle('XY', alignment: .topCenter),
          const BoxTitle('efgh', alignment: .topRight),
        ]),
        '┌abcd──efgh┐',
      );
    });

    test('get the room those placed before them leave', () {
      // the left ones first, then the right ones from the last
      expect(
        top(12, [
          const BoxTitle('abcdefg'),
          const BoxTitle('xyz', alignment: .topRight),
        ]),
        '┌abcdefg─x…┐',
      );
      expect(
        top(12, [
          const BoxTitle('abcdefghijkl'),
          const BoxTitle('xyz', alignment: .topRight),
        ]),
        '┌abcdefghi…┐',
      );
      expect(
        top(13, [
          const BoxTitle('uvw', alignment: .topRight),
          const BoxTitle('xyz', alignment: .topRight),
          const BoxTitle('abcde'),
        ]),
        '┌abcde─…─xyz┐',
      );
    });

    test('too long for their edge are cut off with an ellipsis', () {
      expect(top(8, [const BoxTitle('Settings')]), '┌Setti…┐');
      expect(top(8, [const BoxTitle('Settin')]), '┌Settin┐');
      // no blank before the ellipsis
      expect(top(6, [const BoxTitle('ab cdef')]), '┌ab…─┐');
      expect(top(3, [const BoxTitle('abc')]), '┌…┐');
      expect(top(2, [const BoxTitle('abc')]), '┌┐');
      // without side borders the whole edge is theirs
      expect(
        View(6, 1).show(
          RenderDecoratedBox(
            border: border('t'),
            titles: const [BoxTitle('abcdefgh')],
          ),
        ),
        ['abcde…'],
      );
    });

    test('never split a wide glyph', () {
      for (final mode in TextMode.values) {
        View v(int w) => View(w, 3, mode: mode);
        expect(top(7, [const BoxTitle('漢字かな')], view: v(7)), '┌漢字…┐');
        expect(top(6, [const BoxTitle('漢字かな')], view: v(6)), '┌漢…─┐');
        expect(top(4, [const BoxTitle('漢字かな')], view: v(4)), '┌…─┐');
        expect(top(7, [const BoxTitle('a漢字')], view: v(7)), '┌a漢字┐');
        expect(top(6, [const BoxTitle('a漢字')], view: v(6)), '┌a漢…┐');
        expect(top(5, [const BoxTitle('a漢字')], view: v(5)), '┌a…─┐');
        expect(top(6, [const BoxTitle('👍👍👍')], view: v(6)), '┌👍…─┐');
      }
      // one grapheme where the terminal joins the sequence
      expect(top(6, [const BoxTitle('👨‍👩‍👧x')]), '┌👨‍👩‍👧x─┐');
      expect(top(5, [const BoxTitle('👨‍👩‍👧xy')]), '┌👨‍👩‍👧…┐');
    });

    test('with a two-column ellipsis', () {
      final v = View(6, 3, ambiguousWidth: 2);
      expect(top(6, [const BoxTitle('abcdef')], view: v), '+ab…+');
      final w = View(4, 3, ambiguousWidth: 2);
      expect(top(4, [const BoxTitle('abc')], view: w), '+…+');
      // no room for it: cut off without one
      final x = View(3, 3, ambiguousWidth: 2);
      expect(top(3, [const BoxTitle('abc')], view: x), '+a+');
      final y = View(3, 3, ambiguousWidth: 2);
      expect(top(3, [const BoxTitle('漢')], view: y), '+-+');
    });

    test('on an edge without a border take a row of their own', () {
      final box = RenderDecoratedBox(
        border: border('l'),
        titles: const [
          BoxTitle('T', alignment: .topRight),
          BoxTitle('B', alignment: .bottomCenter),
        ],
        child: Fill(),
      );
      expect(View(5, 4).show(box), ['│   T', '│....', '│....', '│ B']);
      expect(box.insets, const EdgeInsets.only(left: 1, top: 1, bottom: 1));
      expect(box.inner, (1, 1, 4, 2));
      expect(
        View(4, 3).show(
          RenderDecoratedBox(titles: const [BoxTitle('top')], child: Fill()),
        ),
        ['top', '....', '....'],
      );
    });

    test('are drawn in their pens over the line', () {
      final v = View(8, 3)
        ..show(
          RenderDecoratedBox(
            border: const BoxBorder.all(
              pen: Pen(fg: red, bg: gray),
            ),
            titles: const [
              BoxTitle('ab', pen: Pen(fg: blue)),
              BoxTitle('cd', alignment: .bottomRight),
            ],
          ),
        );
      expect([v.fgAt(1, 0), v.bgAt(1, 0), v.fgAt(5, 2)], [blue, gray, red]);
    });

    test('are cut off in their pen, the ellipsis too', () {
      final v = View(5, 3);
      expect(
        v.show(
          RenderDecoratedBox(
            border: const BoxBorder.all(pen: Pen(fg: red)),
            titles: const [BoxTitle('abcd', pen: Pen(fg: blue))],
          ),
        )[0],
        '┌ab…┐',
      );
      expect([v.fgAt(2, 0), v.fgAt(3, 0), v.fgAt(4, 0)], [blue, blue, red]);
    });
  });

  group('layout', () {
    test('insets the child by the border and the padding', () {
      final box = RenderDecoratedBox(
        border: const BoxBorder.all(type: .rounded),
        padding: const EdgeInsets.only(left: 2, top: 1, right: 1),
        child: Fill(),
      );
      expect(View(8, 5).show(box), [
        '╭──────╮',
        '│      │',
        '│  ... │',
        '│  ... │',
        '╰──────╯',
      ]);
      expect(
        box.insets,
        const EdgeInsets.only(left: 3, top: 2, right: 2, bottom: 1),
      );
      expect(box.inner, (3, 2, 3, 2));
    });

    test('padding without a border', () {
      final box = RenderDecoratedBox(
        padding: const EdgeInsets.x(1),
        child: Fill(),
      );
      expect(View(4, 2).show(box), [' ..', ' ..']);
      expect(box.inner, (1, 0, 2, 2));
    });

    test('is as big as its child and its insets, within its constraints', () {
      final child = Block(2, 1);
      final box = RenderDecoratedBox(
        border: const BoxBorder.all(),
        padding: const EdgeInsets.only(left: 1),
        child: child,
      );
      final holder = Holder(box);
      final v = View(8, 4);
      expect(v.show(holder), ['┌───┐xxx', '│x##│xxx', '└───┘xxx', 'xxxxxxxx']);
      expect((box.width, box.height), (5, 3));
      expect(child.got, const BoxConstraints(0, 5, 0, 2));
      // the insets taken off the minimum too
      holder
        ..limits = const BoxConstraints(6, 8, 4, 4)
        ..markNeedsLayout();
      v.frame();
      expect((box.width, box.height), (6, 4));
      expect(child.got, const BoxConstraints(3, 5, 2, 2));
      expect(box.inner, (2, 1, 3, 2));
    });

    test('is as wide as its titles', () {
      final box = RenderDecoratedBox(
        border: const BoxBorder.all(),
        titles: const [
          BoxTitle('ab'),
          BoxTitle('cd', alignment: .topRight),
        ],
        child: Block(1, 1),
      );
      expect(View(9, 3).show(Holder(box)), [
        '┌ab─cd┐xx',
        '│#xxxx│xx',
        '└─────┘xx',
      ]);
      expect(box.width, 7);
    });

    test('without a child is as big as the constraints allow', () {
      final box = RenderDecoratedBox(border: const BoxBorder.all());
      final holder = Holder(box);
      final v = View(4, 3);
      expect(v.show(holder), ['┌──┐', '│xx│', '└──┘']);
      // as small along an axis they leave unbounded
      holder
        ..limits = const BoxConstraints(0, 3, 0, BoxConstraints.unbounded)
        ..markNeedsLayout();
      expect(v.frame(), ['┌─┐x', '└─┘x', 'xxxx']);
      expect((box.width, box.height), (3, 2));
      holder.limits = const BoxConstraints(
        0,
        BoxConstraints.unbounded,
        0,
        BoxConstraints.unbounded,
      );
      box.titles = const [BoxTitle('ab')];
      expect(v.frame(), ['┌ab┐', '└──┘', 'xxxx']);
      expect((box.width, box.height), (4, 2));
    });

    test('asks for what its child asks inside its insets, the titles too', () {
      final box = RenderDecoratedBox(
        border: border('trl'),
        titles: const [BoxTitle('abcdefgh', alignment: .bottomLeft)],
        padding: const EdgeInsets.only(left: 1, top: 2),
        child: Block(3, 2),
      );
      // left 2, right 1; top 3, bottom 1 (the titles' row)
      expect(box.getMinIntrinsicWidth(10), 3 + 3);
      expect(box.getMaxIntrinsicWidth(10), 8 + 2);
      expect(box.getMinIntrinsicHeight(10), 4 + 2);
      expect(box.getMaxIntrinsicHeight(10), 4 + 4);
      box.titles = const [];
      expect(box.getMaxIntrinsicWidth(10), 3 + 6);
      expect(
        RenderDecoratedBox(padding: const EdgeInsets.all(1))
            .getMaxIntrinsicWidth(5),
        2,
      );
    });
  });

  group('changes', () {
    test('new pens and a new border type repaint without a layout', () {
      final box = RenderDecoratedBox(
        border: const BoxBorder.all(),
        titles: const [BoxTitle('ab')],
        child: Block(2, 1),
      );
      final holder = Holder(box);
      final v = View(6, 3)..show(holder);
      final layouts = holder.layouts;
      box
        ..background = const Pen(bg: gray)
        ..border = const BoxBorder.all(
          type: .double,
          pen: Pen(fg: red),
        )
        ..titles = const [BoxTitle('ab', pen: Pen(fg: blue))];
      expect(v.frame(), ['╔ab╗xx', '║##║xx', '╚══╝xx']);
      expect([v.bgAt(1, 1), v.fgAt(0, 0), v.fgAt(1, 0)], [gray, red, blue]);
      expect(holder.layouts, layouts);
    });

    test('new sides, padding or titles lay it out again', () {
      final box = RenderDecoratedBox(
        border: const BoxBorder.all(),
        child: Block(2, 1),
      );
      final holder = Holder(box);
      final v = View(7, 3);
      expect(v.show(holder), ['┌──┐xxx', '│##│xxx', '└──┘xxx']);
      var layouts = holder.layouts;
      box.border = border('tb');
      expect(v.frame(), ['──xxxxx', '##xxxxx', '──xxxxx']);
      expect(holder.layouts, ++layouts);
      box.padding = const EdgeInsets.only(left: 1);
      expect(v.frame(), ['───xxxx', 'x##xxxx', '───xxxx']);
      expect(holder.layouts, ++layouts);
      box.titles = const [BoxTitle('abcde')];
      expect(v.frame(), ['abcdexx', 'x##xxxx', '─────xx']);
      expect(holder.layouts, ++layouts);
      box.titles = const [BoxTitle('abcde', alignment: .topRight)];
      v.frame();
      expect(holder.layouts, ++layouts);
      // the same in other objects: nothing to do
      box
        ..titles = [const BoxTitle('abcde', alignment: .topRight)]
        ..border = border('tb');
      expect(v.owner.hasWork, isFalse);
    });

    test('titles measured again for an owner that measures otherwise', () {
      // Greek is East Asian ambiguous
      final box = RenderDecoratedBox(
        border: const BoxBorder.all(),
        titles: const [BoxTitle('αβ')],
      );
      final holder = Holder(
        box,
        const BoxConstraints(0, BoxConstraints.unbounded, 0, 3),
      );
      final a = View(8, 3);
      expect(a.show(holder)[0], '┌αβ┐xxxx');
      a.owner.root = Fill();
      final b = View(8, 3, ambiguousWidth: 2);
      expect(b.show(holder)[0], '+αβ+xx');
    });

    test('titles shaped again for another screen', () {
      final box = RenderDecoratedBox(
        border: const BoxBorder.all(),
        titles: const [BoxTitle('👨‍👩‍👧')],
      );
      final a = View(4, 3);
      expect(a.show(box)[0], '┌👨‍👩‍👧┐');
      a.owner.root = Fill();
      final b = View(4, 3);
      expect(b.show(box)[0], '┌👨‍👩‍👧┐');
    });
  });

  group('RenderDivider', () {
    test('draws a line across or down the room it gets in each type', () {
      for (final type in BorderType.values) {
        final across = String.fromCharCode(piece(type, 10));
        final down = String.fromCharCode(piece(type, 5));
        expect(
          View(4, 1).show(RenderDivider(type: type)),
          [(across * 4).trimRight()],
          reason: '$type',
        );
        expect(
          View(1, 2).show(RenderDivider(direction: .vertical, type: type)),
          [down.trimRight(), down.trimRight()],
          reason: '$type',
        );
      }
    });

    test('draws ASCII where the canvas draws box drawing two columns wide', () {
      for (final type in const [
        BorderType.single,
        BorderType.double,
        BorderType.heavy,
      ]) {
        expect(
          View(3, 1, ambiguousWidth: 2).show(RenderDivider(type: type)),
          ['---'],
        );
        expect(
          View(1, 2, ambiguousWidth: 2).show(
            RenderDivider(direction: .vertical, type: type),
          ),
          ['|', '|'],
        );
      }
    });

    test('in its pen', () {
      final v = View(3, 1)
        ..show(
          RenderDivider(
            pen: const Pen(fg: red, bg: blue),
          ),
        );
      expect([v.fgAt(0, 0), v.bgAt(2, 0)], [red, blue]);
    });

    test('is a row (a column) across the line, in the middle of more', () {
      final v = View(3, 5);
      expect(
        v.show(
          RenderFlex(
            direction: .vertical,
            children: [v.text('ab'), RenderDivider(), v.text('cd')],
          ),
        ),
        ['ab', '───', 'cd', '', ''],
      );
      final w = View(5, 2);
      expect(
        w.show(
          RenderFlex(
            children: [
              w.text('a'),
              RenderDivider(direction: .vertical),
              w.text('b'),
            ],
          ),
        ),
        ['a│b', ' │'],
      );
      expect(View(3, 4).show(RenderDivider()), ['', '───', '', '']);
      expect(View(3, 3).show(RenderDivider(direction: .vertical)), [
        ' │',
        ' │',
        ' │',
      ]);
    });

    test('as short as the constraints allow along an unbounded axis', () {
      final d = RenderDivider();
      View(4, 3).show(
        Holder(d, const BoxConstraints(2, BoxConstraints.unbounded, 0, 3)),
      );
      expect((d.width, d.height), (2, 1));
      final e = RenderDivider(direction: .vertical);
      View(4, 3).show(
        Holder(e, const BoxConstraints(0, 4, 1, BoxConstraints.unbounded)),
      );
      expect((e.width, e.height), (1, 1));
    });

    test('asks for a row (a column) across the line and nothing along it', () {
      final d = RenderDivider();
      expect(
        [
          d.getMinIntrinsicWidth(3),
          d.getMaxIntrinsicWidth(3),
          d.getMinIntrinsicHeight(3),
          d.getMaxIntrinsicHeight(3),
        ],
        [0, 0, 1, 1],
      );
      final e = RenderDivider(direction: .vertical);
      expect(
        [
          e.getMinIntrinsicWidth(3),
          e.getMaxIntrinsicWidth(3),
          e.getMinIntrinsicHeight(3),
          e.getMaxIntrinsicHeight(3),
        ],
        [1, 1, 0, 0],
      );
    });

    test('a new direction reaches the parent; a new type or pen repaints', () {
      final v = View(5, 2);
      final d = RenderDivider(direction: .vertical);
      final row = RenderFlex(children: [v.text('a'), d, v.text('b')]);
      (d.parentData as FlexParentData)
        ..flex = 1
        ..fit = .loose;
      expect(v.show(row), ['a│b', ' │']);
      d.direction = .horizontal;
      expect(v.frame(), ['a───b', '']);
      d
        ..type = .heavy
        ..pen = const Pen(fg: red);
      expect(v.frame(), ['a━━━b', '']);
      expect(v.fgAt(1, 0), red);
      d.merge = true;
      expect(
        (d.direction, d.type, d.pen, d.merge),
        (Axis.horizontal, BorderType.heavy, const Pen(fg: red), true),
      );
    });
  });

  group('values', () {
    test('borders are equal when their type, pens and merge are', () {
      const all = BoxBorder.all(pen: Pen(fg: red));
      const sides = BoxBorder(
        top: Pen(fg: red),
        right: Pen(fg: red),
        bottom: Pen(fg: red),
        left: Pen(fg: red),
      );
      expect(all, sides);
      expect(all.hashCode, sides.hashCode);
      expect(all, isNot(const BoxBorder.all(pen: Pen(fg: red), merge: true)));
      expect(
        all,
        isNot(
          const BoxBorder.all(
            type: .heavy,
            pen: Pen(fg: red),
          ),
        ),
      );
      expect(all, isNot(border('trb', pen: const Pen(fg: red))));
    });

    test('titles are equal when their text, pen and alignment are', () {
      const a = BoxTitle('a', pen: Pen(fg: red));
      expect(a, const BoxTitle('a', pen: Pen(fg: red)));
      expect(a.hashCode, const BoxTitle('a', pen: Pen(fg: red)).hashCode);
      expect(a, isNot(const BoxTitle('b', pen: Pen(fg: red))));
      expect(a, isNot(const BoxTitle('a')));
      expect(
        a,
        isNot(
          const BoxTitle(
            'a',
            pen: Pen(fg: red),
            alignment: .topRight,
          ),
        ),
      );
    });
  });

  test("a box's properties read back as set, the defaults until then", () {
    final box = RenderDecoratedBox();
    expect(
      (box.background, box.border, box.titles, box.padding),
      (null, null, const <BoxTitle>[], EdgeInsets.zero),
    );
    box
      ..background = const Pen(bg: blue)
      ..border = border('tb')
      ..titles = const [BoxTitle('t')]
      ..padding = const EdgeInsets.x(1);
    expect(
      (box.background, box.border, box.titles, box.padding),
      (
        const Pen(bg: blue),
        border('tb'),
        const [BoxTitle('t')],
        const EdgeInsets.x(1),
      ),
    );
  });

  test('a title cut off on a screen that draws the ellipsis one column '
      'wide, then on one that draws it two, ends in an ellipsis that '
      'wide', () {
    final box = RenderDecoratedBox(
      border: const BoxBorder.all(),
      titles: const [BoxTitle('abcdef')],
    );
    expect(View(6, 3).show(box)[0], '┌abc…┐');
    expect(View(6, 3, ambiguousWidth: 2).show(box)[0], '+ab…+');
  });
}
