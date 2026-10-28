import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  group('an InheritedWidget', () {
    test('is found by its exact type, the nearest of a type shadowing '
        'those above it', () {
      final seen = <InheritedWidget?>[];
      final other = _Other(
        0,
        child: _Build('look', (context) {
          seen
            ..add(context.dependOnInheritedWidgetOfExactType<_Value>())
            ..add(context.dependOnInheritedWidgetOfExactType<_Sub>())
            ..add(context.dependOnInheritedWidgetOfExactType<_Other>())
            ..add(
              context.dependOnInheritedWidgetOfExactType<InheritedWidget>(),
            );
          return const Leaf('look');
        }),
      );
      final inner = _Value(2, child: other);
      final sub = _Sub(9, child: inner);
      final outer = _Value(1, child: sub);
      final tree = Tree()..pump(outer);
      expect(seen, [same(inner), same(sub), same(other), isNull]);
      final above = tree.elementOf<_Sub>();
      expect(above.getInheritedWidgetOfExactType<_Value>(), same(outer));
      expect(above.getInheritedWidgetOfExactType<_Other>(), isNull);
      expect(tree.root.getInheritedWidgetOfExactType<_Value>(), isNull);
    });

    test('found with getInheritedWidgetOfExactType is not depended on', () {
      final log = <String>[];
      final child = Probe(
        'a',
        log,
        builder: (state) {
          final found = state.context.getInheritedWidgetOfExactType<_Value>();
          log.add('a reads ${found?.value}');
          return const Leaf('a');
        },
      );
      final tree = Tree()..pump(_Value(1, log: log, child: child));
      expect(log.last, 'a reads 1');
      log.clear();
      tree.pump(_Value(2, log: log, child: child));
      expect(log, isEmpty);
    });

    test('has its element found with getElementForInheritedWidgetOfExactType '
        'and depended on with dependOnInheritedElement', () {
      final log = <String>[];
      final elements = <InheritedElement?>[];
      final child = Probe(
        'a',
        log,
        builder: (state) {
          final context = state.context;
          final element = context
              .getElementForInheritedWidgetOfExactType<_Value>();
          elements.add(element);
          final value = context.dependOnInheritedElement(element!) as _Value;
          log.add('a reads ${value.value}');
          return const Leaf('a');
        },
      );
      final tree = Tree()..pump(_Value(1, log: log, child: child));
      expect(elements, [same(tree.elementOf<_Value>())]);
      log.clear();
      tree.pump(_Value(2, log: log, child: child));
      expect(log, [
        'notify a',
        'a didChangeDependencies',
        'a build',
        'a reads 2',
      ]);
    });

    test('depended on in initState is an error', () {
      expect(
        () => Tree().pump(const _Value(1, child: _ReadsInInitState())),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('an InheritedWidget replaced', () {
    test('rebuilds only the elements that depend on it, a State told in '
        'didChangeDependencies first', () {
      final log = <String>[];
      final child = Multi([
        _reader('a', log),
        Probe('b', log),
        Wrapper(
          _Build('c', (context) {
            final value = context.dependOnInheritedWidgetOfExactType<_Value>();
            log.add('c reads ${value!.value}');
            return const Leaf('c');
          }),
        ),
      ]);
      final tree = Tree()..pump(_Value(1, log: log, child: child));
      log.clear();
      tree.pump(_Value(2, log: log, child: child));
      expect(log, [
        'notify a',
        'notify c',
        'a didChangeDependencies',
        'a build',
        'a reads 2',
        'c reads 2',
      ]);
    });

    test('rebuilds none of them when updateShouldNotify says no', () {
      final log = <String>[];
      final child = _reader('a', log);
      final tree = Tree()..pump(_Value(1, log: log, child: child));
      log.clear();
      final next = _Value(1, log: log, child: child);
      tree.pump(next);
      expect(log, isEmpty);
      final context = tree.elementOf<Probe>();
      expect(context.getInheritedWidgetOfExactType<_Value>(), same(next));
    });

    test('updates a render object that depends on it in createRenderObject '
        'and updateRenderObject', () {
      const label = _Label();
      final tree = Tree()..pump(const _Value(1, child: label));
      final leaf = tree.host.child! as TestLeaf;
      expect(leaf.label, 'v1');
      tree.pump(const _Value(2, child: label));
      expect(leaf.label, 'v2');
    });
  });

  group('a dependency', () {
    test('is dropped by a build that does not ask for it again, and kept by '
        'one that does', () {
      final log = <String>[];
      final child = Probe(
        'a',
        log,
        builder: (state) {
          final context = state.context
            ..dependOnInheritedWidgetOfExactType<_Value>();
          if (state.count == 0) {
            context.dependOnInheritedWidgetOfExactType<_Other>();
          }
          return const Leaf('a');
        },
      );
      Widget values(int value, int other) => _Other(
        other,
        child: _Value(value, log: log, child: child),
      );
      final tree = Tree()..pump(values(1, 1));
      final state = tree.stateOf<ProbeState>();
      state.change(() => state.count++);
      tree.frame();
      log.clear();
      tree.pump(values(1, 2));
      expect(log, isEmpty);
      tree.pump(values(2, 2));
      expect(log, ['notify a', 'a didChangeDependencies', 'a build']);
    });

    test('asked for in State.didChangeDependencies lasts through builds, '
        'until a call of it does not ask again', () {
      final log = <String>[];
      var depends = true;
      final child = Probe(
        'a',
        log,
        onDidChangeDependencies: (state) {
          if (depends) {
            state.context.dependOnInheritedWidgetOfExactType<_Value>();
          }
        },
      );
      final tree = Tree()..pump(_Value(1, log: log, child: child));
      tree.stateOf<ProbeState>().change(() {});
      tree.frame();
      log.clear();
      tree.pump(_Value(2, log: log, child: child));
      expect(log, ['notify a', 'a didChangeDependencies', 'a build']);
      log.clear();
      tree.pump(_Value(3, log: log, child: child));
      expect(log, ['notify a', 'a didChangeDependencies', 'a build']);
      depends = false;
      tree.pump(_Value(4, log: log, child: child));
      log.clear();
      tree.pump(_Value(5, log: log, child: child));
      expect(log, isEmpty);
    });

    test('of a render object element is dropped by an updateRenderObject '
        'that does not ask for it again', () {
      final log = <String>[];
      const label = _Label(depends: false);
      final tree = Tree()
        ..pump(_Value(1, log: log, child: const _Label()))
        ..pump(_Value(1, log: log, child: label));
      expect((tree.host.child! as TestLeaf).label, '-');
      tree.pump(_Value(2, log: log, child: label));
      expect(log, isEmpty);
    });

    test('is dropped when the dependent leaves the tree, before it is '
        'unmounted, and it finds no inherited widgets', () {
      final log = <String>[];
      final tree = Tree()..pump(_Value(1, log: log, child: _reader('a', log)));
      final context = tree.elementOf<Probe>();
      tree
        ..show(_Value(1, log: log, child: const Leaf('x')))
        ..owner.buildScope();
      expect(context.getInheritedWidgetOfExactType<_Value>(), isNull);
      log.clear();
      tree
        ..show(_Value(2, log: log, child: const Leaf('x')))
        ..owner.buildScope();
      expect(log, isEmpty);
      tree.owner.finalizeTree();
      expect(log, ['a dispose']);
    });
  });
}

/// A [Probe] named [name] that depends on the [_Value] above it and logs the
/// value it read.
Probe _reader(String name, List<String> log) => Probe(
  name,
  log,
  builder: (state) {
    final value = state.context.dependOnInheritedWidgetOfExactType<_Value>();
    log.add('$name reads ${value!.value}');
    return Leaf(name);
  },
);

/// An inherited [value]; its element logs into [log] each dependent it
/// tells of a change.
class _Value extends InheritedWidget {
  const _Value(this.value, {required super.child, this.log});

  final int value;
  final List<String>? log;

  @override
  InheritedElement createElement() => _ValueElement(this);

  @override
  bool updateShouldNotify(_Value oldWidget) => value != oldWidget.value;
}

final class _ValueElement extends InheritedElement {
  _ValueElement(_Value super.widget);

  @override
  _Value get widget => super.widget as _Value;

  @override
  void notifyDependent(_Value oldWidget, Element dependent) {
    final name = switch (dependent.widget) {
      Probe(:final name) || _Build(:final name) => name,
      final other => '${other.runtimeType}',
    };
    widget.log?.add('notify $name');
    super.notifyDependent(oldWidget, dependent);
  }
}

/// A subtype of [_Value]: not a [_Value] to a lookup by exact type.
final class _Sub extends _Value {
  const _Sub(super.value, {required super.child});
}

/// An inherited [value] of another type than [_Value].
final class _Other extends InheritedWidget {
  const _Other(this.value, {required super.child});

  final int value;

  @override
  bool updateShouldNotify(_Other oldWidget) => value != oldWidget.value;
}

/// A stateless widget named [name] that shows what [builder] returns.
final class _Build extends StatelessWidget {
  const _Build(this.name, this.builder);

  final String name;
  final Widget Function(BuildContext context) builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

/// A [TestLeaf] labelled with the [_Value] above it if it [depends] on it,
/// else with '-'.
final class _Label extends LeafRenderObjectWidget {
  const _Label({this.depends = true});

  final bool depends;

  String _label(BuildContext context) => depends
      ? 'v${context.dependOnInheritedWidgetOfExactType<_Value>()!.value}'
      : '-';

  @override
  RenderObject createRenderObject(BuildContext context) =>
      TestLeaf(_label(context));

  @override
  void updateRenderObject(BuildContext context, TestLeaf renderObject) {
    renderObject.label = _label(context);
  }
}

/// Depends on the [_Value] above it in initState.
final class _ReadsInInitState extends StatefulWidget {
  const _ReadsInInitState();

  @override
  State<_ReadsInInitState> createState() => _ReadsInInitStateState();
}

final class _ReadsInInitStateState extends State<_ReadsInInitState> {
  @override
  void initState() {
    super.initState();
    context.dependOnInheritedWidgetOfExactType<_Value>();
  }

  @override
  Widget build(BuildContext context) => const Leaf('early');
}
