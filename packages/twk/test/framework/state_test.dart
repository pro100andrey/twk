import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  group('a State', () {
    test('is initialized, told of its dependencies, then built', () {
      final log = <String>[];
      Tree().pump(Probe('a', log));
      expect(log, ['a initState', 'a didChangeDependencies', 'a build']);
    });

    test('has its widget, context and mounted from initState on', () {
      final seen = <Object?>[];
      final peek = _Peek(seen: seen);
      final tree = Tree()..pump(peek);
      expect(seen, [true, same(peek), same(tree.elementOf<_Peek>())]);
    });

    test('is given a new widget of its type in didUpdateWidget, then built, '
        'and stays', () {
      final log = <String>[];
      final tree = Tree()..pump(Probe('a', log, tag: 1));
      final state = tree.stateOf<ProbeState>();
      log.clear();
      tree.pump(Probe('a', log, tag: 2));
      expect(log, ['a didUpdateWidget 1 to 2', 'a build']);
      expect(tree.stateOf<ProbeState>(), same(state));
      expect(state.widget.tag, 2);
    });

    test('is replaced, with its element, by a widget of another type', () {
      final log = <String>[];
      final tree = Tree()..pump(Probe('a', log));
      final state = tree.stateOf<ProbeState>();
      tree
        ..pump(const Leaf('x'))
        ..pump(Probe('b', log));
      expect(tree.stateOf<ProbeState>(), isNot(same(state)));
      expect(log, [
        'a initState',
        'a didChangeDependencies',
        'a build',
        'a deactivate',
        'a dispose',
        'b initState',
        'b didChangeDependencies',
        'b build',
      ]);
    });

    test('is deactivated when its element is removed, parents first, and '
        'disposed when the tree is finalized, children first', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(Probe('outer', log, child: Probe('inner', log)));
      final outer = tree.probes.first;
      log.clear();
      tree
        ..show(const Leaf('x'))
        ..owner.buildScope();
      expect(log, ['outer deactivate', 'inner deactivate']);
      expect(outer.mounted, isTrue);
      tree.owner.finalizeTree();
      expect(log.skip(2), ['inner dispose', 'outer dispose']);
      expect(outer.mounted, isFalse);
    });

    test('is told of changed dependencies before its next build', () {
      final log = <String>[];
      final tree = Tree()..pump(Probe('a', log));
      log.clear();
      tree.elementOf<Probe>().didChangeDependencies();
      expect(log, isEmpty);
      tree.frame();
      expect(log, ['a didChangeDependencies', 'a build']);
    });
  });

  group('setState', () {
    test('runs its callback and rebuilds the element in the next build '
        'scope, once for any number of calls', () {
      final log = <String>[];
      final tree = Tree()..pump(Probe('a', log));
      final state = tree.stateOf<ProbeState>();
      final scheduled = tree.scheduled;
      log.clear();
      state
        ..change(() => state.count++)
        ..change(() => state.count++);
      expect(state.count, 2);
      expect(log, isEmpty);
      expect(tree.scheduled, scheduled + 1);
      tree.frame();
      expect(log, ['a build']);
      tree.frame();
      expect(log, ['a build']);
    });

    test('after dispose is an error, as is the context', () {
      final log = <String>[];
      final tree = Tree()..pump(Probe('a', log));
      final state = tree.stateOf<ProbeState>();
      tree.pump(const Leaf('x'));
      expect(() => state.change(() {}), throwsA(isA<AssertionError>()));
      expect(() => state.context, throwsA(isA<AssertionError>()));
    });
  });

  group('a StatelessWidget', () {
    test('is built again with each new widget, not with the same one', () {
      final log = <String>[];
      final child = _Counted(log);
      final tree = Tree()..pump(Probe('p', log, child: child));
      final state = tree.stateOf<ProbeState>();
      log.clear();
      state.change(() {});
      tree.frame();
      expect(log, ['p build']);
      log.clear();
      tree.pump(Probe('p', log, child: _Counted(log)));
      expect(log, ['p didUpdateWidget 0 to 0', 'p build', 'counted build']);
    });
  });
}

/// Records, in its initState, what the state can see.
final class _Peek extends StatefulWidget {
  const _Peek({this.seen});

  final List<Object?>? seen;

  @override
  State<_Peek> createState() => _PeekState();
}

final class _PeekState extends State<_Peek> {
  @override
  void initState() {
    super.initState();
    widget.seen?.addAll([mounted, widget, context]);
  }

  @override
  Widget build(BuildContext context) => const Leaf('peek');
}

final class _Counted extends StatelessWidget {
  const _Counted(this.log);

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    log.add('counted build');
    return const Leaf('counted');
  }
}
