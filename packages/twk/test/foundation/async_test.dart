import 'dart:async';
import 'dart:collection';

import 'package:test/test.dart';
import 'package:twk/twk.dart';

void main() {
  group('an AsyncSnapshot', () {
    test('with nothing has neither data nor an error, and requires data in '
        'vain', () {
      const snapshot = AsyncSnapshot<int>.nothing();
      expect(snapshot.connectionState, ConnectionState.none);
      expect(snapshot.hasData, isFalse);
      expect(snapshot.hasError, isFalse);
      expect(() => snapshot.requireData, throwsStateError);
      expect(
        const AsyncSnapshot<int>.waiting(),
        const AsyncSnapshot<int>.nothing().inState(ConnectionState.waiting),
      );
    });

    test('with data has it, also in another state', () {
      const snapshot = AsyncSnapshot.withData(ConnectionState.active, 1);
      expect(snapshot.hasData, isTrue);
      expect(snapshot.hasError, isFalse);
      expect(snapshot.requireData, 1);
      expect(
        snapshot.inState(ConnectionState.done),
        const AsyncSnapshot.withData(ConnectionState.done, 1),
      );
      expect(
        snapshot,
        isNot(const AsyncSnapshot.withData(ConnectionState.active, 2)),
      );
    });

    test('with an error throws it with its stack trace when data is '
        'required', () {
      final stack = StackTrace.current;
      final snapshot = AsyncSnapshot<int>.withError(
        ConnectionState.done,
        'oops',
        stack,
      );
      expect(snapshot.hasData, isFalse);
      expect(snapshot.hasError, isTrue);
      expect(snapshot.stackTrace, stack);
      expect(
        snapshot,
        isNot(const AsyncSnapshot<int>.withError(ConnectionState.done, 'oops')),
      );
      Object? thrown;
      StackTrace? thrownAt;
      try {
        snapshot.requireData;
      } on Object catch (error, stackTrace) {
        thrown = error;
        thrownAt = stackTrace;
      }
      expect(thrown, 'oops');
      expect(thrownAt, stack);
    });

    test('equal to another hashes alike, so a set holds one of them', () {
      final snapshots = {
        const AsyncSnapshot.withData(ConnectionState.active, 1),
        const AsyncSnapshot<int>.nothing().inState(ConnectionState.waiting),
        const AsyncSnapshot.withData(ConnectionState.done, 1),
        const AsyncSnapshot.withData(
          ConnectionState.done,
          1,
        ).inState(ConnectionState.active),
        const AsyncSnapshot<int>.waiting(),
      };
      expect(snapshots, hasLength(3));
    });

    test('names its type, its state, its data and its error', () {
      expect(
        '${const AsyncSnapshot.withData(ConnectionState.active, 1)}',
        'AsyncSnapshot<int>(active, 1, null)',
      );
      expect(
        '${const AsyncSnapshot<int>.withError(ConnectionState.done, 'oops')}',
        'AsyncSnapshot<int>(done, null, oops)',
      );
    });
  });

  group('a FutureBuilder', () {
    test('without a future shows its initial data, not connected', () {
      final log = <AsyncSnapshot<int>>[];
      _Tree().pump(_futureBuilder(null, log, initialData: 1));
      expect(log, [const AsyncSnapshot.withData(ConnectionState.none, 1)]);
    });

    test('waits on its future, then shows its value in the next frame, and '
        'does not wait again on the same future', () {
      _queued((flush) {
        final log = <AsyncSnapshot<int>>[];
        final completer = Completer<int>();
        final tree = _Tree()
          ..pump(_futureBuilder(completer.future, log, initialData: 0));
        expect(log, [const AsyncSnapshot.withData(ConnectionState.waiting, 0)]);
        log.clear();
        completer.complete(1);
        flush();
        expect(log, isEmpty);
        tree.frame();
        expect(log, [const AsyncSnapshot.withData(ConnectionState.done, 1)]);
        log.clear();
        tree.pump(_futureBuilder(completer.future, log));
        expect(log, [const AsyncSnapshot.withData(ConnectionState.done, 1)]);
      });
    });

    test('shows the error of its future with its stack trace', () {
      _queued((flush) {
        final log = <AsyncSnapshot<int>>[];
        final completer = Completer<int>();
        final tree = _Tree()..pump(_futureBuilder(completer.future, log));
        log.clear();
        final stack = StackTrace.current;
        completer.completeError('oops', stack);
        flush();
        tree.frame();
        expect(log, [
          AsyncSnapshot<int>.withError(ConnectionState.done, 'oops', stack),
        ]);
      });
    });

    test('ignores the result of a future a new widget replaced, and waits on '
        "the new widget's if it has one", () {
      _queued((flush) {
        final log = <AsyncSnapshot<int>>[];
        final a = Completer<int>();
        final b = Completer<int>();
        final c = Completer<int>();
        final tree = _Tree()
          ..pump(_futureBuilder(a.future, log))
          ..pump(_futureBuilder(b.future, log));
        expect(log, [
          const AsyncSnapshot<int>.waiting(),
          const AsyncSnapshot<int>.waiting(),
        ]);
        log.clear();
        a.complete(1);
        flush();
        tree.frame();
        expect(log, isEmpty);
        b.complete(2);
        flush();
        tree.frame();
        expect(log, [const AsyncSnapshot.withData(ConnectionState.done, 2)]);
        log.clear();
        tree
          ..pump(_futureBuilder(c.future, log))
          ..pump(_futureBuilder(null, log));
        c.complete(3);
        flush();
        tree.frame();
        expect(log, [
          const AsyncSnapshot.withData(ConnectionState.waiting, 2),
          const AsyncSnapshot.withData(ConnectionState.none, 2),
        ]);
      });
    });

    test('keeps the result of a replaced future, not connected without a '
        'future and waiting on a new one', () {
      _queued((flush) {
        final log = <AsyncSnapshot<int>>[];
        final a = Completer<int>();
        final b = Completer<int>();
        final tree = _Tree()..pump(_futureBuilder(a.future, log));
        a.complete(1);
        flush();
        tree.frame();
        log.clear();
        tree
          ..pump(_futureBuilder(null, log))
          ..pump(_futureBuilder(b.future, log));
        expect(log, [
          const AsyncSnapshot.withData(ConnectionState.none, 1),
          const AsyncSnapshot.withData(ConnectionState.waiting, 1),
        ]);
        log.clear();
        b.completeError('oops');
        flush();
        tree
          ..frame()
          ..pump(_futureBuilder(null, log));
        expect(log, [
          const AsyncSnapshot<int>.withError(ConnectionState.done, 'oops'),
          const AsyncSnapshot<int>.withError(ConnectionState.none, 'oops'),
        ]);
      });
    });

    test('ignores the result of its future once its element is unmounted', () {
      _queued((flush) {
        final log = <AsyncSnapshot<int>>[];
        final a = Completer<int>();
        final b = Completer<int>();
        final tree = _Tree()
          ..pump(_futureBuilder(a.future, log))
          ..pump(const _Leaf());
        a.complete(1);
        flush();
        tree
          ..pump(_futureBuilder(b.future, log))
          ..pump(const _Leaf());
        b.completeError('oops');
        flush();
        tree.frame();
        expect(log, [
          const AsyncSnapshot<int>.waiting(),
          const AsyncSnapshot<int>.waiting(),
        ]);
      });
    });
  });

  group('a StreamBuilder', () {
    test('without a stream shows its initial data, not connected', () {
      final log = <AsyncSnapshot<int>>[];
      _Tree().pump(_streamBuilder(null, log, initialData: 1));
      expect(log, [const AsyncSnapshot.withData(ConnectionState.none, 1)]);
    });

    test('waits on its stream, shows the latest event as active in the next '
        'frame, then done once it closes', () {
      _queued((flush) {
        final log = <AsyncSnapshot<int>>[];
        final controller = StreamController<int>();
        final tree = _Tree()
          ..pump(_streamBuilder(controller.stream, log, initialData: 0));
        expect(log, [const AsyncSnapshot.withData(ConnectionState.waiting, 0)]);
        log.clear();
        controller
          ..add(1)
          ..add(2);
        flush();
        expect(log, isEmpty);
        tree.frame();
        expect(log, [const AsyncSnapshot.withData(ConnectionState.active, 2)]);
        log.clear();
        final stack = StackTrace.current;
        controller.addError('oops', stack);
        flush();
        tree.frame();
        unawaited(controller.close());
        flush();
        tree.frame();
        expect(log, [
          AsyncSnapshot<int>.withError(ConnectionState.active, 'oops', stack),
          AsyncSnapshot<int>.withError(ConnectionState.done, 'oops', stack),
        ]);
      });
    });

    test('listens to the stream of a new widget instead of the old one, '
        'once for the same stream', () {
      _queued((flush) {
        final log = <AsyncSnapshot<int>>[];
        final a = StreamController<int>();
        final b = StreamController<int>();
        final tree = _Tree()..pump(_streamBuilder(a.stream, log));
        a.add(1);
        flush();
        tree.frame();
        log.clear();
        tree
          ..pump(_streamBuilder(a.stream, log))
          ..pump(_streamBuilder(b.stream, log));
        expect(a.hasListener, isFalse);
        expect(b.hasListener, isTrue);
        expect(log, [
          const AsyncSnapshot.withData(ConnectionState.active, 1),
          const AsyncSnapshot.withData(ConnectionState.waiting, 1),
        ]);
        log.clear();
        b.add(2);
        flush();
        tree
          ..frame()
          ..pump(_streamBuilder(null, log));
        expect(log, [
          const AsyncSnapshot.withData(ConnectionState.active, 2),
          const AsyncSnapshot.withData(ConnectionState.none, 2),
        ]);
        unawaited(a.close());
        unawaited(b.close());
      });
    });

    test('cancels its subscription when its element is unmounted, also with '
        'events on the way', () {
      _queued((flush) {
        final log = <AsyncSnapshot<int>>[];
        final controller = StreamController<int>();
        final tree = _Tree()..pump(_streamBuilder(controller.stream, log));
        controller.add(1);
        tree.pump(const _Leaf());
        expect(controller.hasListener, isFalse);
        flush();
        tree.frame();
        expect(log, [const AsyncSnapshot<int>.waiting()]);
        unawaited(controller.close());
      });
    });
  });

  group('a StreamBuilderBase', () {
    test('summarises what its streams deliver, through each step', () {
      _queued((flush) {
        final log = <String>[];
        final a = StreamController<int>();
        final b = StreamController<int>();
        final tree = _Tree()..pump(_Summing(a.stream, log));
        a
          ..add(1)
          ..add(2)
          ..addError('oops');
        unawaited(a.close());
        flush();
        tree
          ..frame()
          ..pump(_Summing(b.stream, log));
        b.add(4);
        flush();
        tree.frame();
        expect(log, [
          'initial',
          'connected 0',
          'build 0',
          'data 0 + 1',
          'data 1 + 2',
          'error 3 oops',
          'done 3',
          'build 3',
          'disconnected 3',
          'connected 3',
          'build 3',
          'data 3 + 4',
          'build 7',
        ]);
        unawaited(b.close());
      });
    });
  });
}

