import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  test('onBuildScheduled is called once for the elements marked dirty '
      'before a build scope', () {
    final log = <String>[];
    final tree = Tree()..pump(Multi([Probe('a', log), Probe('b', log)]));
    final states = tree.probes;
    final scheduled = tree.scheduled;
    for (final s in states) {
      s.change(() {});
    }
    expect(tree.scheduled, scheduled + 1);
    tree.frame();
    states.first.change(() {});
    expect(tree.scheduled, scheduled + 2);
  });

  test('dirty elements are rebuilt parents first, whatever order they were '
      'marked in', () {
    final log = <String>[];
    final tree = Tree()..pump(Probe('outer', log, child: Probe('inner', log)));
    final [outer, inner] = tree.probes;
    log.clear();
    inner.change(() {});
    outer.change(() {});
    tree.frame();
    expect(log, ['outer build', 'inner build']);
  });

  test('a dirty child its parent rebuilt with a new widget is not rebuilt '
      'again', () {
    final log = <String>[];
    final tree = Tree()
      ..pump(Probe('outer', log, builder: (_) => Probe('inner', log)));
    final [outer, inner] = tree.probes;
    log.clear();
    inner.change(() {});
    outer.change(() {});
    tree.frame();
    expect(log, ['outer build', 'inner didUpdateWidget 0 to 0', 'inner build']);
  });

  test('an element removed before its turn is not rebuilt', () {
    final log = <String>[];
    final tree = Tree()
      ..pump(
        Probe(
          'outer',
          log,
          builder: (s) => s.count == 0 ? Probe('inner', log) : const Leaf('x'),
        ),
      );
    final [outer, inner] = tree.probes;
    log.clear();
    inner.change(() {});
    outer.change(() => outer.count++);
    tree.frame();
    expect(log, ['outer build', 'inner deactivate', 'inner dispose']);
  });

  test('an element marked dirty for the first time in a build scope, by the '
      'build of a deeper one, is rebuilt in it', () {
    final log = <String>[];
    final (tree, shallow, deep) = _shallowAndDeep(log);
    final scheduled = tree.scheduled;
    deep.change(() => deep.count++);
    tree.frame();
    expect(log, ['deep build', 'shallow build']);
    expect(tree.scheduled, scheduled + 1);
    expect(tree.elements.where((e) => e.dirty), isEmpty);

    log.clear();
    shallow.change(() {});
    tree.frame();
    expect(log, ['shallow build']);
  });

  test('an element marked dirty again after it was rebuilt in the same '
      'build scope fails an assert naming its path, and is rebuilt once '
      'more', () {
    final log = <String>[];
    final reports = <(Element, Object)>[];
    final (tree, shallow, deep) = _shallowAndDeep(
      log,
      onBuildError: (element, error, stack) {
        reports.add((element, error));
        return const Leaf('error');
      },
    );
    shallow.change(() {});
    deep.change(() => deep.count++);
    tree.frame();
    final [(element, error)] = reports;
    expect(element, same(deep.context));
    expect(
      error,
      isA<AssertionError>().having(
        (e) => e.message,
        'message',
        "RootWidget > Single > Multi > Probe-[<'shallow'>] was marked dirty "
            'again after it was rebuilt in the same build scope',
      ),
    );
    expect(log, ['shallow build', 'deep build', 'shallow build']);
    expect(tree.elements.where((e) => e.dirty), isEmpty);
  });

  test('a root given a new widget shows it from the next build scope on', () {
    final log = <String>[];
    final tree = Tree()..pump(Probe('a', log, tag: 1));
    final scheduled = tree.scheduled;
    log.clear();
    tree.show(Probe('a', log, tag: 2));
    expect(log, isEmpty);
    expect(tree.scheduled, scheduled + 1);
    tree.owner.buildScope();
    expect(log, ['a didUpdateWidget 1 to 2', 'a build']);
  });
}

/// A tree with two probes, the deep one deeper than the shallow one; once
/// its count is above 0, the deep one marks the shallow one dirty in each
/// of its builds. [log] is cleared.
(Tree, ProbeState shallow, ProbeState deep) _shallowAndDeep(
  List<String> log, {
  Widget Function(Element element, Object error, StackTrace stack)?
  onBuildError,
}) {
  late ProbeState shallow;
  final tree = Tree(onBuildError: onBuildError)
    ..pump(
      Multi([
        Probe('shallow', log, key: const Key('shallow')),
        Wrapper(
          Probe(
            'deep',
            log,
            builder: (s) {
              if (s.count > 0) {
                shallow.change(() {});
              }
              return const Leaf('deep');
            },
          ),
        ),
      ]),
    );
  final [first, deep] = tree.probes;
  shallow = first;
  log.clear();
  return (tree, shallow, deep);
}
