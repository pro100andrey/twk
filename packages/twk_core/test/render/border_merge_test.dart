// Lines merged where they meet: the canvas joining a piece of line with the
// one already in its cell, boxes sharing their edges and dividers across
// them in every type, mixed types, and merged lines that look unmerged
// where nothing is under them.
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';

const red = Color.rgb(200, 0, 0);
const green = Color.rgb(0, 200, 0);
const blue = Color.rgb(0, 0, 200);
const gray = Color.rgb(90, 90, 90);

/// A screen and what a tree of render objects paints on it.
final class View {
  View(this.width, this.height, {int ambiguousWidth = 1})
    : screen = Screen(width, height, ambiguousWidth: ambiguousWidth) {
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter);
  }

  final int width;
  final int height;
  final Screen screen;
  late final PipelineOwner owner;

  Canvas get canvas => screen.canvas;

  /// The id of [p] in the screen's style table.
  int pen([Pen p = const Pen()]) => screen.styles.pen(p);

  /// What [root] paints on the whole screen.
  List<String> show(RenderObject root) {
    owner.root = root;
    return frame();
  }

  /// Lays the tree out and paints what changed; returns the rows.
  List<String> frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    return rows();
  }

  /// Each row without the blanks that end it.
  List<String> rows() => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          if ((screen.surface.cells[y * width + x] & kCont) == 0)
            screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
      ].join().trimRight(),
  ];

  /// The glyph at [x], [y].
  String at(int x, int y) =>
      screen.glyphs.stringOf(screen.surface.cells[y * width + x]);

  Color fgAt(int x, int y) =>
      screen.styles.fgOf(screen.surface.styles[y * width + x]);

  Color bgAt(int x, int y) =>
      screen.styles.bgOf(screen.surface.styles[y * width + x]);

  /// Every cell: its glyph, text color and background.
  List<String> cells() => [
    for (var y = 0; y < height; y++)
      for (var x = 0; x < width; x++)
        '${at(x, y)} ${fgAt(x, y).value} ${bgAt(x, y).value}',
  ];
}

/// One cell of [glyph].
GlyphRun one(String glyph) =>
    GlyphRun(Uint32List(1)..[0] = glyph.codeUnitAt(0), 1);

/// [glyphs], one cell each.
GlyphRun runOf(String glyphs) =>
    GlyphRun(Uint32List.fromList(glyphs.codeUnits), glyphs.length);

/// What merging [glyph] into a cell holding [under] leaves in it.
String merged(String glyph, String under) {
  final v = View(1, 1);
  v.canvas
    ..run(0, 0, one(under), v.pen())
    ..mergeRun(0, 0, one(glyph), v.pen());
  return v.at(0, 0);
}

/// The piece of [type] that reaches out in [arms]: up 1, right 2, down 4,
/// left 8.
String piece(BorderType type, int arms) => String.fromCharCode(
  type.glyph(
    up: arms & 1 != 0,
    right: arms & 2 != 0,
    down: arms & 4 != 0,
    left: arms & 8 != 0,
  ),
);

/// [single] with each of its pieces replaced by the piece of [type].
List<String> drawnWith(BorderType type, List<String> single) {
  final to = <String, String>{
    for (var arms = 1; arms < 16; arms++)
      piece(.single, arms): piece(type, arms),
  };
  return [
    for (final row in single)
      [for (final c in row.split('')) to[c] ?? c].join().trimRight(),
  ];
}

/// [child] pinned in a stack at [left], [top], [width] × [height] cells.
RenderObject pin(
  RenderObject child,
  int left,
  int top,
  int width,
  int height,
) => child
  ..parentData = (StackParentData()
    ..left = left
    ..top = top
    ..width = width
    ..height = height);

/// A box with a border of [type] on the sides named in [on] (t, r, b, l).
RenderDecoratedBox box({
  BorderType type = .single,
  String on = 'trbl',
  bool merge = true,
  Pen pen = const Pen(),
  Pen? background,
}) => RenderDecoratedBox(
  background: background,
  border: BoxBorder(
    type: type,
    top: on.contains('t') ? pen : null,
    right: on.contains('r') ? pen : null,
    bottom: on.contains('b') ? pen : null,
    left: on.contains('l') ? pen : null,
    merge: merge,
  ),
);