FutureBuilder<int> _futureBuilder(
  Future<int>? future,
  List<AsyncSnapshot<int>> log, {
  int? initialData,
}) => FutureBuilder<int>(
  future: future,
  initialData: initialData,
  builder: (context, snapshot) {
    log.add(snapshot);
    return const _Leaf();
  },
);

StreamBuilder<int> _streamBuilder(
  Stream<int>? stream,
  List<AsyncSnapshot<int>> log, {
  int? initialData,
}) => StreamBuilder<int>(
  stream: stream,
  initialData: initialData,
  builder: (context, snapshot) {
    log.add(snapshot);
    return const _Leaf();
  },
);

/// Sums the events of [stream], logging each step of the summary.
final class _Summing extends StreamBuilderBase<int, int> {
  const _Summing(Stream<int> stream, this.log) : super(stream: stream);

  final List<String> log;

  int _logged(String step, int sum) {
    log.add(step);
    return sum;
  }

  @override
  int initial() => _logged('initial', 0);

  @override
  int afterConnected(int current) => _logged('connected $current', current);

  @override
  int afterData(int current, int data) =>
      _logged('data $current + $data', current + data);

  @override
  int afterError(int current, Object error, StackTrace stackTrace) =>
      _logged('error $current $error', current);

  @override
  int afterDone(int current) => _logged('done $current', current);

