/// What the framework's tests build trees from: render objects with no
/// children, one child or a list of them, widgets over them, and a tree
/// under a [BuildOwner] pumped the way a frame loop does.
library;

import 'package:twk/twk.dart';

/// A render object without children, named by [label].
final class TestLeaf extends RenderObject {
  TestLeaf(this.label);

  String label;

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
  }

  @override
  void paint(PaintContext ctx) {}

  @override
  String toString() => label;
}

/// A render object with at most one child.
final class TestSingle extends RenderObject {
  RenderObject? _child;

  RenderObject? get child => _child;

  set child(RenderObject? c) {
    final old = _child;
    _child = c;
    if (old != null) {
      drop(old);
    }
    if (c != null) {
      adopt(c);
    }
  }

  @override
  void visitChildren(void Function(RenderObject child) visit) {
    if (_child != null) {
      visit(_child!);
    }
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    _child?.layout(c);
  }

  @override
  void paint(PaintContext ctx) {}
}

/// What a [TestMulti] keeps on each child besides its offset.
final class TestParentData extends ParentData {
  String? tag;
}

/// A render object with a list of children, on each of which it keeps a
/// [TestParentData]; [log] records each change the framework makes to the
/// list.
final class TestMulti extends RenderObject {
  final children = <RenderObject>[];
  final log = <String>[];

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! TestParentData) {
      child.parentData = TestParentData();
    }
  }

  void insert(RenderObject child, {RenderObject? after}) {
    log.add('insert $child after ${after ?? '-'}');
    children.insert(after == null ? 0 : children.indexOf(after) + 1, child);
    adopt(child);
  }

  void move(RenderObject child, {RenderObject? after}) {
    log.add('move $child after ${after ?? '-'}');
    children
      ..remove(child)
      ..insert(after == null ? 0 : children.indexOf(after) + 1, child);
    markNeedsLayout();
  }

  void remove(RenderObject child) {
    log.add('remove $child');
    children.remove(child);
    drop(child);
  }

  @override
  void visitChildren(void Function(RenderObject child) visit) {
    children.forEach(visit);
  }

  @override
  void performLayout(BoxConstraints c) {
    width = c.maxW;
    height = c.maxH;
    for (final child in children) {
      child.layout(c);
    }
  }

  @override
  void paint(PaintContext ctx) {}
}

/// A [TestLeaf] named [label]; [log], when given, records each update and
/// unmount of the render object.
final class Leaf extends LeafRenderObjectWidget {
  const Leaf(this.label, {super.key, this.log});

  final String label;
  final List<String>? log;

  @override
  TestLeaf createRenderObject(BuildContext context) => TestLeaf(label);

  @override
  void updateRenderObject(BuildContext context, TestLeaf renderObject) {
    log?.add('update $label');
    renderObject.label = label;
  }

  @override
  void didUnmountRenderObject(TestLeaf renderObject) {
    log?.add('unmount $renderObject');
  }
}

/// A leaf of another type than [Leaf]: it replaces a [Leaf] rather than
/// updating it.
final class OtherLeaf extends LeafRenderObjectWidget {
  const OtherLeaf(this.label, {super.key});

  final String label;

  @override
  TestLeaf createRenderObject(BuildContext context) => TestLeaf(label);
}

/// A [TestSingle] with [child]'s render object as its child.
final class Single extends SingleChildRenderObjectWidget {
  const Single({super.child});

  @override
  SingleChildRenderObjectElement createElement() => _SingleElement(this);

  @override
  TestSingle createRenderObject(BuildContext context) => TestSingle();
}

final class _SingleElement extends SingleChildRenderObjectElement {
  _SingleElement(Single super.widget);

  @override
  TestSingle get renderObject => super.renderObject as TestSingle;

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.child = child;

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) => throw StateError('one child does not move');

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.child = null;
}

/// A [TestMulti] with [children]'s render objects as its children.
final class Multi extends MultiChildRenderObjectWidget {
  const Multi(List<Widget> children) : super(children: children);

  @override
  MultiChildRenderObjectElement createElement() => _MultiElement(this);

  @override
  TestMulti createRenderObject(BuildContext context) => TestMulti();
}

final class _MultiElement extends MultiChildRenderObjectElement {
  _MultiElement(Multi super.widget);

  @override
  TestMulti get renderObject => super.renderObject as TestMulti;

