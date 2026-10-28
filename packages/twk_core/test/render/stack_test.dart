// A stack lays its children out on top of each other: those it places by
// its alignment first, then those pinned to its edges, and paints them in
// order. A repaint boundary under another child repaints on its own
// without erasing what is above it; those frames go through the terminal
// emulator too, which must show what the screen holds.
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/vt.dart';

/// A screen and a terminal emulator.
final class View {
  View(this.width, this.height)
    : screen = Screen(width, height),
      vt = Vt(width, height) {
    owner = PipelineOwner(() {}, segmenter: screen.canvas.segmenter);
  }

  final int width;
  final int height;
  final Screen screen;
  final Vt vt;
  late final PipelineOwner owner;

  /// Lays the tree out, paints what changed and shows the frame to the
  /// emulator; returns the rows of the screen.
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

  /// What [root] paints on the whole screen.
  List<String> show(RenderObject root) {
    owner.root = root;
    return frame();
  }

  /// A pen with an opaque background, as a repaint boundary needs.
  late final int opaque = screen.styles.pen(
    const Pen(bg: Color.rgb(0, 0, 0)),
  );
}

/// One line of [text] (one column per character), as wide as the text
/// within the constraints; keeps the constraints it was last laid out with
/// and counts its paints.
final class Label extends RenderObject {
  Label(this.text);

  final String text;
  BoxConstraints? got;
  var paints = 0;

  @override
  void performLayout(BoxConstraints c) {
    got = c;
    width = c.constrainW(text.length);
    height = c.constrainH(1);
  }

  @override
  int computeMinIntrinsicWidth(int height) => text.length;

  @override
  int computeMaxIntrinsicWidth(int height) => text.length;

  @override
  int computeMinIntrinsicHeight(int width) => 1;

  @override
  int computeMaxIntrinsicHeight(int width) => 1;

  @override
  void paint(PaintContext ctx) {
    paints++;
    ctx.canvas.text(0, 0, text, ctx.canvas.styles.pen(const Pen()));
  }
}

/// [text] on [h] rows, [w] × [h] whatever the constraints say.
final class Stubborn extends RenderObject {
  Stubborn(this.text, this.w, this.h);

  final String text;
  final int w;
  final int h;

  @override
  void performLayout(BoxConstraints c) {
    width = w;
    height = h;
  }

  @override
  void paint(PaintContext ctx) {
    for (var y = 0; y < h; y++) {
      ctx.canvas.text(0, y, text, ctx.canvas.styles.pen(const Pen()));
    }
  }
}

/// Fills all the room it gets with [char]; keeps the constraints it was
/// last laid out with.
final class Fill extends RenderObject {
  Fill(this.char);

  final String char;
  BoxConstraints? got;

