// The hooks of asynchronous results: useStream and useFuture, each through
// mounting, its events, another stream or future kept or not, and
// unmounting.
import 'dart:async';

import 'package:test/test.dart';
import 'package:twk/hooks.dart';
import 'package:twk/twk.dart';
import 'package:twk_test/twk_test.dart';

void main() {
  group('useStream', () {
    testTwk('is waiting once it listens, active with each event, done once '
        'the stream closes, and cancels the stream when unmounted', (
      t,
    ) async {
      final snapshots = <AsyncSnapshot<int>>[];
      final controller = StreamController<int>();
      await t.pumpWidget(
        HookBuilder(
          builder: (context) {
            snapshots.add(useStream(controller.stream, initialData: 0));
            return const Text('x');
          },
        ),
        size: (10, 1),
      );
      controller.add(1);
      await t.pump();
      controller.addError('oops');
      await t.pump();
      await controller.close();
      await t.pump();
      expect(snapshots, [
        const AsyncSnapshot.withData(ConnectionState.waiting, 0),
        const AsyncSnapshot.withData(ConnectionState.active, 1),
        isA<AsyncSnapshot<int>>()
            .having((s) => s.connectionState, 'state', ConnectionState.active)
            .having((s) => s.error, 'error', 'oops'),
        isA<AsyncSnapshot<int>>()
            .having((s) => s.connectionState, 'state', ConnectionState.done)
            .having((s) => s.error, 'error', 'oops'),
      ]);
      final open = StreamController<int>();
      await t.pumpWidget(
        HookBuilder(
          builder: (context) {
            useStream(open.stream);
            return const Text('x');
          },
        ),
      );
      expect(open.hasListener, isTrue);
      await t.pumpWidget(const Text('gone'));
      expect(open.hasListener, isFalse);
      unawaited(open.close());
    });

    testTwk('goes over to the stream of a later build, the snapshot kept '
        'not connected, or from the initial data without preserveState', (
      t,
    ) async {
      final snapshots = <AsyncSnapshot<int>>[];
      Widget streaming(Stream<int>? stream, {bool preserveState = true}) =>
          HookBuilder(
            builder: (context) {
              snapshots.add(
                useStream(
                  stream,
                  initialData: 0,
                  preserveState: preserveState,
                ),
              );
              return const Text('x');
            },
          );
      final a = StreamController<int>();
      final b = StreamController<int>();
      final c = StreamController<int>();
      await t.pumpWidget(streaming(a.stream), size: (10, 1));
      a.add(1);
      await t.pump();
      snapshots.clear();
      await t.pumpWidget(streaming(b.stream));
      expect(a.hasListener, isFalse);
      expect(snapshots, [
        const AsyncSnapshot.withData(ConnectionState.waiting, 1),
      ]);
      snapshots.clear();
      // the same stream again listens on
      await t.pumpWidget(streaming(b.stream, preserveState: false));
      b.add(2);
      await t.pump();
      await t.pumpWidget(streaming(c.stream, preserveState: false));
      expect(snapshots, [
        const AsyncSnapshot.withData(ConnectionState.waiting, 1),
        const AsyncSnapshot.withData(ConnectionState.active, 2),
        const AsyncSnapshot.withData(ConnectionState.waiting, 0),
      ]);
      snapshots.clear();
      await t.pumpWidget(streaming(null));
      expect(c.hasListener, isFalse);
      expect(snapshots, [
        const AsyncSnapshot.withData(ConnectionState.none, 0),
      ]);
      unawaited(a.close());
      unawaited(b.close());
      unawaited(c.close());
    });
  });

  group('useFuture', () {
    testTwk('is waiting while the future runs and done with its value or its '
        'error', (t) async {
      final snapshots = <AsyncSnapshot<int>>[];
      Widget waiting(Future<int>? future) => HookBuilder(
        builder: (context) {
          snapshots.add(useFuture(future));
          return const Text('x');
        },
      );
      final value = Completer<int>();
      await t.pumpWidget(waiting(value.future), size: (10, 1));
      value.complete(1);
      await t.pump();
      expect(snapshots, [
        const AsyncSnapshot<int>.waiting(),
        const AsyncSnapshot.withData(ConnectionState.done, 1),
      ]);
      snapshots.clear();
      // a future's error goes to no handler in another error zone: this
      // future is the app's
      late Completer<int> error;
      await t.pumpWidget(
        HookBuilder(
          key: const Key('error'),
          builder: (context) {
            error = useMemoized(Completer<int>.new);
            snapshots.add(useFuture(error.future));
            return const Text('x');
          },
        ),
      );
      error.completeError('oops');
      await t.pump();
      expect(snapshots, [
        const AsyncSnapshot<int>.waiting(),
        isA<AsyncSnapshot<int>>()
            .having((s) => s.connectionState, 'state', ConnectionState.done)
            .having((s) => s.error, 'error', 'oops'),
      ]);
    });

    testTwk('goes over to the future of a later build, the snapshot kept not '
        'connected, or from the initial data without preserveState, and '
        'ignores the result of a future left for another or of one it was '
        'unmounted with', (t) async {
      final snapshots = <AsyncSnapshot<int>>[];
      Widget waiting(Future<int>? future, {bool preserveState = true}) =>
          HookBuilder(
            builder: (context) {
              snapshots.add(
                useFuture(
                  future,
                  initialData: 0,
                  preserveState: preserveState,
                ),
              );
              return const Text('x');
            },
          );
      final a = Completer<int>();
      final b = Completer<int>();
      final c = Completer<int>();
      await t.pumpWidget(waiting(a.future), size: (10, 1));
      a.complete(1);
      await t.pump();
      await t.pumpWidget(waiting(b.future, preserveState: false));
      await t.pumpWidget(waiting(null));
      b.complete(2);
      await t.pump();
      await t.pumpWidget(waiting(c.future));
      await t.pumpWidget(const Text('gone'));
      c.complete(3);
      await t.pump();
      expect(snapshots, [
        const AsyncSnapshot.withData(ConnectionState.waiting, 0),
        const AsyncSnapshot.withData(ConnectionState.done, 1),
        const AsyncSnapshot.withData(ConnectionState.waiting, 0),
        const AsyncSnapshot.withData(ConnectionState.none, 0),
        const AsyncSnapshot.withData(ConnectionState.waiting, 0),
      ]);
    });
  });
}
