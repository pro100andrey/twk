// A repaint boundary that repaints on its own has what is over it painted
// again over its cells: a wide glyph of what is over it that one of its
// edges cuts through shows as it would were the whole tree painted, whole,
// on the screen and on the terminal.
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
  /// emulator; returns the rows of the screen, a wide glyph's second
  /// column left out.
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
            if (screen.surface.cells[y * width + x] & kCont == 0)
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

  /// Expects the cells and the styles of the screen to be those a paint
  /// of the whole tree leaves: paints it whole and compares.
  void expectAsWhole() {
    final s = screen.surface;
    final cells = List.of(s.cells);
    final styles = List.of(s.styles);
    owner.root.markNeedsPaint();
    frame();
    expect(cells, s.cells, reason: 'the cells a whole paint leaves');
    expect(styles, s.styles, reason: 'the styles a whole paint leaves');
  }

  /// A pen with an opaque background, as a repaint boundary needs.
  late final int opaque = screen.styles.pen(
    const Pen(bg: Color.rgb(0, 0, 0)),
  );
}

/// [text] on one row in [pen] (the default pen unless given), [w]
/// columns wide whatever the constraints say.
final class Text extends RenderObject {
  Text(this.text, this.w, {this.pen = const Pen()});

  final String text;
  final int w;
  final Pen pen;

  @override
  void performLayout(BoxConstraints c) {
    width = w;
    height = 1;
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.text(0, 0, text, ctx.canvas.styles.pen(pen));
}

/// A repaint boundary that fills all the room it gets with [char] in an
/// opaque [pen]; a new [char] repaints it on its own.
final class Panel extends RenderObject {
  Panel(this._char, this.pen);

  String _char;
  final int pen;

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
  void paint(PaintContext ctx) =>
      ctx.canvas.fill(0, 0, width, height, pen, _char.codeUnitAt(0));
}

/// [child] pinned as the named arguments say.
RenderObject pin(
  RenderObject child, {
  int? left,
  int? top,
  int? width,
  int? height,
}) {
  final at = StackParentData()
    ..left = left
    ..top = top
    ..width = width
    ..height = height;
  return child..parentData = at;
}

void main() {
  group('a boundary repainted under a wide glyph', () {
    test('its right edge cuts through keeps the glyph whole', () {
      final v = View(8, 1);
      final panel = Panel('.', v.opaque);
      final stack = RenderStack(
        children: [
          pin(panel, left: 0, top: 0, width: 4, height: 1),
          // 你 at columns 3 and 4: the panel ends after column 3
          pin(Text('ab你cd', 6), left: 1, top: 0),
        ],
      );
      expect(v.show(stack), ['.ab你cd']);
      panel.char = ':';
      expect(v.frame(), [':ab你cd']);
      v.expectAsWhole();
    });

    test('its left edge cuts through keeps the glyph whole', () {
      final v = View(8, 1);
      final panel = Panel('.', v.opaque);
      final stack = RenderStack(
        children: [
          pin(panel, left: 4, top: 0, width: 4, height: 1),
          // 你 at columns 3 and 4: the panel starts at column 4
          pin(Text('ab你cd', 6), left: 1, top: 0),
        ],
      );
      expect(v.show(stack), [' ab你cd.']);
      panel.char = ':';
      expect(v.frame(), [' ab你cd:']);
      v.expectAsWhole();
    });

    test('both of its edges cut through keeps both glyphs whole', () {
      final v = View(8, 1);
      final panel = Panel('.', v.opaque);
      final stack = RenderStack(
        children: [
          pin(panel, left: 2, top: 0, width: 4, height: 1),
          // 你 at columns 1 and 2, 好 at 5 and 6: the panel is 2 to 5
          pin(Text('你ab好', 6), left: 1, top: 0),
        ],
      );
      expect(v.show(stack), [' 你ab好']);
      panel.char = ':';
      expect(v.frame(), [' 你ab好']);
      v.expectAsWhole();
    });

    test('in a translucent pen leaves the style a whole paint does', () {
      final v = View(8, 2);
      final panel = Panel('.', v.opaque);
      final stack = RenderStack(
        children: [
          pin(Text('xxxxxxxx', 8), left: 0, top: 0),
          pin(panel, left: 4, top: 0, width: 4, height: 2),
          pin(
            Text(
              'ab你cd',
              6,
              pen: const Pen(bg: Color.rgb(200, 40, 40), bgAlpha: 128),
            ),
            left: 1,
            top: 0,
          ),
        ],
      );
      expect(v.show(stack), ['xab你cd.', '    ....']);
      panel.char = ':';
      expect(v.frame(), ['xab你cd:', '    ::::']);
      v.expectAsWhole();
    });

    test('in a stack inside a boundary keeps the glyph whole', () {
      final v = View(10, 3);
      final panel = Panel('.', v.opaque);
      final root = RenderBox(
        pen: v.opaque,
        padX: 1,
        padY: 1,
        boundary: true,
        child: RenderStack(
          children: [
            pin(panel, left: 0, top: 0, width: 4, height: 1),
            pin(Text('ab你cd', 6), left: 1, top: 0),
          ],
        ),
      );
      expect(v.show(root), ['', ' .ab你cd', '']);
      panel.char = ':';
      expect(v.frame(), ['', ' :ab你cd', '']);
      v.expectAsWhole();
    });
  });

  group('a boundary repainted over half of a wide glyph', () {
    test('leaves it blanked whole', () {
      final v = View(8, 1);
      final panel = Panel('.', v.opaque);
      final stack = RenderStack(
        children: [
          // 你 at columns 3 and 4: the panel starts at column 4
          pin(Text('ab你cd', 6), left: 1, top: 0),
          pin(panel, left: 4, top: 0, width: 4, height: 1),
        ],
      );
      expect(v.show(stack), [' ab ....']);
      panel.char = ':';
      expect(v.frame(), [' ab ::::']);
      v.expectAsWhole();
    });

    test('under what covers it leaves it blanked whole', () {
      final v = View(8, 1);
      final panel = Panel('.', v.opaque);
      final stack = RenderStack(
        children: [
          // 你 at columns 3 and 4: the panel starts at column 4
          pin(Text('ab你cd', 6), left: 1, top: 0),
          pin(panel, left: 4, top: 0, width: 4, height: 1),
          pin(Text('ef', 2), left: 6, top: 0),
        ],
      );
      expect(v.show(stack), [' ab ..ef']);
      panel.char = ':';
      expect(v.frame(), [' ab ::ef']);
      v.expectAsWhole();
    });
  });
}
