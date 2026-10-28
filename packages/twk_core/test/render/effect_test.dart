// RenderEffect shows its child through a function over the cells of its
// bounds: a new frame of the effect from what it kept, painting neither
// the child nor what is under it; the child repainting underneath, over
// what was under it put back, and a repaint boundary in it shown through
// the effect as it repaints on its own; what its parent or a sibling under
// it paints anew kept as what is under it; two-column glyphs kept whole.
// The frames go through the terminal emulator, which must show what the
// screen holds.
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
  /// emulator; returns the rows of the screen, after checking that every
  /// two-column glyph on it is whole.
  List<String> frame() {
    owner
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    _expectWhole();
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

  /// What [root] paints on the whole screen.
  List<String> show(RenderObject root) {
    owner.root = root;
    return frame();
  }

  /// A first half followed by a second half in its style, and no second
  /// half alone.
  void _expectWhole() {
    final surface = screen.surface;
    final cells = surface.cells;
    final styles = surface.styles;
    for (var i = 0; i < cells.length; i++) {
      final x = i % width;
      if ((cells[i] & kWide) != 0) {
        expect(x + 1, lessThan(width), reason: 'a first half at $i');
        expect(cells[i + 1] & kCont, kCont, reason: 'the first half at $i');
        expect(styles[i + 1], styles[i], reason: 'the halves at $i');
      } else if ((cells[i] & kCont) != 0) {
        expect(x, greaterThan(0), reason: 'a second half at $i');
        expect(cells[i - 1] & kWide, kWide, reason: 'the second half at $i');
      }
    }
  }
}

/// One line of [text], as wide as it, painting its characters but blanks
/// with a pen of no colors: what is under a blank shows. Counts its paints.
final class Line extends RenderObject {
  Line(this._text);

  String _text;
  var paints = 0;

  String get text => _text;
  set text(String t) {
    final longer = stringWidth(t) != stringWidth(_text);
    _text = t;
    longer ? markNeedsLayout() : markNeedsPaint();
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(stringWidth(_text));
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    final pen = ctx.canvas.styles.pen(const Pen());
    var x = 0;
    for (final char in _text.split(' ')) {
      ctx.canvas.text(x, 0, char, pen);
      x += stringWidth(char) + 1;
    }
  }
}

/// A repaint boundary of one line of [text] on black, as wide as it; a new
/// [text] repaints it on its own. Counts its paints.
final class Board extends RenderObject {
  Board(this._text);

  String _text;
  var paints = 0;

  String get text => _text;
  set text(String t) {
    _text = t;
    markNeedsPaint();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_text.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) {
    paints++;
    final pen = ctx.canvas.styles.pen(
      const Pen(fg: Color.rgb(255, 255, 255), bg: Color.rgb(0, 0, 0)),
    );
    ctx.canvas
      ..fill(0, 0, width, height, pen)
      ..text(0, 0, _text, pen);
  }
}

/// Shows the cells in the columns [hidden] as what was under them, and
/// the child's letters elsewhere [shift] letters on (z to a). Counts the
/// passes and the cells it was asked for.
final class Probe extends RenderEffect {
  Probe(RenderObject child, {this.shift = 0, this.hidden = const {}}) {
    this.child = child;
  }

  int shift;
  Set<int> hidden;
  var passes = 0;
  var cells = 0;

  /// The next frame of the effect.
  void update({int? shift, Set<int>? hidden}) {
    this.shift = shift ?? this.shift;
    this.hidden = hidden ?? this.hidden;
    markNeedsPaint();
  }

  /// Whether the effect is held off: it has none while it is, whatever it
  /// would show.
  var paused = false;

  @override
  bool get hasEffect => !paused && (shift != 0 || hidden.isNotEmpty);

  @override
  void beginEffect(StyleTable styles) => passes++;

  @override
  void effectCell(
    int x,
    int y,
    int glyph,
    int style,
    int underGlyph,
    int underStyle,
  ) {
    cells++;
    if (hidden.contains(x)) {
      effectGlyph = underGlyph;
      effectStyle = underStyle;
      return;
    }
    final a = 'a'.codeUnitAt(0);
    final letter = glyph - a;
    effectGlyph = letter >= 0 && letter < 26
        ? a + (letter + shift) % 26
        : glyph;
    effectStyle = style;
  }
}

