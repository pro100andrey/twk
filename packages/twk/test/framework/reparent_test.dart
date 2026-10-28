import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  TestMulti multiOf(Tree tree) => tree.host.child! as TestMulti;

  group('an element whose widget with a GlobalKey moved in a frame', () {
    test('goes with it to another parent, with its state and render '
        'object, and back', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      Widget probe() => Probe('a', log, key: key, child: const Leaf('a'));
      final tree = Tree()..pump(Single(child: probe()));
      final element = key.currentContext;
      final state = key.currentState;
      final single = tree.host.child! as TestSingle;
      final leaf = single.child!;
      log.clear();
      tree.pump(Multi([const Leaf('x'), probe(), const Leaf('y')]));
      final multi = multiOf(tree);
      expect(key.currentContext, same(element));
      expect(key.currentState, same(state));
      expect(multi.children, [isA<TestLeaf>(), same(leaf), isA<TestLeaf>()]);
      expect([single.child, leaf.parent], [isNull, same(multi)]);
      expect(multi.log, [
        'insert x after -',
        'insert a after x',
        'insert y after a',
      ]);
      expect(log, [
        'a deactivate',
        'a activate',
        'a didUpdateWidget 0 to 0',
        'a build',
      ]);
      log.clear();
      tree.pump(Single(child: probe()));
      expect(key.currentState, same(state));
      expect((tree.host.child! as TestSingle).child, same(leaf));
      expect(log, [
        'a deactivate',
        'a activate',
        'a didUpdateWidget 0 to 0',
        'a build',
      ]);
    });

    test('goes with it to a parent before the one it left, and back', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final probe = Probe('a', log, key: key, child: const Leaf('a'));
      final tree = Tree()..pump(Multi([const Single(), Single(child: probe)]));
      final state = key.currentState;
      final [first, second] = [
        for (final s in multiOf(tree).children) s as TestSingle,
      ];
      final leaf = second.child;
      log.clear();
      tree.pump(Multi([Single(child: probe), const Single()]));
      expect(key.currentState, same(state));
      expect([first.child, second.child], [same(leaf), isNull]);
      tree.pump(Multi([const Single(), Single(child: probe)]));
      expect(key.currentState, same(state));
      expect([first.child, second.child], [isNull, same(leaf)]);
      expect(log, [
        'a deactivate',
        'a activate',
        'a build',
        'a deactivate',
        'a activate',
        'a build',
      ]);
    });

    test('goes with it out of a parent that is rebuilt after the one it '
        'went to', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final probe = Probe('a', log, key: key, child: const Leaf('a'));
      final tree = Tree()..pump(Multi([const Single(), Wrapper(probe)]));
      final state = key.currentState;
      final [single, leaf] = [...multiOf(tree).children];
      tree.pump(Multi([Single(child: probe), const Wrapper(Leaf('x'))]));
      expect(key.currentState, same(state));
      expect((single as TestSingle).child, same(leaf));
      expect('${multiOf(tree).children.last}', 'x');
    });

    test('goes with it into a sibling', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final probe = Probe('a', log, key: key, child: const Leaf('a'));
      final tree = Tree()..pump(Multi([const Single(), probe]));
      final state = key.currentState;
      final multi = multiOf(tree);
      final [single, leaf] = [...multi.children];
      multi.log.clear();
      tree.pump(Multi([Single(child: probe)]));
      expect(key.currentState, same(state));
      expect(multi.children, [same(single)]);
      expect((single as TestSingle).child, same(leaf));
      expect(multi.log, ['remove a']);
    });

    test('goes with it deeper and back, the depths below it following', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      Widget probe() => Probe('a', log, key: key, child: const Leaf('a'));
      final tree = Tree()..pump(Multi([probe()]));
      final element = key.currentContext! as Element;
      final leaf = multiOf(tree).children.single;
      List<int> depths() => [element.depth, tree.elementOf<Leaf>().depth];
      expect(depths(), [4, 5]);
      tree.pump(Multi([Wrapper(Wrapper(probe()))]));
      expect(key.currentContext, same(element));
      expect(multiOf(tree).children, [same(leaf)]);
      expect(depths(), [6, 7]);
      tree.pump(Multi([probe()]));
      expect(key.currentContext, same(element));
      expect(depths(), [4, 5]);
    });

    test('is built once at its new place when it was dirty', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final inner = Probe('a', log, key: key);
      final tree = Tree()
        ..pump(
          Probe(
            'outer',
            log,
            builder: (s) =>
                s.count == 0 ? Single(child: inner) : Multi([inner]),
          ),
        );
      final [outer, a] = tree.probes;
      log.clear();
      a.change(() {});
      outer.change(() => outer.count++);
      tree.frame();
      expect(tree.probes.last, same(a));
      expect(log, ['outer build', 'a deactivate', 'a activate', 'a build']);
    });

    test('is built at its new place when it was dirty and removed in an '
        'earlier build scope of the frame', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final probe = Probe('a', log, key: key);
      final tree = Tree()..pump(Multi([Single(child: probe)]));
      final a = tree.stateOf<ProbeState>();
      log.clear();
      a.change(() {});
      tree
        ..show(const Multi([Single()]))
        ..owner.buildScope()
        ..pump(Multi([Single(child: probe)]));
      expect(key.currentState, same(a));
      expect(log, ['a deactivate', 'a activate', 'a build']);
      a.change(() {});
      tree.frame();
      expect(log.last, 'a build');
    });

    test('depends on the inherited widgets of its new place instead of '
        'those of the old one', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final probe = Probe(
        'a',
        log,
        key: key,
        child: const _Label(),
        onDidChangeDependencies: (state) {
          final value = state.context
              .dependOnInheritedWidgetOfExactType<_Value>();
          log.add('a sees ${value!.value}');
        },
      );
      Widget values(int first, int second, {required bool moved}) => Multi([
        _Value(first, child: Single(child: moved ? null : probe)),
        _Value(second, child: Single(child: moved ? probe : null)),
      ]);
      final tree = Tree()..pump(values(1, 2, moved: false));
      final label = tree.elementOf<_Label>().renderObject!;
      expect('$label', 'v1');
      log.clear();
      tree.pump(values(1, 2, moved: true));
      expect(log, [
        'a deactivate',
        'a activate',
        'a didChangeDependencies',
        'a sees 2',
        'a build',
      ]);
      expect('$label', 'v2');
      log.clear();
      tree.pump(values(3, 2, moved: true));
      expect(log, isEmpty);
      expect('$label', 'v2');
      tree.pump(values(3, 4, moved: true));
      expect(log, ['a didChangeDependencies', 'a sees 4', 'a build']);
      expect('$label', 'v4');
    });

    test('has the data of the parent data widgets of its new place put on '
        'its render object', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      final probe = Probe('a', log, key: key, child: const Leaf('a'));
      final tree = Tree()
        ..pump(
          Multi([
            _Tag('x', child: probe),
            const _Tag('y', child: Leaf('b')),
          ]),
        );
      final multi = multiOf(tree);
      final a = multi.children.first;
      tree.pump(
        Multi([
          const _Tag('x', child: Leaf('b')),
          _Tag('y', child: probe),
        ]),
      );
      String tagOf(RenderObject child) =>
          (child.parentData as TestParentData).tag!;
      expect(multi.children.last, same(a));
      expect(
        [for (final c in multi.children) '$c ${tagOf(c)}'],
        [
          'b x',
          'a y',
        ],
      );
    });

    test('is unmounted at the end of a frame that did not put it back, and '
        'the widget later gets a new element', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      Widget probe() => Probe('a', log, key: key);
      final tree = Tree()..pump(Single(child: probe()));
      final state = key.currentState;
      log.clear();
      tree
        ..pump(const Leaf('x'))
        ..pump(Multi([probe()]));
      expect(key.currentState, isNot(same(state)));
      expect(log, [
        'a deactivate',
        'a dispose',
        'a initState',
        'a didChangeDependencies',
        'a build',
      ]);
    });
  });

  test('an element activated while it is in the tree asserts, naming it '
      'and that it is active', () {
    final tree = Tree()..pump(const Wrapper(Leaf('a')));
    for (final element in [tree.elementOf<Wrapper>(), tree.elementOf<Leaf>()]) {
      expect(
        element.activate,
        throwsA(
          isA<AssertionError>().having(
            (e) => '${e.message}',
            'message',
            '$element activated while active',
          ),
        ),
      );
    }
  });

  group('a GlobalKey on two widgets at once', () {
    /// The error that [key] is on two widgets, [place] and [other].
    Matcher onTwo(GlobalKey key, String place, String other) =>
        isA<AssertionError>().having(
          (e) => '${e.message}',
          'message',
          contains('$key is on two widgets at once, $place and $other'),
        );

    test('of a type is an error that names both places', () {
      final key = GlobalKey();
      expect(
        () => Tree().pump(
          Multi([
            Single(child: Leaf('a', key: key)),
            Wrapper(Leaf('b', key: key)),
          ]),
        ),
        throwsA(
          onTwo(
            key,
            'under RootWidget > Single > Multi > Single',
            'at RootWidget > Single > Multi > Wrapper > Leaf-$key',
          ),
        ),
      );
      final other = GlobalKey();
      expect(
        () => Tree().pump(
          Multi([
            Wrapper(Leaf('a', key: other)),
            Single(child: Leaf('b', key: other)),
          ]),
        ),
        throwsA(
          onTwo(
            other,
            'under RootWidget > Single > Multi > Wrapper',
            'at RootWidget > Single > Multi > Single > Leaf-$other',
          ),
        ),
      );
    });

    test('on a child and below a later sibling of it is an error that names '
        'both places', () {
      final key = GlobalKey();
      expect(
        () => Tree().pump(
          Multi([
            Leaf('a', key: key),
            Wrapper(Leaf('b', key: key)),
          ]),
        ),
        throwsA(
          onTwo(
            key,
            'under RootWidget > Single > Multi',
            'at RootWidget > Single > Multi > Wrapper > Leaf-$key',
          ),
        ),
      );
    });

    test('that a parent still has after another took it goes back to it, '
        'and is an error', () {
      // alone, after a sibling, and before one replaced in the second frame
      for (final sibling in ['', 'x', 'y']) {
        final key = GlobalKey();
        Widget inner({bool later = false}) => Multi([
          if (sibling == 'x') const Leaf('x'),
          Leaf('a', key: key),
          if (sibling == 'y')
            if (later) const OtherLeaf('y') else const Leaf('y'),
        ]);
        final tree = Tree()..pump(Multi([const Single(), inner()]));
        final element = key.currentContext;
        expect(
          () => tree.pump(
            Multi([Single(child: Leaf('a', key: key)), inner(later: true)]),
          ),
          throwsA(
            onTwo(
              key,
              'under RootWidget > Single > Multi > Single',
              'at RootWidget > Single > Multi > Multi > Leaf-$key',
            ),
          ),
          reason: "with '$sibling'",
        );
        expect(
          [
            for (final e in tree.elements)
              if (e.widget.key == key) e,
          ],
          [same(element)],
        );
      }
    });

    test('of two types is an error that names both places', () {
      final key = GlobalKey();
      expect(
        () => Tree().pump(
          Multi([
            Single(child: Leaf('a', key: key)),
            Single(child: OtherLeaf('b', key: key)),
          ]),
        ),
        throwsA(
          onTwo(
            key,
            'at RootWidget > Single > Multi > Single > Leaf-$key',
            'at RootWidget > Single > Multi > Single > OtherLeaf-$key',
          ),
        ),
      );
    });

    test('one below the other is an error that names both places', () {
      final key = GlobalKey();
      final log = <String>[];
      expect(
        () => Tree().pump(
          Probe(
            'a',
            log,
            key: key,
            child: Single(child: Probe('b', log, key: key)),
          ),
        ),
        throwsA(
          onTwo(
            key,
            'under RootWidget > Single > Probe-$key > Single',
            'at RootWidget > Single > Probe-$key',
          ),
        ),
      );
    });

    test('that a rebuild put on a second widget while the first stays is an '
        'error', () {
      final key = GlobalKey();
      final log = <String>[];
      final probe = Probe('p', log, key: key);
      final tree = Tree()
        ..pump(
          Multi([
            Probe('s1', log, builder: (_) => probe),
            Probe(
              's2',
              log,
              builder: (s) => s.count == 0 ? const Leaf('x') : probe,
            ),
          ]),
        );
      final s2 = tree.probes.last;
      s2.change(() => s2.count++);
      expect(
        tree.frame,
        throwsA(
          onTwo(
            key,
            'under RootWidget > Single > Multi > Probe',
            'at RootWidget > Single > Multi > Probe > Probe-$key',
          ),
        ),
      );
    });
  });
}

/// An inherited [value].
final class _Value extends InheritedWidget {
  const _Value(this.value, {required super.child});

  final int value;

  @override
  bool updateShouldNotify(_Value oldWidget) => value != oldWidget.value;
}

/// A [TestLeaf] labelled with the [_Value] above it, which it depends on.
final class _Label extends LeafRenderObjectWidget {
  const _Label();

  String _label(BuildContext context) =>
      'v${context.dependOnInheritedWidgetOfExactType<_Value>()!.value}';

  @override
  RenderObject createRenderObject(BuildContext context) =>
      TestLeaf(_label(context));

  @override
  void updateRenderObject(BuildContext context, TestLeaf renderObject) {
    renderObject.label = _label(context);
  }
}

/// Puts [tag] on its child in a [Multi].
final class _Tag extends ParentDataWidget<TestParentData> {
  const _Tag(this.tag, {required super.child});

  final String tag;

  @override
  void applyParentData(RenderObject renderObject) =>
      (renderObject.parentData as TestParentData).tag = tag;

  @override
  Type get debugTypicalAncestorWidgetClass => Multi;
}
