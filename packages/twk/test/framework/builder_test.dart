import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  group('a Builder', () {
    test('builds what its function returns with its own context, which '
        'finds what the same build put above it', () {
      BuildContext? seen;
      final tree = Tree()
        ..pump(
          _Value(
            1,
            child: Builder(
              builder: (context) {
                seen = context;
                final value = context
                    .dependOnInheritedWidgetOfExactType<_Value>()!
                    .value;
                return Leaf('value $value');
              },
            ),
          ),
        );
      expect(seen, same(tree.elementOf<Builder>()));
      expect((tree.host.child! as TestLeaf).label, 'value 1');
    });

    test('builds again when what it depends on changes, and when the '
        'widget above rebuilds', () {
      var builds = 0;
      Widget builder(BuildContext context) {
        builds++;
        final value = context
            .dependOnInheritedWidgetOfExactType<_Value>()!
            .value;
        return Leaf('value $value');
      }

      // the same widget: built again for the value alone
      final kept = Builder(builder: builder);
      final tree = Tree()..pump(_Value(1, child: kept));
      expect(builds, 1);
      tree.pump(_Value(1, child: kept));
      expect(builds, 1);
      tree.pump(_Value(2, child: kept));
      expect(builds, 2);
      expect((tree.host.child! as TestLeaf).label, 'value 2');
      tree.pump(_Value(2, child: Builder(builder: builder)));
      expect(builds, 3);
    });
  });

  group('a StatefulBuilder', () {
    test('builds again in the next build when its setState is called, '
        'its calls before then one build', () {
      var count = 0;
      var builds = 0;
      late StateSetter set;
      final tree = Tree()
        ..pump(
          StatefulBuilder(
            builder: (context, setState) {
              builds++;
              set = setState;
              return Leaf('count $count');
            },
          ),
        );
      expect(builds, 1);
      set(() => count++);
      set(() => count++);
      expect((tree.host.child! as TestLeaf).label, 'count 0');
      tree.owner.buildScope();
      expect(builds, 2);
      expect((tree.host.child! as TestLeaf).label, 'count 2');
    });

    test('keeps its state, and builds with the builder of the widget it '
        'shows now', () {
      late StateSetter first;
      final tree = Tree()
        ..pump(
          StatefulBuilder(
            builder: (context, setState) {
              first = setState;
              return const Leaf('first');
            },
          ),
        );
      final state =
          (tree.elementOf<StatefulBuilder>() as StatefulElement).state;
      tree.pump(
        StatefulBuilder(builder: (context, setState) => const Leaf('second')),
      );
      expect(
        (tree.elementOf<StatefulBuilder>() as StatefulElement).state,
        same(state),
      );
      expect((tree.host.child! as TestLeaf).label, 'second');
      first(() {});
      tree.owner.buildScope();
      expect((tree.host.child! as TestLeaf).label, 'second');
    });

    test('asserts on a setState after it left the tree', () {
      late StateSetter set;
      Tree()
        ..pump(
          StatefulBuilder(
            builder: (context, setState) {
              set = setState;
              return const Leaf('shown');
            },
          ),
        )
        ..pump(const Leaf('in its place'));
      expect(() => set(() {}), throwsA(isA<AssertionError>()));
    });
  });
}

final class _Value extends InheritedWidget {
  const _Value(this.value, {required super.child});

  final int value;

  @override
  bool updateShouldNotify(_Value oldWidget) => value != oldWidget.value;
}