/// The types that draw lines.
const List<BorderType> drawn = [
  BorderType.single,
  BorderType.rounded,
  BorderType.double,
  BorderType.heavy,
  BorderType.ascii,
];

/// The sets of arms with two arms or more: what borders and dividers draw
/// and what they leave where they meet.
final List<int> joints = [
  for (var a = 1; a < 16; a++)
    if (a & (a - 1) != 0) a,
];

void main() {
  group('Canvas.mergeRun', () {
    test('joins each piece of a type with each other piece of it', () {
      for (final type in drawn) {
        for (final a in joints) {
          for (final b in joints) {
            expect(
              merged(piece(type, a), piece(type, b)),
              piece(type, a | b),
              reason: '$type: ${piece(type, a)} over ${piece(type, b)}',
            );
          }
        }
      }
    });

    test('joins the half lines of single and heavy lines too', () {
      for (final type in const [BorderType.single, BorderType.heavy]) {
        for (var a = 1; a < 16; a++) {
          for (var b = 1; b < 16; b++) {
            expect(
              merged(piece(type, a), piece(type, b)),
              piece(type, a | b),
              reason: '$type: ${piece(type, a)} over ${piece(type, b)}',
            );
          }
        }
      }
    });

    test('keeps the weight of each arm where Unicode has the mix', () {
      // light and heavy mix in every way, light and double where the arms
      // across share a weight and so do those down
      const mixes = {
        '─┃': '╂',
        '━│': '┿',
        '┌┃': '┞',
        '┏│': '┢',
        '╭┃': '┞',
        '┐━': '┮',
        '─║': '╫',
        '═│': '╪',
        '═┌': '╤',
        '║─': '╫',
        '│╔': '╞',
      };
      for (final MapEntry(key: pair, value: glyph) in mixes.entries) {
        expect(merged(pair[0], pair[1]), glyph, reason: pair);
      }
    });

    test('draws every arm in the weight of the new piece elsewhere', () {
      const fallbacks = {
        // light and double, across or down of two weights
        '┌═': '┬',
        '╔│': '╠',
        // heavy and double never mix
        '━║': '╋',
        '║━': '╬',
      };
      for (final MapEntry(key: pair, value: glyph) in fallbacks.entries) {
        expect(merged(pair[0], pair[1]), glyph, reason: pair);
      }
    });

    test('an arm both have takes the weight of the new piece', () {
      expect(merged('│', '┃'), '│');
      expect(merged('━', '─'), '━');
      expect(merged('─', '╋'), '╂');
    });

    test('keeps a round corner it draws or adds nothing to', () {
      expect(merged('╭', '┌'), '╭');
      expect(merged('┌', '╭'), '┌');
      expect(merged('╶', '╭'), '╭');
      expect(merged('╭', '╭'), '╭');
      expect(merged('│', '╭'), '├');
    });

    test('merges dashed lines as solid ones', () {
      expect(merged('─', '┆'), '┼');
      expect(merged('│', '╍'), '┿');
    });

    test('merges ASCII only with ASCII, box drawing only with itself', () {
      const pairs = {
        '-|': '+',
        '|-': '+',
        '-+': '+',
        '+-': '+',
        '--': '-',
        '||': '|',
        '-│': '-',
        '─|': '─',
        '─+': '─',
      };
      for (final MapEntry(key: pair, value: glyph) in pairs.entries) {
        expect(merged(pair[0], pair[1]), glyph, reason: pair);
      }
    });

    test('keeps the text in its cell, draws over a blank, and draws what '
        'is no piece of line', () {
      expect(merged('─', 'x'), 'x');
      expect(merged('-', 'x'), 'x');
      expect(merged('─', ' '), '─');
      expect(merged(' ', '┼'), ' ');
      expect(merged('x', '─'), 'x');
    });

    test('keeps the style of the text it keeps, the pen under it painted '
        'first', () {
      final v = View(3, 1);
      v.canvas
        ..run(0, 0, runOf('x y'), v.pen(const Pen(fg: green)))
        ..mergeRun(
          0,
          0,
          runOf('───'),
          v.pen(const Pen(fg: red)),
          under: v.pen(const Pen(bg: blue)),
        );
      expect(v.rows(), ['x─y']);
      expect([v.fgAt(0, 0), v.bgAt(0, 0)], [green, blue]);
      expect([v.fgAt(1, 0), v.bgAt(1, 0)], [red, blue]);
      expect([v.fgAt(2, 0), v.bgAt(2, 0)], [green, blue]);
    });

    test('ends that join a line in their cell do not reach past it', () {
      List<String> across(String under, String line, {int trim = 10}) {
        final v = View(under.length, 1);
        v.canvas
          ..run(0, 0, runOf(under), v.pen())
          ..mergeRun(
            0,
            0,
            runOf(line),
            v.pen(),
            trimFirst: trim & 8,
            trimLast: trim & 2,
          );
        return v.rows();
      }

      expect(across('│ │', '───'), ['├─┤']);
      expect(across('   ', '───'), ['───']);
      expect(across('───', '───'), ['───']);
      expect(across('┐x└', '───'), ['┬x┴']);
      expect(across('┐ └', '───'), ['┬─┴']);
      expect(across('║ ║', '═══'), ['╠═╣']);
      expect(across('│ ║', '───'), ['├─╢']);
      expect(across('| |', '---'), ['+-+']);
      expect(across('│ │', '───', trim: 0), ['┼─┼']);
      // a line of one cell has both its ends in it
      expect(across('│', '─'), ['│']);
      expect(across(' ', '─'), ['─']);
    });

    test('paints each cell with the pen under it first, then its own', () {
      final v = View(2, 1);
      v.canvas
        ..run(0, 0, runOf('││'), v.pen(const Pen(fg: green, bg: gray)))
        ..mergeRun(0, 0, one('─'), v.pen(const Pen(fg: red)))
        ..mergeRun(
          1,
          0,
          one('─'),
          v.pen(const Pen(fg: red)),
          under: v.pen(const Pen(bg: blue)),
        );
      expect(v.rows(), ['┼┼']);
      expect([v.fgAt(0, 0), v.bgAt(0, 0)], [red, gray]);
      expect([v.fgAt(1, 0), v.bgAt(1, 0)], [red, blue]);
    });

    test('is clipped as run is, and keeps a wide glyph whole', () {
      final v = View(6, 2);
      final pen = v.pen();
      v.canvas.text(0, 0, '│你│', pen);
      v.screen.surface.clearDamage();
      v.canvas
        ..save()
        ..clipRect(0, 0, 2, 2);
      expect(
        v.canvas.mergeRun(0, 0, runOf('────'), pen),
        v.canvas.run(0, 1, runOf('────'), pen),
      );
      expect(v.canvas.mergeRun(0, 2, runOf('─'), pen), 0, reason: 'row out');
      v.canvas.restore();
      expect(v.rows(), ['┼你│', '──']);
      expect(
        (v.screen.surface.dirtyLo[0], v.screen.surface.dirtyHi[0]),
        (0, 1),
      );
    });
  });

  group('boxes that merge', () {
    test('side by side share their edge in every type', () {
      for (final type in BorderType.values) {
        expect(
          View(9, 3).show(
            RenderStack(
              children: [
                pin(box(type: type, merge: false), 0, 0, 5, 3),
                pin(box(type: type), 4, 0, 5, 3),
              ],
            ),
          ),
          drawnWith(type, ['┌───┬───┐', '│   │   │', '└───┴───┘']),
          reason: '$type',
        );
      }
    });

    test('cover the edge they share unless they merge', () {
      expect(
        View(9, 3).show(
          RenderStack(
            children: [
              pin(box(), 0, 0, 5, 3),
              pin(box(merge: false), 4, 0, 5, 3),
            ],
          ),
        ),
        ['┌───┌───┐', '│   │   │', '└───└───┘'],
      );
    });

    test('one above another and four around a point, in every type', () {
      for (final type in BorderType.values) {
        expect(
          View(5, 5).show(
            RenderStack(
              children: [
                pin(box(type: type), 0, 0, 5, 3),
                pin(box(type: type), 0, 2, 5, 3),
              ],
            ),
          ),
          drawnWith(type, ['┌───┐', '│   │', '├───┤', '│   │', '└───┘']),
          reason: '$type',
        );
        expect(
          View(9, 5).show(
            RenderStack(
              children: [
                for (final (x, y) in const [(0, 0), (4, 0), (0, 2), (4, 2)])
                  pin(box(type: type), x, y, 5, 3),
              ],
            ),
          ),
          drawnWith(type, [
            '┌───┬───┐',
            '│   │   │',
            '├───┼───┤',
            '│   │   │',
            '└───┴───┘',
          ]),
          reason: '$type',
        );
      }
    });

    test('nested in another join its sides, in every type', () {
      for (final type in BorderType.values) {
        expect(
          View(7, 5).show(
            RenderStack(
              children: [
                pin(box(type: type), 0, 0, 7, 5),
                pin(box(type: type), 0, 2, 7, 3),
                pin(box(type: type), 3, 2, 4, 3),
              ],
            ),
          ),
          drawnWith(type, [
            '┌─────┐',
            '│     │',
            '├──┬──┤',
            '│  │  │',
            '└──┴──┘',
          ]),
          reason: '$type',
        );
      }
    });

    test('end a side without a neighbour in a joint, in every type', () {
      for (final type in BorderType.values) {
        expect(
          View(7, 4).show(
            RenderStack(
              children: [
                pin(box(type: type), 0, 0, 7, 4),
                pin(box(type: type, on: 'rl'), 2, 0, 3, 4),
                pin(box(type: type, on: 't'), 0, 2, 7, 1),
              ],
            ),
          ),
          drawnWith(type, ['┌─┬─┬─┐', '│ │ │ │', '├─┼─┼─┤', '└─┴─┴─┘']),
          reason: '$type',
        );
      }
    });

    test('look as they do unmerged where nothing is under them', () {
      // pens that leave colors to the cells under them compose in the
      // order of drawing: unmerged, a corner over its side's pen
      const shared = (Pen(fg: red), Pen(fg: red), Pen(fg: red), Pen(fg: red));
      const own = (
        Pen(fg: red, bg: gray),
        Pen(fg: green, bg: blue),
        Pen(fg: blue, bg: green),
        Pen(fg: gray, bg: red),
      );
      const sizes = [(5, 4), (1, 1), (1, 3), (3, 1), (2, 2)];
      List<String> show(
        BorderType type,
        int sides,
        (Pen, Pen, Pen, Pen) pens,
        (int, int) size, {
        required bool merge,
      }) {
        final v = View(6, 5);
        final (w, h) = size;
        final (top, right, bottom, left) = pens;
        v.show(
          RenderStack(
            children: [
              pin(
                RenderDecoratedBox(
                  background: const Pen(fg: gray, bg: blue),
                  border: BoxBorder(
                    type: type,
                    top: sides & 1 != 0 ? top : null,
                    right: sides & 2 != 0 ? right : null,
                    bottom: sides & 4 != 0 ? bottom : null,
                    left: sides & 8 != 0 ? left : null,
                    merge: merge,
                  ),
                  titles: const [BoxTitle('ab')],
                ),
                1,
                1,
                w,
                h,
              ),
            ],
          ),
        );
        return v.cells();
      }

      for (final type in BorderType.values) {
        for (var sides = 0; sides < 16; sides++) {
          for (final pens in [shared, own]) {
            for (final size in sizes) {
              expect(
                show(type, sides, pens, size, merge: true),
                show(type, sides, pens, size, merge: false),
                reason: '$type on sides $sides in $pens at $size',
              );
            }
          }
        }
      }
    });

    test('keep the lines under their background, which fills the rest', () {
      final v = View(9, 3);
      expect(
        v.show(
          RenderStack(
            children: [
              pin(box(merge: false), 0, 0, 5, 3),
              pin(
                box(
                  pen: const Pen(fg: red),
                  background: const Pen(bg: blue),
                ),
                4,
                0,
                5,
                3,
              ),
            ],
          ),
        ),
        ['┌───┬───┐', '│   │   │', '└───┴───┘'],
      );
      expect(
        [v.bgAt(4, 0), v.bgAt(4, 1), v.bgAt(6, 1), v.bgAt(8, 2), v.bgAt(2, 1)],
        [blue, blue, blue, blue, Color.defaultColor],
      );
      expect(
        [v.fgAt(4, 0), v.fgAt(4, 1), v.fgAt(0, 0)],
        [
          red,
          red,
          Color.defaultColor,
        ],
      );
    });

    test('join in ASCII where the canvas draws box drawing two wide', () {
      expect(
        View(9, 4, ambiguousWidth: 2).show(
          RenderStack(
            children: [
              pin(box(merge: false), 0, 0, 5, 4),
              pin(box(type: .heavy), 4, 0, 5, 4),
              pin(box(type: .double, on: 't'), 0, 2, 9, 1),
            ],
          ),
        ),
        ['+---+---+', '|   |   |', '+---+---+', '+---+---+'],
      );
    });

    test('of mixed types mix where Unicode can, else take their own', () {
      List<String> pair(BorderType under, BorderType over) => View(9, 3).show(
        RenderStack(
          children: [
            pin(box(type: under, merge: false), 0, 0, 5, 3),
            pin(box(type: over), 4, 0, 5, 3),
          ],
        ),
      );
      expect(pair(.heavy, .single), ['┏━━━┭───┐', '┃   │   │', '┗━━━┵───┘']);
      expect(pair(.single, .double), ['┌───╦═══╗', '│   ║   ║', '└───╩═══╝']);
      expect(pair(.double, .single), ['╔═══┬───┐', '║   │   │', '╚═══┴───┘']);
      expect(pair(.single, .ascii), ['┌───+---+', '│   |   |', '└───+---+']);
      expect(pair(.ascii, .single), ['+---┌───┐', '|   │   │', '+---└───┘']);
    });

    test('keep the titles of the edges they cross or share', () {
      final titled = RenderDecoratedBox(
        border: const BoxBorder.all(merge: true),
        titles: const [
          BoxTitle('top'),
          BoxTitle('end', alignment: Alignment.bottomRight),
        ],
      );
      // a divider over the top edge, as a split view's with shared edges
      expect(
        View(9, 4).show(
          RenderStack(
            children: [
              pin(titled, 0, 0, 9, 4),
              pin(RenderDivider(merge: true), 0, 0, 9, 1),
            ],
          ),
        ),
        ['┌top────┐', '│       │', '│       │', '└────end┘'],
      );
      // a box below sharing the bottom edge
      expect(
        View(9, 6).show(
          RenderStack(
            children: [
              pin(
                RenderDecoratedBox(
                  border: const BoxBorder.all(merge: true),
                  titles: const [
                    BoxTitle('end', alignment: Alignment.bottomRight),
                  ],
                ),
                0,
                0,
                9,
                3,
              ),
              pin(box(), 0, 2, 9, 4),
            ],
          ),
        ),
        [
          '┌───────┐',
          '│       │',
          '├────end┤',
          '│       │',
          '│       │',
          '└───────┘',
        ],
      );
    });

    test('merging is a change of paint, not of layout', () {
      final b = box(merge: false);
      final v = View(9, 3)
        ..show(
          RenderStack(children: [pin(box(), 0, 0, 5, 3), pin(b, 4, 0, 5, 3)]),
        );
      b.border = const BoxBorder.all(merge: true);
      expect(b.debugNeedsLayout, isFalse);
      expect(v.frame(), ['┌───┬───┐', '│   │   │', '└───┴───┘']);
    });

    test('say they merge when described', () {
      final properties = DiagnosticPropertiesBuilder();
      box(on: 'tb').debugFillProperties(properties);
      expect(properties.properties.map((p) => '$p'), [
        'border: single top bottom merged',
      ]);
    });
  });

  group('dividers that merge', () {
    test('across a box join its sides, down it its edges, in every type', () {
      for (final type in BorderType.values) {
        expect(
          View(7, 5).show(
            RenderStack(
              children: [
                pin(box(type: type, merge: false), 0, 0, 7, 5),
                pin(RenderDivider(type: type, merge: true), 0, 2, 7, 1),
              ],
            ),
          ),
          drawnWith(type, [
            '┌─────┐',
            '│     │',
            '├─────┤',
            '│     │',
            '└─────┘',
          ]),
          reason: '$type',
        );
        expect(
          View(7, 5).show(
            RenderStack(
              children: [
                pin(box(type: type, merge: false), 0, 0, 7, 5),
                pin(
                  RenderDivider(direction: .vertical, type: type, merge: true),
                  3,
                  0,
                  1,
                  5,
                ),
              ],
            ),
          ),
          drawnWith(type, [
            '┌──┬──┐',
            '│  │  │',
            '│  │  │',
            '│  │  │',
            '└──┴──┘',
          ]),
          reason: '$type',
        );
      }
    });

    test('crossing each other meet in a cross, in every type', () {
      for (final type in BorderType.values) {
        expect(
          View(7, 5).show(
            RenderStack(
              children: [
                pin(box(type: type, merge: false), 0, 0, 7, 5),
                pin(RenderDivider(type: type, merge: true), 0, 2, 7, 1),
                pin(
                  RenderDivider(direction: .vertical, type: type, merge: true),
                  3,
                  0,
                  1,
                  5,
                ),
              ],
            ),
          ),
          drawnWith(type, [
            '┌──┬──┐',
            '│  │  │',
            '├──┼──┤',
            '│  │  │',
            '└──┴──┘',
          ]),
          reason: '$type',
        );
      }
    });

    test('of another type mix where Unicode can, else take their own', () {
      List<String> across(BorderType boxType, BorderType line) =>
          View(
            7,
            3,
          ).show(
            RenderStack(
              children: [
                pin(box(type: boxType, merge: false), 0, 0, 7, 3),
                pin(RenderDivider(type: line, merge: true), 0, 1, 7, 1),
              ],
            ),
          );
      expect(across(.double, .single), ['╔═════╗', '╟─────╢', '╚═════╝']);
      expect(across(.heavy, .single), ['┏━━━━━┓', '┠─────┨', '┗━━━━━┛']);
      expect(across(.heavy, .double), ['┏━━━━━┓', '╠═════╣', '┗━━━━━┛']);
      expect(across(.single, .heavy), ['┌─────┐', '┝━━━━━┥', '└─────┘']);
    });

    test('over nothing draw what they draw unmerged', () {
      for (final type in BorderType.values) {
        for (final direction in Axis.values) {
          List<String> show(bool merge) => View(3, 3).show(
            RenderDivider(direction: direction, type: type, merge: merge),
          );
          expect(show(true), show(false), reason: '$type $direction');
        }
      }
    });

    test('merging is a change of paint, not of layout', () {
      final line = RenderDivider();
      final v = View(5, 3);
      expect(
        v.show(
          RenderStack(
            children: [pin(box(), 0, 0, 5, 3), pin(line, 0, 1, 5, 1)],
          ),
        ),
        ['┌───┐', '─────', '└───┘'],
      );
      line.merge = true;
      expect(line.debugNeedsLayout, isFalse);
      expect(v.frame(), ['┌───┐', '├───┤', '└───┘']);
    });

    test('say they merge when described', () {
      final properties = DiagnosticPropertiesBuilder();
      RenderDivider(merge: true).debugFillProperties(properties);
      expect(properties.properties.map((p) => '$p'), ['merged']);
    });
  });
}
