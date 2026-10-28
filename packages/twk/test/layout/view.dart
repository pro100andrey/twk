/// What the layout tests build trees from: a screen that shows a widget
/// tree frame by frame, leaves that show a line of text or fill their room,
/// and a widget that switches what it shows.
library;

import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show PipelineOwner, Screen;

/// A widget tree on a screen, built, laid out and painted as a frame does.
final class View {
  View(this.width, this.height) : screen = Screen(width, height);

  final int width;
  final int height;
  final Screen screen;
  final owner = BuildOwner();
  late final pipeline = PipelineOwner(
    () {},
    segmenter: screen.canvas.segmenter,
  );
  RootElement? _root;
  RenderObject? _top;

  /// Shows [widget] and runs a frame.
  void pump(Widget widget) {
    _root = RootWidget(child: widget).attach(owner, _root);
    frame();
  }

  /// Rebuilds what is dirty, lays out and paints what changed, then
  /// unmounts what was removed.
  void frame() {
    owner.buildScope();
    final top = _root!.renderObject!;
    if (!identical(top, _top)) {
      pipeline.root = top;
      _top = top;
    }
    pipeline
      ..flushLayout(width, height)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    owner.finalizeTree();
    screen.render();
  }

  List<String> rows() => [
    for (var y = 0; y < height; y++)
      [
        for (var x = 0; x < width; x++)
          screen.glyphs.stringOf(screen.surface.cells[y * width + x]),
      ].join().trimRight(),
  ];

  /// The element at the top of the tree.
  RootElement get root => _root!;

  /// The render object at the top of the tree.
  RenderObject get top => _top!;
}

/// The children of [o], in order.
List<RenderObject> childrenOf(RenderObject o) {
  final out = <RenderObject>[];
  o.visitChildren(out.add);
  return out;
}

/// One line of [text] (one column per character), as wide as the text.
final class Label extends LeafRenderObjectWidget {
  const Label(this.text, {super.key});

  final String text;

  @override
  RenderLabel createRenderObject(BuildContext context) => RenderLabel(text);

  @override
  void updateRenderObject(BuildContext context, RenderLabel renderObject) {
    if (text != renderObject._text) {
      renderObject
        .._text = text
        ..markNeedsLayout();
    }
  }
}

/// What a [Label] lays out and paints.
final class RenderLabel extends RenderObject {
  RenderLabel(this._text);

  String _text;

  @override
  void performLayout(BoxConstraints c) {
    width = c.constrainW(_text.length);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) =>
      ctx.canvas.text(0, 0, _text, ctx.canvas.styles.pen(const Pen()));
}

/// Fills all the room it gets with [char].
final class Fill extends LeafRenderObjectWidget {
  const Fill(this.char);

  final String char;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFill(char);
}

final class _RenderFill extends RenderObject {
  _RenderFill(this.char);

  final String char;

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

/// Shows what [first] returns, and what [second] returns once [ToggleState.
/// toggle] was called.
final class Toggle extends StatefulWidget {
  const Toggle(this.first, this.second);

  final Widget Function() first;
  final Widget Function() second;

  @override
  State<Toggle> createState() => ToggleState();
}

final class ToggleState extends State<Toggle> {
  var _second = false;

  void toggle() => setState(() => _second = !_second);

  @override
  Widget build(BuildContext context) =>
      _second ? widget.second() : widget.first();
}

/// A stateless widget that shows [child].
final class Wrapper extends StatelessWidget {
  const Wrapper(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The state of the only [Toggle] under [root].
ToggleState toggleIn(Element root) {
  ToggleState? found;
  void visit(Element e) {
    if (e is StatefulElement && e.state is ToggleState) {
      found = e.state as ToggleState;
    }
    e.visitChildren(visit);
  }

  visit(root);
  return found!;
}
