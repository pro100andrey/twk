import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  const inner = Wrapper(Leaf('leaf'));
  final log = <String>[];
  final widget = Probe('outer', log, child: Probe('inner', log, child: inner));

  test('findAncestorStateOfType finds the nearest state of the type', () {
    final tree = Tree()..pump(widget);
    final context = tree.elementOf<Leaf>();
    expect(
      context.findAncestorStateOfType<ProbeState>(),
      same(tree.probes.last),
    );
    expect(context.findAncestorStateOfType<State<Probe>>(), tree.probes.last);
    expect(context.findAncestorStateOfType<_Absent>(), isNull);
    expect(tree.root.findAncestorStateOfType<ProbeState>(), isNull);
  });

  test('findAncestorWidgetOfExactType finds the nearest widget of exactly '
      'the type', () {
    final tree = Tree()..pump(widget);
    final context = tree.elementOf<Leaf>();
    expect(context.findAncestorWidgetOfExactType<Wrapper>(), same(inner));
    expect(
      context.findAncestorWidgetOfExactType<Probe>(),
      same(widget.child),
    );
    expect(context.findAncestorWidgetOfExactType<StatefulWidget>(), isNull);
  });

  test('visitAncestorElements walks up from the parent until the visitor '
      'returns false', () {
    final tree = Tree()..pump(widget);
    final seen = <Widget>[];
    tree.elementOf<Leaf>().visitAncestorElements((e) {
      seen.add(e.widget);
      return e.widget is! Probe;
    });
    expect(seen, [same(inner), same(widget.child)]);
  });

  test('findRenderObject of a component is the render object below it', () {
    final tree = Tree()..pump(widget);
    expect(
      tree.probes.first.context.findRenderObject(),
      same(tree.host.child),
    );
  });

  test('an element has its owner, and is mounted until it is unmounted', () {
    final tree = Tree()..pump(widget);
    final context = tree.elementOf<Leaf>();
    expect(context.owner, same(tree.owner));
    tree
      ..show(const Leaf('x'))
      ..owner.buildScope();
    expect(context.mounted, isTrue);
    tree.owner.finalizeTree();
    expect(context.mounted, isFalse);
  });
}

/// A state of a type no element in the tests has.
final class _Absent extends State<Probe> {
  @override
  Widget build(BuildContext context) => const Leaf('absent');
}
