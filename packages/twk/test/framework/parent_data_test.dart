import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  group('a ParentDataWidget', () {
    List<RenderObject> childrenOf(Tree tree) =>
        (tree.host.child! as TestMulti).children;

    String? tagOf(RenderObject child) =>
        (child.parentData as TestParentData).tag;

    test('puts its data on the render object of its child', () {
      final tree = Tree()
        ..pump(const Multi([_Tag('x', child: Leaf('a')), Leaf('b')]));
      final [a, b] = childrenOf(tree);
      expect([tagOf(a), tagOf(b)], ['x', null]);
    });

    test('reaches it through widgets without render objects above and '
        'below', () {
      final tree = Tree()
        ..pump(
          const Multi([
            Wrapper(_Tag('x', child: Wrapper(Wrapper(Leaf('a'))))),
          ]),
        );
      expect(tagOf(childrenOf(tree).single), 'x');
    });

    test('puts the data of a widget that replaced it on the same render '
        'object', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(Multi([_Tag('x', log: log, child: const Leaf('a'))]));
      final a = childrenOf(tree).single;
      log.clear();
      tree.pump(Multi([_Tag('y', log: log, child: const Leaf('a'))]));
      expect(childrenOf(tree).single, same(a));
      expect(tagOf(a), 'y');
      expect(log, ['tag a y']);
    });

    test('puts its data on a render object that replaced the one below it '
        'in a rebuild of its own', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(
          Multi([
            _Tag(
              'x',
              child: Probe(
                'p',
                log,
                builder: (state) =>
                    state.count == 0 ? const Leaf('a') : const OtherLeaf('b'),
              ),
            ),
          ]),
        );
      final state = tree.stateOf<ProbeState>();
      state.change(() => state.count++);
      tree.frame();
      final b = childrenOf(tree).single;
      expect('$b', 'b');
      expect(tagOf(b), 'x');
    });

    test('goes with one that puts another kind of data', () {
      final tree = Tree()
        ..pump(const Multi([_Shift(3, child: _Tag('x', child: Leaf('a')))]));
      final a = childrenOf(tree).single;
      expect([tagOf(a), a.parentData.dx], ['x', 3]);
    });

    test('under a render object that keeps another kind of data on its '
        'children is an error that names both', () {
      expect(
        () => Tree().pump(const Single(child: _Tag('x', child: Leaf('a')))),
        throwsA(
          isA<AssertionError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains('_Tag'), contains('Single'), contains('Multi')),
          ),
        ),
      );
    });

    test('inside another one that puts the same kind of data is an error '
        'that names both', () {
      expect(
        () => Tree().pump(
          const Multi([
            _Tag(
              'x',
              key: Key('outer'),
              child: Wrapper(_Tag('y', key: Key('inner'), child: Leaf('a'))),
            ),
          ]),
        ),
        throwsA(
          isA<AssertionError>().having(
            (e) => '${e.message}',
            'message',
            allOf(contains("_Tag-[<'outer'>]"), contains("_Tag-[<'inner'>]")),
          ),
        ),
      );
    });
  });
}

/// Puts [tag] on its child in a [Multi]; [log], when given, records each
/// time it does.
final class _Tag extends ParentDataWidget<TestParentData> {
  const _Tag(this.tag, {required super.child, super.key, this.log});

  final String tag;
  final List<String>? log;

  @override
  void applyParentData(RenderObject renderObject) {
    log?.add('tag $renderObject $tag');
    (renderObject.parentData as TestParentData).tag = tag;
  }

  @override
  Type get debugTypicalAncestorWidgetClass => Multi;
}

/// Puts [dx] on its child, under any parent.
final class _Shift extends ParentDataWidget<ParentData> {
  const _Shift(this.dx, {required super.child});

  final int dx;

  @override
  void applyParentData(RenderObject renderObject) =>
      renderObject.parentData.dx = dx;

  @override
  Type get debugTypicalAncestorWidgetClass => Multi;
}