  @override
  int afterDisconnected(int current) =>
      _logged('disconnected $current', current);

  @override
  Widget build(BuildContext context, int currentSummary) {
    log.add('build $currentSummary');
    return const _Leaf();
  }
}

/// Runs [body] in a zone whose microtasks wait until [body] calls `flush`,
/// so that the futures and streams made in it deliver when the test says,
/// without waiting for anything.
void _queued(void Function(void Function() flush) body) {
  final queue = Queue<void Function()>();
  void flush() {
    while (queue.isNotEmpty) {
      queue.removeFirst()();
    }
  }

  runZoned(
    () => body(flush),
    zoneSpecification: ZoneSpecification(
      scheduleMicrotask: (self, parent, zone, fn) => queue.add(fn),
    ),
  );
}

/// A tree under one [BuildOwner], pumped the way a frame loop does.
final class _Tree {
  final owner = BuildOwner();
  RootElement? _root;

  /// Shows [widget] at the top of the tree and runs a frame.
  void pump(Widget widget) {
    _root = RootWidget(child: widget).attach(owner, _root);
    frame();
  }

  /// Rebuilds what is dirty, then unmounts what was removed.
  void frame() {
    owner
      ..buildScope()
      ..finalizeTree();
  }
}

final class _Leaf extends LeafRenderObjectWidget {
  const _Leaf();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLeaf();
}

final class _RenderLeaf extends RenderObject {
  @override
  void performLayout(BoxConstraints c) {
    width = c.minW;
    height = c.minH;
  }

  @override
  void paint(PaintContext ctx) {}
}
