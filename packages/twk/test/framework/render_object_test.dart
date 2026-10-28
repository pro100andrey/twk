import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  group('a render object widget', () {
    test('puts its render object under the nearest ancestor render object', () {
      final tree = Tree()..pump(const Wrapper(Leaf('a')));
      final leaf = tree.host.child! as TestLeaf;
      expect(leaf.label, 'a');
      expect(leaf.parent, same(tree.host));
      expect(tree.elementOf<Wrapper>().renderObject, same(leaf));
    });

    test('updates its render object with a new widget of its type', () {
      final tree = Tree()..pump(const Leaf('a'));
      final leaf = tree.host.child! as TestLeaf;
      tree.pump(const Leaf('b'));
      expect(tree.host.child, same(leaf));
      expect(leaf.label, 'b');
    });

    test('is replaced, render object and all, by a widget of another type', () {
      final tree = Tree()..pump(const Leaf('a'));
      final a = tree.host.child!;
      tree.pump(const OtherLeaf('b'));
      expect(tree.host.child, isNot(same(a)));
      expect(tree.host.child.toString(), 'b');
      expect(a.parent, isNull);
    });

    test('takes the render object of a removed child out of its own', () {
      final tree = Tree()..pump(const Single(child: Leaf('a')));
      final single = tree.host.child! as TestSingle;
      final a = single.child!;
      tree.pump(const Single());
      expect(tree.host.child, same(single));
      expect(single.child, isNull);
      expect(a.parent, isNull);
    });

    test(
      'updates its render object again when its element is marked dirty',
      () {
        final log = <String>[];
        final tree = Tree()..pump(Leaf('a', log: log));
        tree.elementOf<Leaf>().markNeedsBuild();
        expect(log, isEmpty);
        tree.frame();
        expect(log, ['update a']);
      },
    );

    test('is told when its element is unmounted, at the end of the frame', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(Leaf('a', log: log))
        ..show(const OtherLeaf('b'))
        ..owner.buildScope();
      expect(log, isEmpty);
      tree.owner.finalizeTree();
      expect(log, ['unmount a']);
    });
  });

  group('the children of a multi-child render object', () {
    List<String> labels(Tree tree) => [
      for (final c in (tree.host.child! as TestMulti).children) '$c',
    ];

    List<String> logOf(Tree tree) => (tree.host.child! as TestMulti).log;

    test('are the elements of the children, in order', () {
      final tree = Tree()..pump(const Multi([Leaf('a'), Wrapper(Leaf('b'))]));
      final multi = tree.elementOf<Multi>() as MultiChildRenderObjectElement;
      expect(
        [for (final e in multi.children) e.widget.runtimeType],
        [
          Leaf,
          Wrapper,
        ],
      );
      tree.pump(const Multi([Wrapper(Leaf('b'))]));
      expect(
        [for (final e in multi.children) e.widget.runtimeType],
        [
          Wrapper,
        ],
      );
    });

    test('have slots equal for the same index after the same sibling, which '
        'hash alike', () {
      final tree = Tree()..pump(const Multi([Leaf('a'), Leaf('b')]));
      final [a, b] = [
        ...(tree.elementOf<Multi>() as MultiChildRenderObjectElement).children,
      ];
      expect(b.slot, IndexedSlot(1, a));
      expect(b.slot.hashCode, IndexedSlot(1, a).hashCode);
      expect(b.slot, isNot(IndexedSlot(1, b)));
      expect(b.slot, isNot(IndexedSlot(0, a)));
      expect({b.slot, IndexedSlot(1, a), a.slot}, hasLength(2));
    });

    test('are inserted in order', () {
      final tree = Tree()..pump(const Multi([Leaf('a'), Leaf('b'), Leaf('c')]));
      expect(labels(tree), ['a', 'b', 'c']);
      expect(logOf(tree), [
        'insert a after -',
        'insert b after a',
        'insert c after b',
      ]);
    });

    test('match new widgets of their type position by position', () {
      final tree = Tree()..pump(const Multi([Leaf('a'), Leaf('b')]));
      final before = [...(tree.host.child! as TestMulti).children];
      logOf(tree).clear();
      tree.pump(const Multi([Leaf('b'), Leaf('a')]));
      expect((tree.host.child! as TestMulti).children, before);
      expect(labels(tree), ['b', 'a']);
      expect(logOf(tree), isEmpty);
    });

    test('lose the render object of a child removed from the middle; those '
        'after it keep theirs and move', () {
      final tree = Tree()
        ..pump(const Multi([Leaf('a'), OtherLeaf('b'), Leaf('c')]));
      final c = (tree.host.child! as TestMulti).children.last;
      logOf(tree).clear();
      tree.pump(const Multi([Leaf('a'), Leaf('c')]));
      expect(labels(tree), ['a', 'c']);
      expect((tree.host.child! as TestMulti).children.last, same(c));
      expect(logOf(tree), ['remove b', 'move c after a']);
    });

    test('get the render object of a child inserted in the middle after its '
        "previous sibling's", () {
      final tree = Tree()..pump(const Multi([Leaf('a'), Leaf('c')]));
      final [a, c] = [...(tree.host.child! as TestMulti).children];
      logOf(tree).clear();
      tree.pump(const Multi([Leaf('a'), OtherLeaf('b'), Leaf('c')]));
      expect(labels(tree), ['a', 'b', 'c']);
      final children = (tree.host.child! as TestMulti).children;
      expect(children.first, same(a));
      expect(children.last, same(c));
      expect(logOf(tree), ['insert b after a', 'move c after b']);
    });

    test(
      'are the render objects below component children, which move them',
      () {
        final tree = Tree()
          ..pump(const Multi([Wrapper(Leaf('a')), Wrapper(Leaf('c'))]));
        logOf(tree).clear();
        tree.pump(
          const Multi([Wrapper(Leaf('a')), OtherLeaf('b'), Wrapper(Leaf('c'))]),
        );
        expect(labels(tree), ['a', 'b', 'c']);
        expect(logOf(tree), ['insert b after a', 'move c after b']);
        logOf(tree).clear();
        tree.pump(const Multi([Wrapper(Leaf('a'))]));
        expect(labels(tree), ['a']);
        expect(logOf(tree), ['remove b', 'remove c']);
      },
    );
  });
}