void main() {
  test('shows the child through its effect, over what was under it; a new '
      'frame of the effect is shown from what it kept, painting neither the '
      'child nor what is under it', () {
    final view = View(6, 1);
    final under = Line('uvwxyz');
    final child = Line('abcd');
    final effect = Probe(child, shift: 1);
    expect(view.show(RenderStack(children: [under, effect])), ['bcdeyz']);
    effect.update(hidden: {1, 2});
    expect(view.frame(), ['bvweyz']);
    effect.update(shift: 25, hidden: {});
    expect(view.frame(), ['zabcyz']);
    expect((child.paints, under.paints), (1, 1));
    expect(effect.passes, 3);
  });

  test('a mark in the child paints it again over what was under it, put '
      'back: the effect is shown on what it paints, not on what it showed', () {
    final view = View(4, 1);
    final child = Line('a');
    final effect = Probe(child, shift: 1);
    expect(
      view.show(RenderStack(children: [Line('wxyz'), effect])),
      ['bxyz'],
    );
    // four wide: the cells it leaves show what is under them
    child.text = 'c   ';
    expect(view.frame(), ['dyza']);
    child.text = 'e   ';
    expect(view.frame(), ['fyza']);
    expect(child.paints, 3);
  });

  test('a repaint boundary in the child repaints on its own, shown through '
      'the effect in its cells only', () {
    final view = View(6, 1);
    final line = Line('abc');
    final board = Board('xyz');
    final effect = Probe(
      RenderFlex(children: [line, board], mainAxisSize: MainAxisSize.min),
      shift: 1,
    );
    expect(view.show(effect), ['bcdyza']);
    final cells = effect.cells;
    board.text = 'mno';
    expect(view.frame(), ['bcdnop']);
    expect(effect.cells - cells, 3);
    expect((line.paints, board.paints), (1, 2));
  });

  test('a repaint boundary marked in the child as a new frame of the effect '
      'is shown repaints on its own too', () {
    final view = View(6, 1);
    final board = Board('xyz');
    final effect = Probe(
      RenderFlex(
        children: [Line('abc'), board],
        mainAxisSize: MainAxisSize.min,
      ),
      shift: 1,
    );
    expect(view.show(effect), ['bcdyza']);
    effect.update(shift: 2);
    board.text = 'mno';
    expect(view.frame(), ['cdeopq']);
  });

  test('without an effect the child shows as it paints; the effect is shown '
      'once it has one, and the child as it paints again once it has none', () {
    final view = View(4, 1);
    final child = Line('ab');
    final effect = Probe(child);
    expect(
      view.show(RenderStack(children: [Line('wxyz'), effect])),
      ['abyz'],
    );
    expect(effect.passes, 0);
    effect.update(hidden: {0});
    expect(view.frame(), ['wbyz']);
    effect.update(hidden: {1});
    expect(view.frame(), ['axyz']);
    effect.update(hidden: {});
    expect(view.frame(), ['abyz']);
    // painted to keep, then again once the effect was off
    expect(child.paints, 3);
    child.text = 'cd';
    expect(view.frame(), ['cdyz']);
  });

  test('what its parent paints anew under it shows where the effect shows '
      'what is under it', () {
    final view = View(4, 1);
    final under = Line('wxyz');
    final child = Line('ab');
    final effect = Probe(child, hidden: {0});
    expect(view.show(RenderStack(children: [under, effect])), ['wbyz']);
    under.text = 'klmn';
    expect(view.frame(), ['kbmn']);
    effect.update(hidden: {1});
    expect(view.frame(), ['almn']);
  });

  test('what a repaint boundary under it repaints on its own shows where the '
      'effect shows what is under it', () {
    final view = View(6, 1);
    final board = Board('uvwxyz');
    final effect = Probe(Line('abcd'), hidden: {1});
    expect(view.show(RenderStack(children: [board, effect])), ['avcdyz']);
    board.text = 'mnopqr';
    expect(view.frame(), ['ancdqr']);
    effect.update(hidden: {2});
    expect(view.frame(), ['abodqr']);
  });

  test('the effect is asked for the cells of its own bounds, the child '
      'growing with them', () {
    final view = View(8, 1);
    final child = Line('abc');
    final effect = Probe(child, hidden: {0});
    expect(
      view.show(
        RenderFlex(
          children: [Line('>>'), effect, Line('<')],
          mainAxisSize: MainAxisSize.min,
        ),
      ),
      ['>> bc<'],
    );
    child.text = 'abcd';
    expect(view.frame(), ['>> bcd<']);
    effect.update(hidden: {3});
    expect(view.frame(), ['>>abc <']);
  });

  test('keeps two-column glyphs whole, taking both halves from the child or '
      'what is under it, or blanking a half left alone', () {
    final view = View(8, 1);
    final effect = Probe(Line('a中文bc'));
    expect(
      view.show(RenderStack(children: [Line('中文中文'), effect])),
      ['a中文bc'],
    );
    for (final hidden in [
      {0},
      {1},
      {2},
      {0, 2},
      {1, 3},
      {3, 4},
      {5},
      {1, 2, 3, 4},
    ]) {
      effect.update(hidden: hidden);
      view.frame();
    }
    // the first half of what is under it takes its second half along; the
    // child's second half left alone is blanked
    effect.update(hidden: {0});
    expect(view.frame(), ['中 文bc']);
    // a second half alone of what is under it, then of the child's
    effect.update(hidden: {1});
    expect(view.frame(), ['a  文bc']);
  });

  test('without an effect a repaint boundary in the child repaints on its '
      'own under a sibling over it as it paints, the effect not asked', () {
    final view = View(6, 1);
    final board = Board('xyz');
    final effect = Probe(
      RenderFlex(
        children: [Line('abc'), board],
        mainAxisSize: MainAxisSize.min,
      ),
      shift: 1,
    )..paused = true;
    expect(
      view.show(RenderStack(children: [effect, Line('     q')])),
      ['abcxyq'],
    );
    board.text = 'mno';
    expect(view.frame(), ['abcmnq']);
    expect((effect.passes, effect.cells), (0, 0));
    expect(board.paints, 2);
  });

  test('a two-column glyph the effect makes up, whose second half neither '
      'the child nor what is under it has, is blanked', () {
    // the cell after it holds the next glyph
    expect(View(4, 1).show(Widen(Line('awb'))), ['a b']);
    // the effect ends after it, at the edge of the screen or not
    expect(View(2, 1).show(Widen(Line('aw'))), ['a']);
    expect(View(4, 1).show(Widen(Line('aw'))), ['a']);
  });

  test('is as big as its child, and asks for what its child asks for; '
      'without a child, as small as the constraints allow', () {
    final effect = Widen(RenderParagraph([('ab cd', const Pen())]))
      ..layout(const BoxConstraints(0, 10, 0, 5), parentUsesSize: true);
    expect((effect.width, effect.height), (5, 1));
    expect(
      [
        effect.getMinIntrinsicWidth(5),
        effect.getMaxIntrinsicWidth(5),
        effect.getMinIntrinsicHeight(2),
        effect.getMaxIntrinsicHeight(2),
      ],
      [2, 5, 2, 2],
    );
    final empty = Widen(null)
      ..layout(const BoxConstraints(1, 10, 2, 5), parentUsesSize: true);
    expect((empty.width, empty.height), (1, 2));
    expect(
      [
        empty.getMinIntrinsicWidth(5),
        empty.getMaxIntrinsicWidth(5),
        empty.getMinIntrinsicHeight(5),
        empty.getMaxIntrinsicHeight(5),
      ],
      [0, 0, 0, 0],
    );
  });

  test('moved to another screen, it shows its child through the effect '
      'there', () {
    final effect = Probe(Line('abc'), shift: 1);
    final first = View(4, 1);
    expect(first.show(effect), ['bcd']);
    first.owner.root = Line('x');
    expect(effect.owner, isNull);
    expect(View(4, 1).show(effect), ['bcd']);
  });

  test('describes whether it has an effect', () {
    final effect = Probe(Line('abc'));
    expect('${effect.describe()}', 'Probe');
    effect.update(shift: 1);
    expect('${effect.describe()}', 'Probe ‹effect: true›');
  });
}

/// Shows its child's `w` as `漢`, a two-column glyph, and the rest as the
/// child paints it.
final class Widen extends RenderEffect {
  Widen(RenderObject? child) {
    this.child = child;
  }

  @override
  bool get hasEffect => true;

  @override
  void effectCell(
    int x,
    int y,
    int glyph,
    int style,
    int underGlyph,
    int underStyle,
  ) {
    effectGlyph = glyph == 0x77 ? 0x6F22 | kWide : glyph;
    effectStyle = style;
  }
}
