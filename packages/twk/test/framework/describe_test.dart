import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_core/twk_core.dart' show PipelineOwner, RenderBox, Screen;

import 'harness.dart';

void main() {
  test('an element is named by its widget type and key', () {
    final tree = Tree()
      ..pump(const Multi([Leaf('a', key: ValueKey('k')), Wrapper(Leaf('b'))]));
    final [keyed, wrapped] = tree.elementOf<Multi>().describe().children;
    expect('$keyed', "Leaf-[<'k'>]");
    expect('$wrapped', 'Wrapper');
    expect('${tree.elementOf<Wrapper>()}', 'Wrapper');
    expect(
      '${tree.elements.singleWhere((e) => e.widget.key != null)}',
      "Leaf-[<'k'>]",
    );
    final wrapper = tree.elementOf<Wrapper>();
    tree.pump(const Leaf('c'));
    expect('$wrapper', 'StatelessElement, unmounted');
  });

  test("an element shows its widget's properties, then its state's, and "
      "a render object element its render object's and their flags", () {
    final tree = Tree()
      ..pump(
        const Multi([
          _Named('a', key: ValueKey('k')),
          _Counter(),
          _Boundary(),
        ]),
      );
    expect(tree.elementOf<Multi>().describe().toStringDeep(), '''
Multi                 ⟳
├─ _Named-[<'k'>] ‹label: "a"›
│  └─ Leaf            ⟳
├─ _Counter ‹label: "count", count: 0›
│  └─ Leaf            ⟳
└─ _Boundary ‹pen: 0› ◆ ⟳

◆ repaint boundary, ⟳ needs layout''');
  });

  test('an element to be rebuilt needs a build until it is', () {
    final tree = Tree()..pump(const _Counter());
    final element = tree.elementOf<_Counter>();
    expect(element.describe().flags, isEmpty);
    tree.stateOf<_CounterState>().increment();
    expect(element.describe().flags, [DiagnosticsFlag.needsBuild]);
    expect('${element.describe()}', '_Counter ‹label: "count", count: 1›');
    tree.frame();
    expect(element.describe().flags, isEmpty);
  });

  test('an element whose build threw shows an error until it builds', () {
    final log = <String>[];
    final tree = Tree(onBuildError: (element, error, stack) => const Leaf('!'))
      ..pump(
        Probe(
          'a',
          log,
          builder: (s) =>
              s.count == 1 ? throw StateError('boom') : const Leaf('a'),
        ),
      );
    final element = tree.elementOf<Probe>();
    expect(element.describe().flags, isEmpty);
    final state = tree.probes.single;
    state.change(() => state.count++);
    tree.frame();
    expect(element.describe().toStringDeep(), '''
Probe   ✗
└─ Leaf ⟳

⟳ needs layout, ✗ error''');
    state.change(() => state.count++);
    tree.frame();
    expect(element.describe().flags, isEmpty);
  });

  test('a render object element to be repainted says so until the next '
      'paint', () {
    final screen = Screen(4, 1);
    // the boundary's pen, 0
    screen.styles.pen(const Pen(fg: Color.white, bg: Color.black));
    final root = const RootWidget(child: _Boundary()).attach(BuildOwner());
    final pipeline = PipelineOwner(() {}, segmenter: screen.canvas.segmenter)
      ..root = root.renderObject!;
    void frame() => pipeline
      ..flushLayout(4, 1)
      ..flushPaint(
        PaintContext(screen.canvas, screen.surface, screen.presenter),
      );
    frame();
    late final Element boundary;
    root.visitChildren((child) => boundary = child);
    expect(boundary.describe().flags, [DiagnosticsFlag.repaintBoundary]);
    boundary.renderObject!.markNeedsPaint();
    expect(boundary.describe().flags, [
      DiagnosticsFlag.repaintBoundary,
      DiagnosticsFlag.needsPaint,
    ]);
    frame();
    expect(boundary.describe().flags, [DiagnosticsFlag.repaintBoundary]);
  });

  test('frames never describe a widget or a state', () {
    final described = <String>[];
    final tree = Tree();
    for (var i = 0; i < 3; i++) {
      tree.pump(
        Multi([
          _Named('$i', described: described),
          _Counter(described: described),
        ]),
      );
    }
    tree.stateOf<_CounterState>().increment();
    tree.frame();
    expect(described, isEmpty);
    tree.root.describe();
    expect(described, ['2', 'count']);
  });
}

/// Shows a leaf; describes itself by [label], recording it in [described].
final class _Named extends StatelessWidget {
  const _Named(this.label, {super.key, this.described});

  final String label;
  final List<String>? described;

  @override
  Widget build(BuildContext context) => const Leaf('x');

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    described?.add(label);
    properties.add('label', label);
  }
}

/// Shows a leaf; its state counts, and records `count` in [described]
/// when it describes itself.
final class _Counter extends StatefulWidget {
  const _Counter({this.described});

  final List<String>? described;

  @override
  State<_Counter> createState() => _CounterState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add('label', 'count');
  }
}

final class _CounterState extends State<_Counter> {
  var _count = 0;

  void increment() => setState(() => _count++);

  @override
  Widget build(BuildContext context) => const Leaf('x');

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    widget.described?.add('count');
    properties.add('count', _count);
  }
}

/// A repaint boundary.
final class _Boundary extends LeafRenderObjectWidget {
  const _Boundary();

  @override
  RenderBox createRenderObject(BuildContext context) =>
      RenderBox(pen: 0, boundary: true);
}
