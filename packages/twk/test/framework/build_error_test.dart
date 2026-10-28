import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  test('a build that throws is reported to onBuildError, and the element '
      'shows what it returns', () {
    final reports = <(Element, Object)>[];
    final tree = Tree(
      onBuildError: (element, error, stack) {
        reports.add((element, error));
        return const Leaf('error');
      },
    )..pump(const Multi([Leaf('a'), _Throws(), Leaf('c')]));
    final multi = tree.host.child! as TestMulti;
    expect([for (final c in multi.children) '$c'], ['a', 'error', 'c']);
    final [(element, error)] = reports;
    expect(element, same(tree.elementOf<_Throws>()));
    expect(error, isA<StateError>());
  });

  test('an element whose builds go on throwing the same error is reported '
      'once and shows the same widget; another error, or a build that '
      'succeeded in between, is reported again', () {
    final reports = <Object>[];
    final log = <String>[];
    final tree = Tree(
      onBuildError: (element, error, stack) {
        reports.add(error);
        return Leaf('error ${reports.length}');
      },
    );
    var message = 'boom';
    var ok = false;
    tree.pump(
      Probe(
        'a',
        log,
        builder: (s) => ok ? const Leaf('a') : throw StateError(message),
      ),
    );
    final state = tree.probes.single;
    expect(reports, hasLength(1));
    for (var i = 0; i < 3; i++) {
      state.change(() => state.count++);
      tree.frame();
    }
    expect(reports, hasLength(1));
    expect(tree.host.child.toString(), 'error 1');
    // another error
    message = 'bang';
    state.change(() => state.count++);
    tree.frame();
    expect(reports, hasLength(2));
    expect(tree.host.child.toString(), 'error 2');
    // built, then the first error again
    ok = true;
    state.change(() => state.count++);
    tree.frame();
    expect(tree.host.child.toString(), 'a');
    ok = false;
    message = 'boom';
    state.change(() => state.count++);
    tree.frame();
    expect(reports, hasLength(3));
  });

  test('without onBuildError, a build that throws reports to the zone, and '
      'the element shows an empty render object until it builds again', () {
    final errors = <Object>[];
    final guarded = _guardedInto(errors);
    final log = <String>[];
    final tree = Tree();
    guarded(
      () => tree.pump(
        Probe(
          'a',
          log,
          builder: (s) =>
              s.count == 1 ? throw StateError('boom') : const Leaf('a'),
        ),
      ),
    );
    final state = tree.probes.single;
    expect(tree.host.child.toString(), 'a');

    state.change(() => state.count++);
    guarded(tree.frame);
    expect(errors, [isA<StateError>()]);
    final empty = tree.host.child!..layout(const BoxConstraints(1, 9, 2, 9));
    expect(empty, isNot(isA<TestLeaf>()));
    expect((empty.width, empty.height), (1, 2));

    state.change(() => state.count++);
    guarded(tree.frame);
    expect(errors, hasLength(1));
    expect(tree.host.child.toString(), 'a');
  });

  test(
    'an element whose onBuildError threw builds again when marked dirty',
    () {
      final log = <String>[];
      final tree =
          Tree(
            onBuildError: (element, error, stack) =>
                Error.throwWithStackTrace(error, stack),
          )..pump(
            Probe(
              'a',
              log,
              builder: (s) =>
                  s.count == 1 ? throw StateError('boom') : const Leaf('a'),
            ),
          );
      final state = tree.probes.single;
      state.change(() => state.count++);
      expect(tree.frame, throwsStateError);
      state.change(() => state.count++);
      log.clear();
      tree.frame();
      expect(log, ['a build']);
      expect(tree.host.child.toString(), 'a');
    },
  );

  test('without onBuildError, the siblings after a widget whose build threw '
      'keep their order', () {
    final errors = <Object>[];
    final tree = Tree();
    _guardedInto(errors)(
      () => tree.pump(const Multi([Leaf('a'), _Throws(), Leaf('c')])),
    );
    expect(errors, [isA<StateError>()]);
    final children = (tree.host.child! as TestMulti).children;
    expect(children, hasLength(3));
    expect('${children.first} ${children.last}', 'a c');
  });
}

/// Runs a frame in a zone that adds its uncaught errors to [errors]. Only
/// frames run there: a failed expectation would be reported to it too.
void Function(void Function() frame) _guardedInto(List<Object> errors) =>
    (frame) => runZonedGuarded(frame, (error, stack) => errors.add(error));

final class _Throws extends StatelessWidget {
  const _Throws();

  @override
  Widget build(BuildContext context) => throw StateError('boom');
}
