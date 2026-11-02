import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

List<Element> childrenOf(Tree tree) => [
  for (final e in tree.elements)
    if (e.widget is Leaf) e,
];

/// A [Multi] whose element tells whether each update returned the list it
/// was given.
final class Spy extends MultiChildRenderObjectWidget {
  const Spy(List<Widget> children, this.reused) : super(children: children);

  final List<bool> reused;

  @override
  MultiChildRenderObjectElement createElement() => _SpyElement(this);

  @override
  TestMulti createRenderObject(BuildContext context) => TestMulti();
}

final class _SpyElement extends MultiChildRenderObjectElement {
  _SpyElement(Spy super.widget);

  @override
  List<Element> updateChildren(
    List<Element> oldChildren,
    List<Widget> newWidgets, {
    Set<Element>? forgottenChildren,
  }) {
    final result = super.updateChildren(
      oldChildren,
      newWidgets,
      forgottenChildren: forgottenChildren,
    );
    (widget as Spy).reused.add(identical(result, oldChildren));
    return result;
  }

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {}

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) {}

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {}
}

Key k(String s) => ValueKey(s);
IndexedSlot<Element?> slotOf(Element e) => e.slot! as IndexedSlot<Element?>;
Widget leaf(String label, {Key? key}) => Leaf(label, key: key);
Widget otherLeaf(String label) => OtherLeaf(label);
Widget multi(List<Widget> children) => Multi(children);
Widget spy(List<Widget> children, List<bool> reused) => Spy(children, reused);

void main() {
  test('updating as many children as there are reuses the list, another '
      'count makes a new one', () {
    final reused = <bool>[];
    Tree()
      ..pump(spy([leaf('a'), leaf('b')], reused))
      ..pump(spy([leaf('a'), leaf('b')], reused))
      ..pump(spy([leaf('b'), leaf('a')], reused))
      ..pump(spy([leaf('a'), leaf('b'), leaf('c')], reused))
      ..pump(spy([leaf('c')], reused));
    expect(reused, [true, true, false, false]);
  });

  test('an unchanged rebuild of a multi-child widget keeps the children and '
      'their slots, the same objects', () {
    final tree = Tree()..pump(multi([leaf('a'), leaf('b'), leaf('c')]));
    final before = childrenOf(tree);
    final slots = [for (final e in before) e.slot];
    final host = tree.elementOf<Multi>();

    tree.pump(multi([leaf('a'), leaf('b'), leaf('c')]));

    final after = childrenOf(tree);
    expect(after, hasLength(3));
    for (var i = 0; i < 3; i++) {
      expect(after[i], same(before[i]));
      expect(after[i].slot, same(slots[i]), reason: 'slot $i');
    }
    expect(labels(tree, host), ['a', 'b', 'c']);
  });

  test('a changed neighbour moves only what moved: an insert at the front '
      'gives the old children slots at their new places', () {
    final tree = Tree()
      ..pump(multi([leaf('a', key: k('a')), leaf('b', key: k('b'))]));
    final [a, b] = childrenOf(tree);

    tree.pump(
      multi([
        leaf('n', key: k('n')),
        leaf('a', key: k('a')),
        leaf('b', key: k('b')),
      ]),
    );

    final after = childrenOf(tree);
    expect(after[1], same(a));
    expect(after[2], same(b));
    final n = after[0];
    expect(slotOf(n).index, 0);
    expect(slotOf(a).index, 1);
    expect(slotOf(a).value, same(n));
    expect(slotOf(b).index, 2);
    expect(slotOf(b).value, same(a));
    expect(labels(tree, tree.elementOf<Multi>()), ['n', 'a', 'b']);
  });

  test('a reorder of keyed children of the same count moves slots and '
      'render objects right, in place', () {
    final tree = Tree()
      ..pump(
        multi([
          leaf('a', key: k('a')),
          leaf('b', key: k('b')),
          leaf('c', key: k('c')),
          leaf('d', key: k('d')),
        ]),
      );
    final [a, b, c, d] = childrenOf(tree);

    tree.pump(
      multi([
        leaf('d', key: k('d')),
        leaf('b', key: k('b')),
        leaf('a', key: k('a')),
        leaf('c', key: k('c')),
      ]),
    );

    expect(childrenOf(tree), [d, b, a, c]);
    final order = [d, b, a, c];
    for (var i = 0; i < 4; i++) {
      final slot = slotOf(order[i]);
      expect(slot.index, i);
      expect(slot.value, i == 0 ? isNull : same(order[i - 1]));
    }
    expect(labels(tree, tree.elementOf<Multi>()), ['d', 'b', 'a', 'c']);
  });

  test('a replaced child of the same count is a new element at its place', () {
    final tree = Tree()..pump(multi([leaf('a'), leaf('b'), leaf('c')]));
    final [a, b, c] = childrenOf(tree);

    tree.pump(multi([leaf('a'), otherLeaf('x'), leaf('c')]));

    final after = tree.elementOf<Multi>();
    final kids = <Element>[];
    after.visitChildren(kids.add);
    expect(kids[0], same(a));
    expect(kids[1], isNot(same(b)));
    expect(kids[2], same(c));
    expect(slotOf(kids[2]).value, same(kids[1]));
    expect(slotOf(c).value, same(kids[1]));
  });
}

List<String> labels(Tree tree, Element multi) => [
  for (final c in (multi.renderObject! as TestMulti).children) '$c',
];
