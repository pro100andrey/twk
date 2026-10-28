import 'package:test/test.dart';
import 'package:twk/twk.dart';

import 'harness.dart';

void main() {
  group('a notification', () {
    test('bubbles up from the context to each listener above it, the '
        'nearest first, through elements of every kind', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(
          _listener<_Ping>(
            'outer',
            log,
            child: Multi([
              Wrapper(_listener<_Ping>('inner', log, child: const Leaf('a'))),
            ]),
          ),
        );
      const _Ping().dispatch(tree.elementOf<Leaf>());
      expect(log, ['inner _Ping', 'outer _Ping']);
    });

    test('starts at the parent of the context', () {
      final log = <String>[];
      final inner = _listener<_Ping>('inner', log);
      final tree = Tree()..pump(_listener<_Ping>('outer', log, child: inner));
      const _Ping().dispatch(
        tree.elements.singleWhere((e) => identical(e.widget, inner)),
      );
      expect(log, ['outer _Ping']);
    });

    test('stops at the listener that returns true', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(
          _listener<_Ping>(
            'outer',
            log,
            child: _listener<_Ping>('inner', log, stop: true),
          ),
        );
      const _Ping().dispatch(tree.elementOf<Leaf>());
      expect(log, ['inner _Ping']);
    });

    test('goes past the listeners of other types, which neither hear nor '
        'stop it, to those of its type and its supertypes', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(
          _listener<Notification>(
            'any',
            log,
            child: _listener<_Ping>(
              'ping',
              log,
              child: _listener<_Pong>('pong', log, stop: true),
            ),
          ),
        );
      final context = tree.elementOf<Leaf>();
      const _Ping().dispatch(context);
      const _LoudPing().dispatch(context);
      const _Pong().dispatch(context);
      expect(log, [
        'ping _Ping',
        'any _Ping',
        'ping _LoudPing',
        'any _LoudPing',
        'pong _Pong',
      ]);
    });

    test('goes past a listener without a callback', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(
          _listener<_Ping>(
            'outer',
            log,
            child: const NotificationListener<_Ping>(child: Leaf('a')),
          ),
        );
      const _Ping().dispatch(tree.elementOf<Leaf>());
      expect(log, ['outer _Ping']);
    });

    test('reaches the callback of the widget that replaced a listener', () {
      final log = <String>[];
      final tree = Tree()..pump(_listener<_Ping>('old', log));
      final context = tree.elementOf<Leaf>();
      tree.pump(_listener<_Ping>('new', log));
      expect(tree.elementOf<Leaf>(), same(context));
      const _Ping().dispatch(context);
      expect(log, ['new _Ping']);
    });

    test('visits each ancestor, the nearest first, up to the listener that '
        'stops it', () {
      final log = <String>[];
      final tree = Tree()
        ..pump(
          Wrapper(
            _listener<_Ping>(
              'outer',
              log,
              stop: true,
              child: Wrapper(_listener<_Ping>('inner', log)),
            ),
          ),
        );
      final notification = _Tracer()..dispatch(tree.elementOf<Leaf>());
      expect(notification.visited, [
        NotificationListener<_Ping>,
        Wrapper,
        NotificationListener<_Ping>,
      ]);
      expect(log, ['inner _Tracer', 'outer _Tracer']);
    });

    test('is described by its type', () {
      expect('${const _LoudPing()}', '_LoudPing');
    });
  });
}

/// A listener for the [T]s dispatched below it that logs each one into
/// [log], prefixed with [name], and returns [stop].
NotificationListener<T> _listener<T extends Notification>(
  String name,
  List<String> log, {
  bool stop = false,
  Widget child = const Leaf('leaf'),
}) => NotificationListener<T>(
  onNotification: (notification) {
    log.add('$name $notification');
    return stop;
  },
  child: child,
);

class _Ping extends Notification {
  const _Ping();
}

final class _LoudPing extends _Ping {
  const _LoudPing();
}

final class _Pong extends Notification {
  const _Pong();
}

/// A ping that records the types of the widgets of the ancestors it
/// visits.
final class _Tracer extends _Ping {
  final visited = <Type>[];

  @override
  bool visitAncestor(Element element) {
    visited.add(element.widget.runtimeType);
    return super.visitAncestor(element);
  }
}
