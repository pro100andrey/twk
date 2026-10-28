part of '../sample_app.dart';

extension on _SampleAppState {
  List<Widget> _framework() => [
    SizedBox(
      height: 1,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            const Expanded(
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Text('half'),
              ),
            ),
            IntrinsicWidth(
              stepWidth: 2,
              child: Text('${constraints.maxW} wide'),
            ),
            const IntrinsicHeight(child: Text('content')),
            StatefulBuilder(
              builder: (context, setState) => Button(
                'stateful',
                onPressed: () => setState(() {}),
              ),
            ),
            const _Plugged(),
          ],
        ),
      ),
    ),
    SizedBox(
      height: 3,
      child: NotificationListener<Ping>(
        onNotification: (ping) => true,
        child: Scope(
          value: 2,
          child: Passing(
            child: Strip(
              children: [
                const Share(weight: 2, child: Glyphs('glyphs')),
                Share(
                  child: Frame(child: Glyphs('framed ${describeValue(2)}')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ];
}

/// A slot that a plugin fills, and one it leaves empty.
final class _Plugged extends StatefulWidget {
  const _Plugged();

  @override
  State<_Plugged> createState() => _PluggedState();
}

final class _PluggedState extends State<_Plugged> {
  final _registry = SlotRegistry()
    ..register(
      SlotEntry(
        slot: 'status',
        id: 'plugin',
        order: 1,
        builder: (context) => const Text('plugged'),
      ),
    );

  @override
  void dispose() {
    _registry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlotScope(
    registry: _registry,
    child: Row(
      mainAxisSize: .min,
      gap: 1,
      children: [
        for (final name in ['status', 'empty'])
          Slot(
            name,
            layout: (context, children) =>
                Row(mainAxisSize: .min, children: children),
            placeholder: Text('no $name'),
          ),
      ],
    ),
  );
}

/// The element tree of [app] mounted by [owner], outside any app.
RootElement mount(Widget app, BuildOwner owner) =>
    RootWidget(child: app).attach(owner);

/// What [element] and those below it say of themselves.
DiagnosticsNode describeTree(Element element) => element.describe();

/// Whether [widget] puts a render object of its own in the tree.
bool rendersItself(Widget widget) => widget is RenderObjectWidget;

/// The render objects at [x], [y] of [root], the deepest first.
List<RenderObject> hitsAt(RenderObject root, int x, int y) {
  final result = HitTestResult();
  root.hitTest(result, x, y);
  return [for (var i = 0; i < result.length; i++) result[i]];
}

final class Ping extends Notification {}

/// An [InheritedWidget] of the app's own.
final class Scope extends InheritedWidget {
  const Scope({required this.value, required super.child, super.key});

  final int value;

  @override
  bool updateShouldNotify(Scope oldWidget) => value != oldWidget.value;
}

/// A [ProxyWidget] of the app's own, which tells nothing to anyone.
final class Passing extends ProxyWidget {
  const Passing({required super.child, super.key});

  @override
  ProxyElement createElement() => _PassingElement(this);
}

final class _PassingElement extends ProxyElement {
  _PassingElement(super.widget);

  @override
  void notifyClients(Passing oldWidget) {}
}

/// One line of [text] in bold, as wide as it is.
final class Glyphs extends LeafRenderObjectWidget {
  const Glyphs(this.text, {super.key});

  final String text;

  @override
  RenderGlyphs createRenderObject(BuildContext context) => RenderGlyphs(text);

  @override
  void updateRenderObject(BuildContext context, RenderGlyphs renderObject) =>
      renderObject.text = text;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..addMessage('text', describeText(text))
      ..addMessage('pen', describePen(RenderGlyphs.pen))
      ..addMessage('color', describeColor(Color.cyan))
      ..addMessage('alignment', describeAlignment(Alignment.center))
      ..addMessage('insets', describeInsets(EdgeInsets.zero))
      ..addMessage('constraints', describeConstraints(_loose))
      ..properties.add(const DiagnosticsProperty('own', 'yes'));
    if (text.isEmpty) {
      properties.flag(DiagnosticsFlag.overflow);
    }
  }
}

const _loose = BoxConstraints(0, 10, 0, 1);

/// What [Glyphs] lays out and paints: its text shaped once.
final class RenderGlyphs extends RenderObject {
  RenderGlyphs(this._text);

  static const pen = Pen(fg: Color.cyan, attrs: Attr.bold);

  String _text;
  GlyphRun? _run;

  String get text => _text;

  /// Hit anywhere in its bounds, and what it covers too.
  @override
  HitTestBehavior get hitTestBehavior => HitTestBehavior.translucent;

  set text(String value) {
    if (value != _text) {
      _text = value;
      _run = null;
      markNeedsLayout();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    final segmenter = owner?.segmenter ?? TextSegmenter(mode: TextMode.legacy);
    final scan = ClusterScan();
    var columns = 0;
    for (var i = 0; i < _text.length; i = scan.end) {
      segmenter.scan(_text, i, scan);
      columns += scan.width;
    }
    assert(columns == stringWidth(_text, mode: segmenter.mode), _text);
    width = c.constrainW(columns);
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) => _paintOn(ctx.canvas);

  void _paintOn(Canvas canvas) =>
      canvas.run(0, 0, _run ??= canvas.shape(_text), _penIn(canvas.styles));

  int _penIn(StyleTable styles) => styles.pen(pen);
}

/// What a [Strip] keeps on each child.
final class ShareData extends ParentData with ContainerParentDataMixin {
  var weight = 1;
}

/// Gives its child in a [Strip] a [weight].
final class Share extends ParentDataWidget<ShareData> {
  const Share({required super.child, this.weight = 1, super.key});

  final int weight;

  @override
  Type get debugTypicalAncestorWidgetClass => Strip;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData as ShareData;
    if (data.weight != weight) {
      data.weight = weight;
      renderObject.parent?.markNeedsLayout();
    }
  }
}

/// Its children side by side, each as wide as its [Share]'s weight says.
final class Strip extends MultiChildRenderObjectWidget {
  const Strip({super.children, super.key});

  @override
  MultiChildRenderObjectElement createElement() => ChildListElement(this);

  @override
  RenderStrip createRenderObject(BuildContext context) => RenderStrip();
}

/// What [Strip] lays out and paints.
final class RenderStrip extends RenderObject
    with ContainerRenderObjectMixin<ShareData> {
  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! ShareData) {
      child.parentData = ShareData();
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    var weights = 0;
    for (var o = firstChild; o != null; o = childAfter(o)) {
      weights += (o.parentData as ShareData).weight;
    }
    var x = 0;
    for (var o = firstChild; o != null; o = childAfter(o)) {
      final w = c.maxW * (o.parentData as ShareData).weight ~/ weights;
      o
        ..layout(BoxConstraints(0, w, 0, c.maxH))
        ..parentData.dx = x;
      x += w;
    }
    width = c.maxW;
    height = c.constrainH(1);
  }

  @override
  void paint(PaintContext ctx) => visitChildren((o) => paintChild(ctx, o));
}

/// [child] with a cell of room on its left.
final class Frame extends SingleChildRenderObjectWidget {
  const Frame({super.child, super.key});

  @override
  SingleChildRenderObjectElement createElement() => OneChildElement(this);

  @override
  RenderFrame createRenderObject(BuildContext context) => RenderFrame();
}

/// What [Frame] lays out and paints.
final class RenderFrame extends RenderObject with RenderObjectWithChildMixin {
  @override
  void performLayout(BoxConstraints c) {
    var w = 1;
    var h = 0;
    if (child case final child?) {
      child
        ..layout(BoxConstraints(0, c.maxW - 1, 0, c.maxH), parentUsesSize: true)
        ..parentData.dx = 1;
      w += child.width;
      h = child.height;
    }
    width = c.constrainW(w);
    height = c.constrainH(h);
  }

  @override
  void paint(PaintContext ctx) {
    if (child case final child?) {
      paintChild(ctx, child);
    }
  }
}
