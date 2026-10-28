// Unmounting what was removed from the tree (BuildOwner.finalizeTree) goes
// through every element, even when a state's dispose throws: the states
// after it are disposed too, and let go of their timers, listeners and
// controllers. The first error is thrown once all are unmounted, each
// later one going to the zone's error handler.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

/// A stateful widget whose state records its dispose in [log] as `name`,
/// then throws [throws] when it is given.
final class _Disposer extends StatefulWidget {
  const _Disposer(this.name, this.log, {this.throws, this.child});

  final String name;
  final List<String> log;
  final Error? throws;
  final Widget? child;

  @override
  State<_Disposer> createState() => _DisposerState();
}

final class _DisposerState extends State<_Disposer> {
  @override
  void dispose() {
    widget.log.add(widget.name);
    super.dispose();
    if (widget.throws case final Error error) {
      throw error;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child ?? Leaf(widget.name);
}

/// The error [body] throws, null if none.
Object? _thrown(void Function() body) {
  try {
    body();
  } on Object catch (error) {
    return error;
  }
  return null;
}

void main() {
  final boom = StateError('b');

  test('three states of one subtree removed, the middle one throwing in '
      'dispose: all three are disposed, and its error is thrown', () {
    final log = <String>[];
    final tree = Tree()
      ..pump(
        Multi([
          _Disposer('a', log),
          _Disposer('b', log, throws: boom),
          _Disposer('c', log),
        ]),
      );
    final states = tree.elements
        .whereType<StatefulElement>()
        .map((e) => e.state)
        .toList();
    tree.show(const Leaf('x'));
    expect(_thrown(tree.frame), same(boom));
    expect(log, ['a', 'b', 'c']);
    expect([for (final s in states) s.mounted], [false, false, false]);
    // nothing is left to unmount by the next frame
    log.clear();
    expect(_thrown(tree.frame), isNull);
    expect(log, isEmpty);
  });

  test('a state that throws in dispose under another: the one above is '
      'disposed too, after it', () {
    final log = <String>[];
    final tree = Tree()
      ..pump(
        _Disposer('outer', log, child: _Disposer('inner', log, throws: boom)),
      )
      ..show(const Leaf('x'));
    expect(_thrown(tree.frame), same(boom));
    expect(log, ['inner', 'outer']);
  });

  test('three subtrees removed in one frame, the middle one throwing in '
      'dispose: all three are disposed, and its error is thrown', () {
    final log = <String>[];
    final tree = Tree()
      ..pump(
        Multi([
          _Disposer('a', log),
          _Disposer('b', log, throws: boom),
          _Disposer('c', log),
        ]),
      )
      ..show(const Multi([Leaf('x'), Leaf('y'), Leaf('z')]));
    expect(_thrown(tree.frame), same(boom));
    expect(log..sort(), ['a', 'b', 'c']);
  });

  test('two states throwing in dispose: the first error is thrown once all '
      'are unmounted, the second goes to the zone after it, once', () async {
    final log = <String>[];
    final first = StateError('first');
    final second = StateError('second');
    final tree = Tree()
      ..pump(
        Multi([
          _Disposer('a', log, throws: first),
          _Disposer('b', log),
          _Disposer('c', log, throws: second),
        ]),
      )
      ..show(const Leaf('x'));
    final reported = <Object>[];
    Object? thrown;
    await runZonedGuarded(() async {
      thrown = _thrown(tree.frame);
      // what goes to the zone goes once the error was thrown
      expect(reported, isEmpty);
      await Future<void>.value();
    }, (error, _) => reported.add(error));
    expect(thrown, same(first));
    expect(log, ['a', 'b', 'c']);
    expect(reported, [same(second)]);
  });
}