  @override
  void performLayout(BoxConstraints c) {
    got = c;
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

/// A repaint boundary that fills all the room it gets with [char] in an
/// opaque [pen]; a new [char] repaints it on its own. Counts its paints.
final class Panel extends RenderObject {
  Panel(this._char, this.pen);

  String _char;
  final int pen;
  var paints = 0;

  String get char => _char;
  set char(String c) {
    _char = c;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    ctx.canvas.fill(0, 0, width, height, pen, _char.codeUnitAt(0));
  }
}

/// Asks for [minW], [maxW], [minH] and [maxH] at any extent.
final class Probe extends RenderObject {
  Probe({this.minW = 0, this.maxW = 0, this.minH = 0, this.maxH = 0});

  final int minW;
  final int maxW;
  final int minH;
  final int maxH;

  @override
  int computeMinIntrinsicWidth(int height) => minW;

  @override
  int computeMaxIntrinsicWidth(int height) => maxW;

  @override
  int computeMinIntrinsicHeight(int width) => minH;

  @override
  int computeMaxIntrinsicHeight(int width) => maxH;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {}
}

/// [child] pinned as the named arguments say.
RenderObject pin(
  RenderObject child, {
  int? left,
  int? top,
  int? right,
  int? bottom,
  int? width,
  int? height,
}) {
  final at = StackParentData()
    ..left = left
    ..top = top
    ..right = right
    ..bottom = bottom
    ..width = width
    ..height = height;
  return child..parentData = at;
}

/// Where [o] is and how big: 'x,y wxh'.
String box(RenderObject o) =>
    '${o.parentData.dx},${o.parentData.dy} ${o.width}x${o.height}';

/// Every intrinsic size of [o] at [extent]: min and max width, min and max
/// height.
List<int> intrinsics(RenderObject o, int extent) => [
  o.getMinIntrinsicWidth(extent),
  o.getMaxIntrinsicWidth(extent),
  o.getMinIntrinsicHeight(extent),
  o.getMaxIntrinsicHeight(extent),
];

void main() {
  group('the children placed by the alignment', () {
    test('are laid out loosely, and the stack is as big as the biggest', () {
      final a = Label('abc');
      final b = Label('de');
      final stack = RenderStack(children: [a, b])
        ..layout(const BoxConstraints(1, 10, 2, 5), parentUsesSize: true);
      expect(a.got, const BoxConstraints(0, 10, 0, 5));
      expect([stack.width, stack.height], [3, 2]);
      expect([box(a), box(b)], ['0,0 3x1', '0,0 2x1']);
    });

    test('go where the alignment puts them', () {
      final v = View(6, 3);
      final a = Label('abcd');
      final b = Label('ef');
      final stack = RenderStack(
        alignment: Alignment.bottomRight,
        children: [a, b],
      );
      expect(v.show(stack), ['', '', '  abef']);
      stack.alignment = Alignment.center;
      expect(v.frame(), ['', ' aefd', '']);
      expect([box(a), box(b)], ['1,1 4x1', '2,1 2x1']);
      expect(stack.alignment, Alignment.center);
    });

    test('are as big as the stack may be with StackFit.expand, and get its '
        'constraints with passthrough', () {
      final a = Label('abc');
      final stack = RenderStack(fit: StackFit.expand, children: [a])
        ..layout(const BoxConstraints(1, 10, 2, 5), parentUsesSize: true);
      expect(a.got, const BoxConstraints.tight(10, 5));
      expect([stack.width, stack.height], [10, 5]);
      stack
        ..fit = StackFit.passthrough
        ..layout(const BoxConstraints(1, 10, 2, 5), parentUsesSize: true);
      expect(a.got, const BoxConstraints(1, 10, 2, 5));
      expect([stack.width, stack.height], [3, 2]);
      expect(stack.fit, StackFit.passthrough);
    });

    test('bigger than the stack may be are cut off at its bounds', () {
      final v = View(8, 3);
      final stack = RenderStack(
        alignment: Alignment.center,
        children: [Stubborn('abcdefg', 7, 3)],
      );
      // four columns and one row in the middle of the screen
      final root = RenderPadding(
        padding: const EdgeInsets.only(left: 2, top: 1, right: 2, bottom: 1),
        child: stack,
      );
      expect(v.show(root), ['', '  bcde', '']);
    });
  });

  group('without children placed by the alignment the stack', () {
    test('is as big as its constraints allow', () {
      final stack = RenderStack(children: [pin(Label('ab'), left: 1)])
        ..layout(const BoxConstraints(1, 10, 2, 5), parentUsesSize: true);
      expect([stack.width, stack.height], [10, 5]);
      final empty = RenderStack()
        ..layout(const BoxConstraints(1, 10, 2, 5), parentUsesSize: true);
      expect([empty.width, empty.height], [10, 5]);
    });

    test('is as small as they allow along an unbounded axis', () {
      final stack = RenderStack()
        ..layout(
          const BoxConstraints(1, BoxConstraints.unbounded, 2, 5),
          parentUsesSize: true,
        );
      expect([stack.width, stack.height], [1, 5]);
      stack.layout(
        const BoxConstraints(1, 4, 2, BoxConstraints.unbounded),
        parentUsesSize: true,
      );
      expect([stack.width, stack.height], [4, 2]);
    });
  });

  group('a positioned child', () {
    /// [child] in a 10 × 5 stack, laid out.
    RenderObject inStack(RenderObject child) {
      RenderStack(
        children: [Fill('.'), child],
      ).layout(const BoxConstraints.tight(10, 5), parentUsesSize: true);
      return child;
    }

    test('is pinned to the left and top edges', () {
      final a = inStack(pin(Label('abc'), left: 2, top: 1)) as Label;
      expect(box(a), '2,1 3x1');
      expect(a.got, const BoxConstraints(0, 8, 0, 4));
    });

    test('is pinned to the right and bottom edges', () {
      final a = inStack(pin(Label('abc'), right: 2, bottom: 1)) as Label;
      expect(box(a), '5,3 3x1');
      expect(a.got, const BoxConstraints(0, 8, 0, 4));
    });

    test('pinned to both edges is as long as the cells between them', () {
      final a = inStack(pin(Fill('x'), left: 1, top: 1, right: 3, bottom: 2));
      expect(box(a), '1,1 6x2');
      expect((a as Fill).got, const BoxConstraints.tight(6, 2));
      final b = inStack(pin(Fill('x'), left: 6, top: 1, right: 6, bottom: 2));
      expect(box(b), '6,1 0x2');
    });

    test('is as big as its size says, whatever the edge', () {
      final a = inStack(pin(Fill('x'), width: 4, height: 2)) as Fill;
      expect(a.got, const BoxConstraints.tight(4, 2));
      expect(box(a), '0,0 4x2');
      final b = inStack(
        pin(Fill('x'), right: 1, width: 4, bottom: 0, height: 1),
      );
      expect(box(b), '5,4 4x1');
      final c = inStack(pin(Fill('x'), left: 1, right: 1, width: 4));
      expect(box(c), '1,0 8x5');
    });

    test('with no edge set along an axis goes where the alignment puts '
        'it', () {
      final a = pin(Label('abcd'), top: 1);
      final b = pin(Label('ab'), left: 1);
      RenderStack(
        alignment: Alignment.bottomRight,
        children: [a, b],
      ).layout(const BoxConstraints.tight(10, 5), parentUsesSize: true);
      expect([box(a), box(b)], ['6,1 4x1', '1,4 2x1']);
      expect((a as Label).got, const BoxConstraints(0, 10, 0, 4));
    });

    test('is as long as it wants up to the far edge', () {
      final v = View(8, 2);
      final a = pin(Label('abcdefgh'), left: 5);
      final b = pin(Label('ijklmnop'), right: 3, top: 1);
      expect(v.show(RenderStack(children: [a, b])), ['     abc', 'ijklm']);
    });

    test('sticks out by a negative edge or its size and is cut off at the '
        "stack's bounds", () {
      final v = View(9, 4);
      final stack = RenderStack(
        children: [
          pin(Label('abcdef'), left: -2, top: -1),
          pin(Label('abcdef'), left: -2, top: 0),
          pin(Fill('#'), right: -2, top: 1, width: 4, height: 1),
          pin(Fill('x'), left: 1, bottom: -5, width: 1, height: 8),
        ],
      );
      // five columns and two rows in the middle of the screen
      final root = RenderPadding(
        padding: const EdgeInsets.only(left: 2, top: 1, right: 2, bottom: 1),
        child: stack,
      );
      expect(v.show(root), ['', '  cxef', '   x ##', '']);
    });
  });

  test('later children are painted over earlier ones', () {
    final v = View(6, 2);
    final stack = RenderStack(
      children: [
        Fill('.'),
        pin(Label('abcd'), left: 1),
        pin(Label('XY'), left: 2),
        pin(Fill('#'), top: 1, width: 2, height: 1),
      ],
    );
    expect(v.show(stack), ['.aXYd.', '##....']);
    // the last child moved to the front
    stack.move(stack.firstChild!, after: stack.lastChild);
    expect(v.frame(), ['......', '......']);
  });

  test('asks for what the biggest child placed by the alignment asks '
      'for', () {
    final stack = RenderStack(
      children: [
        Probe(minW: 3, maxW: 5, minH: 2, maxH: 6),
        Probe(minW: 4, maxW: 4, minH: 1, maxH: 7),
        pin(Probe(minW: 9, maxW: 9, minH: 9, maxH: 9), left: 0),
      ],
    );
    expect(intrinsics(stack, 10), [4, 5, 2, 7]);
    expect(intrinsics(RenderStack(), 10), [0, 0, 0, 0]);
    expect(intrinsics(RenderStack(children: [pin(Label('ab'), top: 0)]), 3), [
      0,
      0,
      0,
      0,
    ]);
  });

  group('a repaint boundary that repaints on its own', () {
    test('under another one leaves it on top', () {
      final v = View(6, 3);
      final under = Panel('.', v.opaque);
      final over = Panel('#', v.opaque);
      final stack = RenderStack(
        children: [
          under,
          pin(over, left: 2, top: 1, width: 3, height: 1),
        ],
      );
      expect(v.show(stack), ['......', '..###.', '......']);
      under.char = ':';
      expect(v.frame(), ['::::::', '::###:', '::::::']);
      expect([under.paints, over.paints], [2, 2]);
    });

    test('under another one that repaints in the same frame leaves it on '
        'top, whichever repaints first', () {
      final v = View(6, 3);
      final under = Panel('.', v.opaque);
      final over = Panel('#', v.opaque);
      final stack = RenderStack(
        children: [
          under,
          pin(over, left: 2, top: 1, width: 3, height: 1),
        ],
      );
      expect(v.show(stack), ['......', '..###.', '......']);
      over.char = '%';
      under.char = ':';
      expect(v.frame(), ['::::::', '::%%%:', '::::::']);
      under.char = '.';
      over.char = '#';
      expect(v.frame(), ['......', '..###.', '......']);
    });

    test('under children that are not boundaries leaves them on top', () {
      final v = View(6, 3);
      final under = Panel('.', v.opaque);
      final stack = RenderStack(
        children: [
          under,
          pin(Label('ab'), left: 1, top: 1),
          pin(Label('cd'), left: 2, top: 1),
        ],
      );
      expect(v.show(stack), ['......', '.acd..', '......']);
      under.char = ':';
      expect(v.frame(), ['::::::', ':acd::', '::::::']);
    });

    test('paints again only the children above it that overlap it', () {
      final v = View(8, 2);
      final under = Panel('.', v.opaque);
      final beside = pin(Label('ab'), left: 6);
      final over = pin(Label('cd'), left: 2);
      final stack = RenderStack(
        children: [
          pin(under, left: 0, top: 0, width: 5, height: 2),
          beside,
          over,
        ],
      );
      expect(v.show(stack), ['..cd. ab', '.....']);
      under.char = ':';
      expect(v.frame(), ['::cd: ab', ':::::']);
      expect([(beside as Label).paints, (over as Label).paints], [1, 2]);
    });

    test('under children of every stack around it leaves them on top', () {
      final v = View(8, 3);
      final under = Panel('.', v.opaque);
      final inner = RenderStack(
        children: [under, pin(Label('ab'), left: 3, top: 1)],
      );
      final outer = RenderStack(
        children: [
          pin(inner, left: 1, top: 0, width: 6, height: 3),
          pin(Label('cd'), left: 1, top: 1),
          pin(Label('ef'), left: 0, top: 2),
        ],
      );
      expect(v.show(outer), [' ......', ' cd.ab.', 'ef.....']);
      under.char = ':';
      expect(v.frame(), [' ::::::', ' cd:ab:', 'ef:::::']);
    });

    test('in a stack cut off by its parent paints within the parent', () {
      final v = View(8, 3);
      final under = Panel('.', v.opaque);
      final stack = RenderStack(
        children: [
          pin(under, left: 0, top: 0, width: 8, height: 3),
          pin(Stubborn('abcdefgh', 8, 1), left: 0, top: 0),
        ],
      );
      final root = RenderBox(
        pen: v.opaque,
        padX: 2,
        padY: 1,
        boundary: true,
        child: stack,
      );
      expect(v.show(root), ['', '  abcd', '']);
      under.char = ':';
      expect(v.frame(), ['', '  abcd', '']);
      expect(under.paints, 2);
    });

    test('a log that scrolls under a panel leaves the panel on top', () {
      final v = View(10, 4);
      final log = RenderLog(pen: v.opaque, itemPen: (_, _) => v.opaque);
      final panel = Panel('#', v.opaque);
      final stack = RenderStack(
        children: [
          log,
          pin(panel, left: 7, top: 1, width: 3, height: 2),
        ],
      );
      for (var i = 0; i < 4; i++) {
        log.add('line $i');
      }
      expect(v.show(stack), [
        ' line 0',
        ' line 1###',
        ' line 2###',
        ' line 3',
      ]);
      for (var i = 4; i < 6; i++) {
        log.add('line $i');
      }
      expect(v.frame(), [' line 2', ' line 3###', ' line 4###', ' line 5']);
      expect(panel.paints, 2);
    });

    test('under a log keeps every line of the log', () {
      final v = View(10, 3);
      final under = Panel('.', v.opaque);
      final log = RenderLog(pen: v.opaque, itemPen: (_, _) => v.opaque);
      final stack = RenderStack(
        children: [
          pin(under, left: 0, top: 0, width: 4, height: 3),
          // a level deeper than the panel: painted after it in a frame
          pin(
            RenderPadding(padding: EdgeInsets.zero, child: log),
            left: 2,
            top: 0,
            width: 8,
            height: 3,
          ),
        ],
      );
      for (var i = 0; i < 3; i++) {
        log.add('line $i');
      }
      expect(v.show(stack), ['.. line 0', '.. line 1', '.. line 2']);
      under.char = ':';
      log.add('line 3');
      expect(v.frame(), [':: line 1', ':: line 2', ':: line 3']);
    });
  });
}
