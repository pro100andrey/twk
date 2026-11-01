import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

// An element keeps the inherited elements it depends on from build to
// build: a build that registers the same ones in the same order changes
// nothing, any other build leaves it depending on exactly the ones it
// registered, in whatever order.

void main() {
  group('the dependencies an element keeps across builds', () {
    test('stay when a build registers them in the same order', () {
      final r = _Rig(plan: ['a', 'b', 'c']);
      expect(r.depends(), {'a', 'b', 'c'});
      r
        ..rebuild()
        ..rebuild();
      expect(r.depends(), {'a', 'b', 'c'});
    });

    test('stay when a build registers them in another order', () {
      final r = _Rig(plan: ['a', 'b', 'c']);
      expect(r.depends(), {'a', 'b', 'c'});
      r
        ..plan = ['c', 'a', 'b']
        ..rebuild();
      expect(r.depends(), {'a', 'b', 'c'});
      r
        ..plan = ['b', 'c', 'a']
        ..rebuild()
        ..plan = ['a']
        ..rebuild();
      expect(r.depends(), {'a'});
    });

    test('lose the ones a build does not register, wherever they were', () {
      final r = _Rig(plan: ['a', 'b', 'c'])
        ..depends()
        ..plan = ['a', 'c']
        ..rebuild();
      expect(r.depends(), {'a', 'c'});
      r
        ..plan = ['c']
        ..rebuild();
      expect(r.depends(), {'c'});
      r
        ..plan = []
        ..rebuild();
      expect(r.depends(), isEmpty);
    });

    test('gain the ones a build registers, wherever it puts them', () {
      final r = _Rig(plan: ['b']);
      expect(r.depends(), {'b'});
      r
        ..plan = ['b', 'c']
        ..rebuild();
      expect(r.depends(), {'b', 'c'});
      r
        ..plan = ['a', 'b', 'c']
        ..rebuild();
      expect(r.depends(), {'a', 'b', 'c'});
      r
        ..plan = ['c', 'a']
        ..rebuild();
      expect(r.depends(), {'a', 'c'});
      r
        ..plan = ['b', 'c', 'a']
        ..rebuild();
      expect(r.depends(), {'a', 'b', 'c'});
    });

    test('are the same whatever a build registers twice', () {
      final r = _Rig(plan: ['a', 'a', 'b', 'a']);
      expect(r.depends(), {'a', 'b'});
      r
        ..plan = ['b', 'b']
        ..rebuild();
      expect(r.depends(), {'b'});
    });

    test('are told once of a change, in a rebuild of their own', () {
      final r = _Rig(plan: ['a', 'b'])
        ..depends()
        ..plan = ['b', 'a', 'b']
        ..rebuild()
        ..log.clear()
        ..pumpValue('a');
      expect(r.log, ['a didChangeDependencies', 'a build']);
    });

    test('of a State and of its build are kept apart: one that either '
        'registers stays', () {
      final r = _Rig(plan: ['a'], statePlan: ['a', 'b']);
      expect(r.depends(), {'a', 'b'});
      // the build drops a: the state still depends on it
      r
        ..plan = []
        ..rebuild();
      expect(r.depends(), {'a', 'b'});
      // the build takes c; didChangeDependencies is not called again
      r
        ..plan = ['c']
        ..rebuild();
      expect(r.depends(), {'a', 'b', 'c'});
      // the state drops b and a on its next call, the build has c
      r
        ..statePlan = []
        ..pumpValue('a');
      expect(r.depends(), {'c'});
    });

    test('of a State are kept by a build that registers the same', () {
      final r = _Rig(plan: ['b'], statePlan: ['b']);
      expect(r.depends(), {'b'});
      r
        ..plan = []
        ..rebuild();
      expect(r.depends(), {'b'});
      r
        ..statePlan = []
        ..pumpValue('b');
      expect(r.depends(), isEmpty);
    });

    test('of a State are kept when its own call stops asking for what the '
        'build still does', () {
      final r = _Rig(plan: ['b'], statePlan: ['b'])
        ..statePlan = []
        ..pumpValue('b');
      expect(r.depends(), {'b'});
    });

    test('of a State are dropped when the element leaves the tree', () {
      final log = <String>[];
      final probe = Probe(
        'p',
        log,
        onDidChangeDependencies: (state) =>
            state.context.dependOnInheritedWidgetOfExactType<_A>(),
      );
      final told = <Element>[];
      final tree = Tree()..show(_A(1, told: told, child: probe));
      tree.owner.buildScope();
      // the probe is out of the tree, not yet unmounted
      tree
        ..show(_A(1, told: told, child: const Leaf('x')))
        ..owner.buildScope()
        ..show(_A(2, told: told, child: const Leaf('x')))
        ..owner.buildScope();
      expect(told, isEmpty);
    });

    test('are dropped when the element is deactivated, and come back '
        'with the builds of the place it is activated in', () {
      final key = GlobalKey<ProbeState>();
      final log = <String>[];
      var plan = ['a', 'b'];
      final probe = Probe(
        'p',
        log,
        key: key,
        builder: (state) {
          for (final name in plan) {
            _depend(state.context, name);
          }
          return const Leaf('p');
        },
      );
      Widget place(int a1, int b1, int a2, int b2, {required bool moved}) =>
          Multi([
            _A(
              a1,
              child: _B(b1, child: Single(child: moved ? null : probe)),
            ),
            _A(
              a2,
              child: _B(b2, child: Single(child: moved ? probe : null)),
            ),
          ]);
      final told = ['p didChangeDependencies', 'p build'];
      final tree = Tree()..pump(place(1, 1, 1, 1, moved: false));
      log.clear();
      tree.pump(place(2, 1, 1, 1, moved: false));
      expect(log, told);
      log.clear();
      tree.pump(place(2, 1, 1, 1, moved: true));
      expect(log, ['p deactivate', 'p activate', ...told]);
      log.clear();
      // the old place's inherited widgets no longer tell it
      tree.pump(place(3, 3, 1, 1, moved: true));
      expect(log, isEmpty);
      // the new place's do, each of them
      tree.pump(place(3, 3, 2, 1, moved: true));
      expect(log, told);
      log.clear();
      tree.pump(place(3, 3, 2, 2, moved: true));
      expect(log, told);
      // a build of the new place that registers one drops the other
      plan = ['b'];
      tree.stateOf<ProbeState>().change(() {});
      tree.frame();
      log.clear();
      tree.pump(place(3, 3, 3, 2, moved: true));
      expect(log, isEmpty);
      tree.pump(place(3, 3, 3, 3, moved: true));
      expect(log, told);
    });
  });
}