  @override
  void insertRenderObjectChild(
    RenderObject child,
    IndexedSlot<Element?> slot,
  ) => renderObject.insert(child, after: slot.value?.renderObject);

  @override
  void moveRenderObjectChild(
    RenderObject child,
    IndexedSlot<Element?> oldSlot,
    IndexedSlot<Element?> newSlot,
  ) => renderObject.move(child, after: newSlot.value?.renderObject);

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) =>
      renderObject.remove(child);
}

/// A stateless widget that shows [child].
final class Wrapper extends StatelessWidget {
  const Wrapper(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A stateful widget whose state logs each call of the framework into
/// [log], prefixed with [name], and shows [child] or what [builder] returns.
/// [onDidChangeDependencies] is for depending on inherited widgets there.
final class Probe extends StatefulWidget {
  const Probe(
    this.name,
    this.log, {
    super.key,
    this.child = const Leaf('leaf'),
    this.builder,
    this.onDidChangeDependencies,
    this.tag = 0,
  });

  final String name;
  final List<String> log;
  final Widget child;
  final Widget Function(ProbeState state)? builder;

  /// Runs in [ProbeState.didChangeDependencies], after the log.
  final void Function(ProbeState state)? onDidChangeDependencies;

  /// Tells widgets that are otherwise the same apart in the log.
  final int tag;

  @override
  State<Probe> createState() => ProbeState();
}

final class ProbeState extends State<Probe> {
  /// For builders to show something else after a [setState].
  var count = 0;

  /// Calls [setState] with [fn], which code outside a state may not.
  void change(void Function() fn) => setState(fn);

  void _log(String what) => widget.log.add('${widget.name} $what');

  @override
  void initState() {
    super.initState();
    _log('initState');
  }

  @override
  void didUpdateWidget(Probe oldWidget) {
    super.didUpdateWidget(oldWidget);
    _log('didUpdateWidget ${oldWidget.tag} to ${widget.tag}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _log('didChangeDependencies');
    widget.onDidChangeDependencies?.call(this);
  }

  @override
  void deactivate() {
    _log('deactivate');
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _log('activate');
  }

  @override
  void dispose() {
    _log('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _log('build');
    return widget.builder?.call(this) ?? widget.child;
  }
}

/// A tree under one [BuildOwner], at the top of which [pump] puts widgets;
/// a [TestSingle] holds the render object of the widget pumped.
final class Tree {
  Tree({this.onBuildError});

  final Widget Function(Element element, Object error, StackTrace stack)?
  onBuildError;

  late final owner = BuildOwner(
    onBuildScheduled: () => scheduled++,
    onBuildError: onBuildError,
  );

  /// How many times the owner asked for a build scope.
  var scheduled = 0;

  RootElement? _root;

  RootElement get root => _root!;

  /// The render object at the top of the tree.
  TestSingle get host => root.renderObject! as TestSingle;

  /// Shows [widget] at the top of the tree: built now in a new tree, from
  /// the next build scope on in one already built.
  void show(Widget widget) {
    _root = RootWidget(child: Single(child: widget)).attach(owner, _root);
  }

  /// Shows [widget] at the top of the tree and runs a frame.
  void pump(Widget widget) {
    show(widget);
    frame();
  }

  /// Rebuilds what is dirty, then unmounts what was removed, as a frame
  /// does.
  void frame() {
    owner
      ..buildScope()
      ..finalizeTree();
  }

  /// Every element of the tree, parents before children.
  Iterable<Element> get elements sync* {
    final stack = <Element>[root];
    while (stack.isNotEmpty) {
      final e = stack.removeLast();
      yield e;
      final children = <Element>[];
      e.visitChildren(children.add);
      stack.addAll(children.reversed);
    }
  }

  /// The element of the only widget of type [W] in the tree.
  Element elementOf<W extends Widget>() =>
      elements.singleWhere((e) => e.widget is W);

  /// The states of the [Probe]s in the tree, parents before children.
  List<ProbeState> get probes => elements
      .whereType<StatefulElement>()
      .map((e) => e.state)
      .whereType<ProbeState>()
      .toList();

  /// The state of the only state of type [S] in the tree.
  S stateOf<S extends State<StatefulWidget>>() => elements
      .whereType<StatefulElement>()
      .map((e) => e.state)
      .whereType<S>()
      .single;
}
