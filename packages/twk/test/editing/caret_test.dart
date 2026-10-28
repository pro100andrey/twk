// The terminal's cursor at the caret of an app's own render object
// (showCaret, hideCaret): in the object's shape; kept by the one the focus
// moves to, from a TextField or back, within a frame, whichever of the two
// paints last; hidden while neither has the focus, and once the object
// leaves the tree.
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

/// A cell with the terminal's cursor on it, in [shape], while [node] has
/// the focus.
final class Cell extends StatelessWidget {
  const Cell(this.node, {this.shape = CursorShape.block, super.key});

  final FocusNode node;
  final CursorShape shape;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: node,
    child: ListenableBuilder(
      listenable: node,
      builder: (context, _) => _Cell(focused: node.hasFocus, shape: shape),
    ),
  );
}

final class _Cell extends LeafRenderObjectWidget {
  const _Cell({required this.focused, required this.shape});

  final bool focused;
  final CursorShape shape;

  @override
  _RenderCell createRenderObject(BuildContext context) =>
      _RenderCell(shape)..focused = focused;

  @override
  void updateRenderObject(BuildContext context, _RenderCell renderObject) =>
      renderObject.focused = focused;
}

/// A repaint boundary of a cell: it paints on its own.
final class _RenderCell extends RenderObject {
  _RenderCell(this.shape);

  final CursorShape shape;

  var _focused = false;

  bool get focused => _focused;
  set focused(bool f) {
    if (f != _focused) {
      _focused = f;
      markNeedsPaint();
    }
  }

  PaintContext? _painted;

  @override
  bool get isRepaintBoundary => true;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(1);
    height = c.constrainH(1);
  }

  @override
  void detach() {
    final ctx = _painted;
    if (ctx != null) {
      hideCaret(ctx, this);
    }
    super.detach();
  }

  @override
  void paint(PaintContext ctx) {
    _painted = ctx;
    if (_focused) {
      showCaret(ctx, this, 0, 0, shape: shape);
    } else {
      hideCaret(ctx, this);
    }
  }
}

/// [child] three render objects deeper: a frame paints it after the
/// repaint boundaries above that depth.
Widget deeper(Widget child) => Padding(
  padding: EdgeInsets.zero,
  child: Padding(
    padding: EdgeInsets.zero,
    child: Padding(padding: EdgeInsets.zero, child: child),
  ),
);

/// The shape the terminal shows the cursor in.
int shapeOf(TwkTester t) => t.vt.cursorShape;

void main() {
  for (final fieldLast in [true, false]) {
    final last = fieldLast ? 'the field' : 'the cell';
    testTwk('the focus moving from a field to a cell and back within a '
        'frame leaves the cursor at the focused one, in its shape, $last '
        'painting last', (t) async {
      final fieldNode = FocusNode();
      final cellNode = FocusNode();
      addTearDown(fieldNode.dispose);
      addTearDown(cellNode.dispose);
      final c = TextEditingController(text: 'abc');
      addTearDown(c.dispose);
      final field = SizedBox(
        width: 10,
        child: TextField(controller: c, focusNode: fieldNode),
      );
      final cell = Cell(cellNode);
      // later in the column and deeper: painted after the other
      await t.pumpWidget(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: fieldLast ? [cell, deeper(field)] : [field, deeper(cell)],
        ),
        size: (12, 3),
      );
      final fieldRow = fieldLast ? 1 : 0;
      final cellRow = 1 - fieldRow;
      expect(t.cursorVisible, isFalse);
      fieldNode.requestFocus();
      await t.pump();
      expect(t, cursorAt(3, fieldRow));
      expect(shapeOf(t), CursorShape.bar.code);

      var frames = t.frames.length;
      cellNode.requestFocus();
      await t.pump();
      expect(t.frames, hasLength(frames + 1));
      expect(t, cursorAt(0, cellRow));
      expect(shapeOf(t), CursorShape.block.code);

      frames = t.frames.length;
      fieldNode.requestFocus();
      await t.pump();
      expect(t.frames, hasLength(frames + 1));
      expect(t, cursorAt(3, fieldRow));
      expect(shapeOf(t), CursorShape.bar.code);

      fieldNode.unfocus();
      await t.pump();
      expect(t.cursorVisible, isFalse);
    });
  }

  testTwk('the cursor goes with the object that showed it', (t) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await t.pumpWidget(
      Column(
        children: [
          const Text('top'),
          Cell(node, shape: CursorShape.underline),
        ],
      ),
      size: (5, 2),
    );
    node.requestFocus();
    await t.pump();
    expect(t, cursorAt(2, 1));
    expect(shapeOf(t), CursorShape.underline.code);
    await t.pumpWidget(const Text('top'), size: (5, 2));
    expect(t.cursorVisible, isFalse);
  });
}