void _depend(BuildContext context, String name) {
  switch (name) {
    case 'a':
      context.dependOnInheritedWidgetOfExactType<_A>();
    case 'b':
      context.dependOnInheritedWidgetOfExactType<_B>();
    case 'c':
      context.dependOnInheritedWidgetOfExactType<_C>();
  }
}

/// A tree of three inherited widgets over a probe that registers the ones
/// of [plan] in its builds and the ones of [statePlan] in its
/// didChangeDependencies.
final class _Rig {
  _Rig({this.plan = const [], this.statePlan = const []}) {
    tree.pump(_values());
  }

  final tree = Tree();
  final log = <String>[];
  List<String> plan;
  List<String> statePlan;
  final _counts = <String, int>{'a': 0, 'b': 0, 'c': 0};

  late final Widget probe = Probe(
    'a',
    log,
    builder: (state) {
      for (final name in plan) {
        _depend(state.context, name);
      }
      return const Leaf('a');
    },
    onDidChangeDependencies: (state) {
      for (final name in statePlan) {
        _depend(state.context, name);
      }
    },
  );

  Widget _values() => _A(
    _counts['a']!,
    child: _B(
      _counts['b']!,
      child: _C(_counts['c']!, child: probe),
    ),
  );

  /// Builds the probe again.
  void rebuild() {
    tree.stateOf<ProbeState>().change(() {});
    tree.frame();
  }

  /// Changes the value of the inherited widget [name].
  void pumpValue(String name) {
    _counts[name] = _counts[name]! + 1;
    tree.pump(_values());
  }

  /// The names of the inherited widgets whose change the probe is told of.
  /// Changes each in turn.
  Set<String> depends() {
    // the first call registers: build and didChangeDependencies
    final found = <String>{};
    for (final name in ['a', 'b', 'c']) {
      log.clear();
      pumpValue(name);
      if (log.contains('a didChangeDependencies')) {
        found.add(name);
      }
    }
    log.clear();
    return found;
  }
}

final class _A extends InheritedWidget {
  const _A(this.value, {required super.child, this.told});

  final int value;

  /// Gets each dependent its element tells of a change.
  final List<Element>? told;

  @override
  InheritedElement createElement() => _AElement(this);

  @override
  bool updateShouldNotify(_A oldWidget) => value != oldWidget.value;
}

final class _B extends InheritedWidget {
  const _B(this.value, {required super.child});

  final int value;

  @override
  bool updateShouldNotify(_B oldWidget) => value != oldWidget.value;
}

final class _C extends InheritedWidget {
  const _C(this.value, {required super.child});

  final int value;

  @override
  bool updateShouldNotify(_C oldWidget) => value != oldWidget.value;
}

final class _AElement extends InheritedElement {
  _AElement(_A super.widget);

  @override
  void notifyDependent(_A oldWidget, Element dependent) {
    (widget as _A).told?.add(dependent);
    super.notifyDependent(oldWidget, dependent);
  }
}
