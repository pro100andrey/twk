import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  group('a key', () {
    test('ValueKeys are equal when their types and values are', () {
      final [a, alsoA, b] = ['a', 'a', 'b'];
      expect(ValueKey(a), ValueKey(alsoA));
      expect(ValueKey(a).hashCode, ValueKey(alsoA).hashCode);
      expect(ValueKey(a), isNot(ValueKey(b)));
      expect(ValueKey<Object>(a), isNot(ValueKey<String>(alsoA)));
      expect(ValueKey<String>(alsoA), isNot(ValueKey<Object>(a)));
      expect(Key(a), ValueKey<String>(alsoA));
    });

    test("ValueKeys of types that are each other's subtypes are unequal "
        'still', () {
      expect(const ValueKey<int>(1), isNot(const ValueKey<int?>(1)));
      expect(const ValueKey<int?>(1), isNot(const ValueKey<int>(1)));
      expect(const ValueKey<dynamic>(1), isNot(const ValueKey<Object?>(1)));
      expect(const ValueKey<Object?>(1), isNot(const ValueKey<dynamic>(1)));
      expect(const ValueKey<Object?>(1), const ValueKey<Object?>(1));
      expect(const ValueKey<dynamic>(null), const ValueKey<dynamic>(null));
    });

    test('a ValueKey is equal to itself, even of a value that is not', () {
      final [nan, alsoNan] = [double.nan, double.parse('NaN')];
      final key = ValueKey(nan);
      expect(key == key, isTrue);
      expect(
        Widget.canUpdate(Leaf('a', key: key), Leaf('a', key: key)),
        isTrue,
      );
      expect(key == ValueKey(alsoNan), isFalse);
    });

    test('ValueKeys of related types and equal values are unequal, from '
        'either side, and hash alike', () {
      final [one, oneToo] = <num>[1, 1.0];
      final [Object wide, Object narrow] = [
        ValueKey<num>(one),
        ValueKey<int>(one as int),
      ];
      expect(wide == narrow, isFalse);
      expect(narrow == wide, isFalse);
      expect(wide.hashCode, narrow.hashCode);
      expect(ValueKey<num>(oneToo) == wide, isTrue);
      expect(ValueKey<Object>(one) == ValueKey<String>('$one'), isFalse);
    });

    test('ObjectKeys are equal when their values are the same object', () {
      final [value, equal] = [DateTime(2000), DateTime(2000)];
      expect(ObjectKey(value), ObjectKey(value));
      expect(ObjectKey(value).hashCode, ObjectKey(value).hashCode);
      expect(value, equal);
      expect(ObjectKey(value), isNot(ObjectKey(equal)));
    });

    test('a UniqueKey is equal only to itself', () {
      final key = UniqueKey();
      expect(key, key);
      expect(UniqueKey(), isNot(UniqueKey()));
    });

    test('names its value, or the identity of what it is equal to', () {
      expect('${const ValueKey('a')}', "[<'a'>]");
      expect('${const ValueKey(1)}', '[<1>]');
      final value = <int>[];
      expect('${ObjectKey(value)}', matches(r'^\[List<int>#[0-9a-f]{5}\]$'));
      expect('${UniqueKey()}', matches(r'^\[#[0-9a-f]{5}\]$'));
      expect('${GlobalKey()}', matches(r'^\[GlobalKey#[0-9a-f]{5}\]$'));
      expect(
        '${GlobalKey(debugLabel: 'form')}',
        matches(r'^\[GlobalKey#[0-9a-f]{5} form\]$'),
      );
    });

    test('lets an element go on to a widget of its type with an equal key '
        'only', () {
      expect(
        Widget.canUpdate(
          const Leaf('a', key: ValueKey(1)),
          const Leaf('b', key: ValueKey(1)),
        ),
        isTrue,
      );
      expect(
        Widget.canUpdate(
          const Leaf('a', key: ValueKey(1)),
          const Leaf('a', key: ValueKey(2)),
        ),
        isFalse,
      );
      expect(
        Widget.canUpdate(const Leaf('a'), const Leaf('a', key: ValueKey(1))),
        isFalse,
      );
      expect(
        Widget.canUpdate(
          const Leaf('a', key: ValueKey(1)),
          const OtherLeaf('a', key: ValueKey(1)),
        ),
        isFalse,
      );
    });

    test('that changed replaces the element, its state and render object', () {
      final log = <String>[];
      final tree = Tree()..pump(Probe('a', log, key: const ValueKey(1)));
      final state = tree.stateOf<ProbeState>();
      final leaf = tree.host.child;
      tree.pump(Probe('a', log, key: const ValueKey(2)));
      expect(tree.stateOf<ProbeState>(), isNot(same(state)));
      expect(tree.host.child, isNot(same(leaf)));
      expect(log.skip(3), [
        'a deactivate',
        'a initState',
        'a didChangeDependencies',
        'a build',
        'a dispose',
      ]);
    });
  });

  group('keyed children of a multi-child render object', () {
    TestMulti multiOf(Tree tree) => tree.host.child! as TestMulti;

    List<String> labels(Tree tree) => [
      for (final c in multiOf(tree).children) '$c',
    ];

    Widget leaf(String label) => Leaf(label, key: ValueKey(label));

    test('keep their states and render objects when reordered, which moves '
        'the render objects', () {
      final log = <String>[];
      Widget probe(String name) =>
          Probe(name, log, key: ValueKey(name), child: Leaf(name));
      final tree = Tree()..pump(Multi([probe('a'), probe('b'), probe('c')]));
      final [a, b, c] = tree.probes;
      final [ra, rb, rc] = [...multiOf(tree).children];
      log.clear();
      multiOf(tree).log.clear();
      tree.pump(Multi([probe('c'), probe('a'), probe('b')]));
      expect(tree.probes, [same(c), same(a), same(b)]);
      expect(multiOf(tree).children, [same(rc), same(ra), same(rb)]);
      expect(multiOf(tree).log, [
        'move c after -',
        'move a after c',
        'move b after a',
      ]);
      expect(log, [
        'c didUpdateWidget 0 to 0',
        'c build',
        'a didUpdateWidget 0 to 0',
        'a build',
        'b didUpdateWidget 0 to 0',
        'b build',
      ]);
    });

    test('keep their render objects when a child is inserted before them', () {
      final tree = Tree()..pump(Multi([leaf('a'), leaf('b')]));
      final [a, b] = [...multiOf(tree).children];
      multiOf(tree).log.clear();
      tree.pump(Multi([leaf('x'), leaf('a'), leaf('b')]));
      expect(labels(tree), ['x', 'a', 'b']);
      expect(multiOf(tree).children.skip(1), [same(a), same(b)]);
      expect(multiOf(tree).log, [
        'insert x after -',
        'move a after x',
        'move b after a',
      ]);
    });

    test('keep their states and render objects when a child before them is '
        'removed', () {
      final log = <String>[];
      Widget probe(String name) =>
          Probe(name, log, key: ValueKey(name), child: Leaf(name));
      final tree = Tree()..pump(Multi([probe('a'), probe('b'), probe('c')]));
      final [_, b, c] = tree.probes;
      final [_, rb, rc] = [...multiOf(tree).children];
      log.clear();
      multiOf(tree).log.clear();
      tree.pump(Multi([probe('b'), probe('c')]));
      expect(tree.probes, [same(b), same(c)]);
      expect(multiOf(tree).children, [same(rb), same(rc)]);
      expect(multiOf(tree).log, [
        'move b after -',
        'move c after b',
        'remove a',
      ]);
      expect(log, [
        'b didUpdateWidget 0 to 0',
        'b build',
        'c didUpdateWidget 0 to 0',
        'c build',
        'a deactivate',
        'a dispose',
      ]);
    });

    test('are matched by key among the middle children, where those '
        'without a key are replaced', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(
          Multi([
            Probe('a', log, key: const ValueKey('a'), child: const Leaf('a')),
            Probe('x', log, child: const Leaf('x')),
          ]),
        );
      final [a, _] = tree.probes;
      final [ra, _] = [...multiOf(tree).children];
      log.clear();
      multiOf(tree).log.clear();
      tree.pump(
        Multi([
          Probe('y', log, child: const Leaf('y')),
          Probe('a', log, key: const ValueKey('a'), child: const Leaf('a')),
        ]),
      );
      expect(tree.probes.last, same(a));
      expect(multiOf(tree).children.last, same(ra));
      expect(multiOf(tree).log, [
        'remove x',
        'insert y after -',
        'move a after y',
      ]);
      expect(log, [
        'x deactivate',
        'y initState',
        'y didChangeDependencies',
        'y build',
        'a didUpdateWidget 0 to 0',
        'a build',
        'x dispose',
      ]);
    });

    test('whose key comes back on a widget of another type are replaced, '
        'after the new child is inserted', () {
      final tree = Tree()..pump(Multi([leaf('a'), leaf('b')]));
      final [a, b] = [...multiOf(tree).children];
      multiOf(tree).log.clear();
      tree.pump(
        Multi([const OtherLeaf('b', key: ValueKey('b')), leaf('a')]),
      );
      expect(labels(tree), ['b', 'a']);
      expect(multiOf(tree).children.first, isNot(same(b)));
      expect(multiOf(tree).children.last, same(a));
      expect(multiOf(tree).log, [
        'insert b after -',
        'move a after b',
        'remove b',
      ]);
    });

    test('with equal keys are an error that names the key', () {
      expect(
        () => Tree().pump(Multi([leaf('a'), leaf('b'), leaf('a')])),
        throwsA(_duplicateKey("[<'a'>]")),
      );
    });

    test('given with equal keys to an element that has children are an '
        'error', () {
      final tree = Tree()..pump(Multi([leaf('a'), leaf('b')]));
      expect(
        () => tree.pump(Multi([leaf('b'), leaf('b')])),
        throwsA(_duplicateKey("[<'b'>]")),
      );
    });
  });

  group('a GlobalKey', () {
    test('finds the element, widget and state of its widget', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final widget = Probe('a', log, key: key);
      final tree = Tree()..pump(Multi([const Leaf('x'), widget]));
      expect(key.currentContext, same(tree.elementOf<Probe>()));
      expect(key.currentWidget, same(widget));
      expect(key.currentState, same(tree.stateOf<ProbeState>()));
    });

    test('has no state for a widget without one, or with one of another '
        'type', () {
      final leafKey = GlobalKey();
      final otherKey = GlobalKey<_OtherState>();
      final log = <String>[];
      final tree = Tree()
        ..pump(
          Multi([
            Leaf('a', key: leafKey),
            Probe('b', log, key: otherKey, child: const OtherLeaf('b')),
          ]),
        );
      expect(leafKey.currentContext, same(tree.elementOf<Leaf>()));
      expect(leafKey.currentState, isNull);
      expect(otherKey.currentContext, same(tree.elementOf<Probe>()));
      expect(otherKey.currentState, isNull);
    });

    test('finds the element until it is unmounted, at the end of the frame '
        'that removed it', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final tree = Tree()..pump(Probe('a', log, key: key));
      final state = tree.stateOf<ProbeState>();
      tree
        ..show(const Leaf('x'))
        ..owner.buildScope();
      expect(key.currentState, same(state));
      tree.owner.finalizeTree();
      expect(key.currentContext, isNull);
      expect(key.currentWidget, isNull);
      expect(key.currentState, isNull);
    });

    test('whose widget moved to another parent finds the element there', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final tree = Tree()
        ..pump(Single(child: Probe('a', log, key: key)))
        ..pump(Multi([Probe('a', log, key: key)]));
      expect(key.currentState, same(tree.stateOf<ProbeState>()));
      expect(key.currentContext, same(tree.elementOf<Probe>()));
    });

    test('is in one tree at a time', () {
      final key = GlobalKey();
      Tree().pump(Leaf('a', key: key));
      expect(
        () => Tree().pump(Leaf('b', key: key)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('an element', () {
    test('given a widget its own cannot update, of another type or key, '
        'asserts, naming both', () {
      final tree = Tree()..pump(const Leaf('a', key: ValueKey(1)));
      final element = tree.elementOf<Leaf>();
      for (final other in [
        const OtherLeaf('b'),
        const Leaf('a', key: ValueKey(2)),
      ]) {
        expect(
          () => element.update(other),
          throwsA(
            isA<AssertionError>().having(
              (e) => '${e.message}',
              'message',
              '$other cannot update $element',
            ),
          ),
        );
      }
      expect(element.widget, const Leaf('a', key: ValueKey(1)));
    });
  });
}

/// The error of children with equal keys, naming [key].
Matcher _duplicateKey(String key) => isA<AssertionError>().having(
  (e) => '${e.message}',
  'message',
  allOf(contains('equal keys'), contains(key)),
);

final class _OtherState extends State<Probe> {
  @override
  Widget build(BuildContext context) => const Leaf('other');
}
