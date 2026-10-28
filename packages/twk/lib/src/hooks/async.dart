/// The hooks of asynchronous results: [useStream] and [useFuture], the
/// latest snapshot of a stream or a future, as `StreamBuilder` and
/// `FutureBuilder` build from.
///
/// @docImport 'primitives.dart';
library;

import 'dart:async';

import '../../twk.dart';

import 'hook.dart';

// Examples can assume:
// late Stream<String> logLines;
// Future<String> loadConfig() async => '';

/// The latest snapshot of [stream], from [initialData] on: waiting once
/// the stream is listened to, active with each event it delivers, done
/// once it closes, and none while there is no stream; each event rebuilds
/// the element. A snapshot keeps the latest data or error until the next.
///
/// The stream is listened to from the first build that gives it on, the
/// stream of a later build instead once it is not the same, and is
/// cancelled when the element is unmounted. The snapshot of a stream left
/// for another is the last one's, not connected, with [preserveState], or
/// the first one, from [initialData], without.
///
/// The last line of a log as it arrives:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final last = useStream(logLines, initialData: '');
///     return Text(last.data ?? '');
///   },
/// )
/// ```
AsyncSnapshot<T> useStream<T>(
  Stream<T>? stream, {
  T? initialData,
  bool preserveState = true,
}) => use(_StreamHook(stream, initialData, preserveState: preserveState));

final class _StreamHook<T> extends Hook<AsyncSnapshot<T>> {
  const _StreamHook(
    this.stream,
    this.initialData, {
    required this.preserveState,
  });

  final Stream<T>? stream;
  final T? initialData;
  final bool preserveState;

  @override
  String get debugLabel => 'useStream<$T>';

  @override
  _StreamHookState<T> createState() => _StreamHookState<T>();
}

final class _StreamHookState<T>
    extends HookState<AsyncSnapshot<T>, _StreamHook<T>> {
  StreamSubscription<T>? _subscription;
  late AsyncSnapshot<T> _snapshot;

  @override
  void initHook() {
    super.initHook();
    _snapshot = _initial(hook.initialData);
    _subscribe();
  }

  @override
  void didUpdateHook(_StreamHook<T> oldHook) {
    super.didUpdateHook(oldHook);
    if (oldHook.stream == hook.stream) {
      return;
    }
    if (_subscription != null) {
      _unsubscribe();
      _snapshot = hook.preserveState
          ? _snapshot.inState(ConnectionState.none)
          : _initial(hook.initialData);
    }
    _subscribe();
  }

  @override
  AsyncSnapshot<T> build(BuildContext context) => _snapshot;

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(hook.debugLabel, _snapshot);
  }

  void _subscribe() {
    final stream = hook.stream;
    if (stream == null) {
      return;
    }
    _subscription = stream.listen(
      (data) => setState(
        () => _snapshot = AsyncSnapshot<T>.withData(
          ConnectionState.active,
          data,
        ),
      ),
      onError: (Object error, StackTrace stackTrace) => setState(
        () => _snapshot = AsyncSnapshot<T>.withError(
          ConnectionState.active,
          error,
          stackTrace,
        ),
      ),
      onDone: () =>
          setState(() => _snapshot = _snapshot.inState(ConnectionState.done)),
    );
    _snapshot = _snapshot.inState(ConnectionState.waiting);
  }

  void _unsubscribe() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}

/// The latest snapshot of [future], from [initialData] on: waiting while
/// the future runs, done with its value or error once it completes, which
/// rebuilds the element, and none while there is no future. A snapshot
/// keeps the latest data or error until the next.
///
/// The future is waited on from the first build that gives it on, the
/// future of a later build instead once it is not the same; the result of
/// a future left for another, or of one the element was unmounted with,
/// is ignored. The snapshot of a future left for another is the last
/// one's, not connected, with [preserveState], or the first one, from
/// [initialData], without.
///
/// A config loaded once, its future kept by [useMemoized] so that a build
/// does not start another:
///
/// ```dart
/// HookBuilder(
///   builder: (context) {
///     final config = useFuture(useMemoized(loadConfig));
///     return Text(config.hasData ? config.data! : 'Loading…');
///   },
/// )
/// ```
AsyncSnapshot<T> useFuture<T>(
  Future<T>? future, {
  T? initialData,
  bool preserveState = true,
}) => use(_FutureHook(future, initialData, preserveState: preserveState));

final class _FutureHook<T> extends Hook<AsyncSnapshot<T>> {
  const _FutureHook(
    this.future,
    this.initialData, {
    required this.preserveState,
  });

  final Future<T>? future;
  final T? initialData;
  final bool preserveState;

  @override
  String get debugLabel => 'useFuture<$T>';

  @override
  _FutureHookState<T> createState() => _FutureHookState<T>();
}

final class _FutureHookState<T>
    extends HookState<AsyncSnapshot<T>, _FutureHook<T>> {
  // the token of the future waited on, which its callbacks check; null
  // without one and once disposed
  Object? _waitingOn;
  late AsyncSnapshot<T> _snapshot;

  @override
  void initHook() {
    super.initHook();
    _snapshot = _initial(hook.initialData);
    _subscribe();
  }

  @override
  void didUpdateHook(_FutureHook<T> oldHook) {
    super.didUpdateHook(oldHook);
    if (oldHook.future == hook.future) {
      return;
    }
    if (_waitingOn != null) {
      _waitingOn = null;
      _snapshot = hook.preserveState
          ? _snapshot.inState(ConnectionState.none)
          : _initial(hook.initialData);
    }
    _subscribe();
  }

  @override
  AsyncSnapshot<T> build(BuildContext context) => _snapshot;

  @override
  void dispose() {
    _waitingOn = null;
    super.dispose();
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(hook.debugLabel, _snapshot);
  }

  void _subscribe() {
    final future = hook.future;
    if (future == null) {
      return;
    }
    final token = Object();
    _waitingOn = token;
    unawaited(
      future.then<void>(
        (data) {
          if (_waitingOn == token) {
            setState(
              () => _snapshot = AsyncSnapshot<T>.withData(
                ConnectionState.done,
                data,
              ),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (_waitingOn == token) {
            setState(
              () => _snapshot = AsyncSnapshot<T>.withError(
                ConnectionState.done,
                error,
                stackTrace,
              ),
            );
          }
        },
      ),
    );
    _snapshot = _snapshot.inState(ConnectionState.waiting);
  }
}

AsyncSnapshot<T> _initial<T>(T? initialData) => initialData == null
    ? AsyncSnapshot<T>.nothing()
    : AsyncSnapshot<T>.withData(ConnectionState.none, initialData);
