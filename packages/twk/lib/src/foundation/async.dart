/// Widgets that build from the latest result of a future or a stream:
/// [FutureBuilder], [StreamBuilder] and the [StreamBuilderBase] under it,
/// and the [AsyncSnapshot] they build from.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import '../framework/framework.dart';

// Examples can assume:
// late Future<String> answer;
// late Stream<int> ticks;

/// Where an asynchronous computation stands.
enum ConnectionState {
  /// Not connected to a computation, maybe with initial data.
  none,

  /// Connected to a computation, waiting for its first result.
  waiting,

  /// Connected to a stream that has delivered a result and may deliver more.
  active,

  /// Connected to a computation that has finished.
  done,
}

/// The latest result of an asynchronous computation: [data] or [error],
/// at most one of them, and where it stands.
///
/// A builder tells them apart with a pattern:
///
/// ```dart
/// Widget show(AsyncSnapshot<String> snapshot) => switch (snapshot) {
///   AsyncSnapshot(hasError: true) => Text('failed: ${snapshot.error}'),
///   AsyncSnapshot(hasData: true) => Text(snapshot.requireData),
///   _ => const Text('…'),
/// };
/// ```
@immutable
final class AsyncSnapshot<T> {
  const AsyncSnapshot._(
    this.connectionState,
    this.data,
    this.error,
    this.stackTrace,
  ) : assert(data == null || error == null, 'both data and error'),
      assert(stackTrace == null || error != null, 'a stack trace, no error');

  /// No computation, no result.
  const AsyncSnapshot.nothing()
    : this._(ConnectionState.none, null, null, null);

  /// Waiting for a computation, no result yet.
  const AsyncSnapshot.waiting()
    : this._(ConnectionState.waiting, null, null, null);

  /// [data] in [state].
  const AsyncSnapshot.withData(ConnectionState state, T data)
    : this._(state, data, null, null);

  /// [error], thrown at [stackTrace], in [state].
  const AsyncSnapshot.withError(
    ConnectionState state,
    Object error, [
    StackTrace stackTrace = StackTrace.empty,
  ]) : this._(state, null, error, stackTrace);

  /// Where the computation stands.
  final ConnectionState connectionState;

  /// The latest data; null with none, as with an error.
  final T? data;

  /// The latest error; null with none, as with data.
  final Object? error;

  /// Where [error] was thrown; null without an error.
  final StackTrace? stackTrace;

  /// Whether [data] is not null.
  bool get hasData => data != null;

  /// Whether [error] is not null.
  bool get hasError => error != null;

  /// [data]; throws [error] with its [stackTrace] instead, or a
  /// [StateError] when there is neither.
  T get requireData {
    if (hasData) {
      return data!;
    }
    if (hasError) {
      Error.throwWithStackTrace(error!, stackTrace!);
    }
    throw StateError('$this has neither data nor an error');
  }

  /// This result in [state].
  AsyncSnapshot<T> inState(ConnectionState state) =>
      AsyncSnapshot._(state, data, error, stackTrace);

  /// Whether [other] is a snapshot of the same type with an equal
  /// [connectionState], [data], [error] and [stackTrace].
  @override
  bool operator ==(Object other) =>
      other is AsyncSnapshot<T> &&
      other.connectionState == connectionState &&
      other.data == data &&
      other.error == error &&
      other.stackTrace == stackTrace;

  @override
  int get hashCode => Object.hash(connectionState, data, error, stackTrace);

  /// `AsyncSnapshot<T>(state, data, error)`.
  @override
  String toString() =>
      'AsyncSnapshot<$T>(${connectionState.name}, $data, $error)';
}

/// Builds a widget from [snapshot].
typedef AsyncWidgetBuilder<T> = Widget Function(
  BuildContext context,
  AsyncSnapshot<T> snapshot,
);

/// A widget that listens to [stream] while its element is in the tree, to
/// the stream of each new widget instead from its update on, and keeps a
/// summary of type [S] of what it delivered, built again in the next build
/// scope after each event.
///
/// The summary starts as [initial] and goes through [afterConnected] when a
/// stream is listened to, [afterData], [afterError] and [afterDone] as it
/// delivers, and [afterDisconnected] when it is replaced; the stream of a
/// widget is listened to once, the one of a disposed element cancelled.
///
/// A count of the events a stream delivered:
///
/// ```dart
/// final class EventCount extends StreamBuilderBase<Object?, int> {
///   const EventCount({required super.stream, super.key});
///
///   @override
///   int initial() => 0;
///
///   @override
///   int afterData(int current, Object? data) => current + 1;
///
///   @override
///   Widget build(BuildContext context, int currentSummary) =>
///       Text('$currentSummary events');
/// }
/// ```
///
/// See also:
///
///  * [StreamBuilder], whose summary is the latest [AsyncSnapshot].
abstract class StreamBuilderBase<T, S> extends StatefulWidget {
  /// For subclasses: listens to [stream].
  const StreamBuilderBase({required this.stream, super.key});

  /// What this widget listens to; null for nothing.
  final Stream<T>? stream;

  /// The summary before any stream.
  @protected
  S initial();

  /// The summary once a stream is listened to; [current] by default.
  @protected
  S afterConnected(S current) => current;

  /// The summary after the stream delivered [data].
  @protected
  S afterData(S current, T data);

  /// The summary after the stream delivered [error]; [current] by default.
  @protected
  S afterError(S current, Object error, StackTrace stackTrace) => current;

  /// The summary after the stream closed; [current] by default.
  @protected
  S afterDone(S current) => current;

  /// The summary once the stream is replaced; [current] by default.
  @protected
  S afterDisconnected(S current) => current;

  /// Describes this part of the interface from [currentSummary].
  @protected
  Widget build(BuildContext context, S currentSummary);

  @override
  State<StreamBuilderBase<T, S>> createState() =>
      _StreamBuilderBaseState<T, S>();
}

final class _StreamBuilderBaseState<T, S>
    extends State<StreamBuilderBase<T, S>> {
  StreamSubscription<T>? _subscription;
  late S _summary;

  @override
  void initState() {
    super.initState();
    _summary = widget.initial();
    _subscribe();
  }

  @override
  void didUpdateWidget(StreamBuilderBase<T, S> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream == widget.stream) {
      return;
    }
    if (_subscription != null) {
      _unsubscribe();
      _summary = widget.afterDisconnected(_summary);
    }
    _subscribe();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.build(context, _summary);

  void _subscribe() {
    final stream = widget.stream;
    if (stream == null) {
      return;
    }
    _subscription = stream.listen(
      (data) => setState(() => _summary = widget.afterData(_summary, data)),
      onError: (Object error, StackTrace stackTrace) => setState(
        () => _summary = widget.afterError(_summary, error, stackTrace),
      ),
      onDone: () => setState(() => _summary = widget.afterDone(_summary)),
    );
    _summary = widget.afterConnected(_summary);
  }

  void _unsubscribe() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }
}

/// Shows what [builder] returns for the latest snapshot of [stream], from
/// [initialData] on: waiting once the stream is listened to, active with
/// each event it delivers, done once it closes, and none while there is no
/// stream; a snapshot keeps the latest data or error until the next one.
///
/// See [StreamBuilderBase] for when the stream is listened to.
///
/// The latest of the numbers a stream delivers, a dash until the first:
///
/// ```dart
/// StreamBuilder<int>(
///   stream: ticks,
///   builder: (context, snapshot) => Text('${snapshot.data ?? '-'}'),
/// )
/// ```
///
/// See also:
///
///  * [FutureBuilder], for one result.
final class StreamBuilder<T> extends StreamBuilderBase<T, AsyncSnapshot<T>> {
  /// Shows what [builder] returns for the snapshots of [stream], the first
  /// with [initialData].
  const StreamBuilder({
    required super.stream,
    required this.builder,
    super.key,
    this.initialData,
  });

  /// Builds what this widget shows from the latest snapshot.
  // called with the state's snapshots, whose T is the widget's own
  // ignore: unsafe_variance
  final AsyncWidgetBuilder<T> builder;

  /// The data of the first snapshot; null for none.
  final T? initialData;

  @override
  AsyncSnapshot<T> initial() => initialData == null
      ? AsyncSnapshot<T>.nothing()
      : AsyncSnapshot<T>.withData(ConnectionState.none, initialData as T);

  @override
  AsyncSnapshot<T> afterConnected(AsyncSnapshot<T> current) =>
      current.inState(ConnectionState.waiting);

  @override
  AsyncSnapshot<T> afterData(AsyncSnapshot<T> current, T data) =>
      AsyncSnapshot<T>.withData(ConnectionState.active, data);

  @override
  AsyncSnapshot<T> afterError(
    AsyncSnapshot<T> current,
    Object error,
    StackTrace stackTrace,
  ) => AsyncSnapshot<T>.withError(ConnectionState.active, error, stackTrace);

  @override
  AsyncSnapshot<T> afterDone(AsyncSnapshot<T> current) =>
      current.inState(ConnectionState.done);

  @override
  AsyncSnapshot<T> afterDisconnected(AsyncSnapshot<T> current) =>
      current.inState(ConnectionState.none);

  @override
  Widget build(BuildContext context, AsyncSnapshot<T> currentSummary) =>
      builder(context, currentSummary);
}

/// Shows what [builder] returns for the latest snapshot of [future], from
/// [initialData] on: waiting while the future runs, done with its value or
/// error once it completes, and none while there is no future; a snapshot
/// keeps the latest data or error until the next one.
///
/// The future of a widget is waited on from the element's mount or update
/// on, rebuilding in the next build scope after it completes; the result
/// of a future a new widget replaced, or of one the element was disposed
/// with, is ignored. So the future is made once, in a state's `initState`
/// or by the caller, not in the build that makes this widget: a new one
/// each build starts over each time.
///
/// ```dart
/// FutureBuilder<String>(
///   future: answer,
///   builder: (context, snapshot) => switch (snapshot) {
///     AsyncSnapshot(hasError: true) => Text('failed: ${snapshot.error}'),
///     AsyncSnapshot(hasData: true) => Text(snapshot.requireData),
///     _ => const Text('thinking…'),
///   },
/// )
/// ```
///
/// See also:
///
///  * [StreamBuilder], for a result after another.
final class FutureBuilder<T> extends StatefulWidget {
  /// Shows what [builder] returns for the snapshots of [future], the first
  /// with [initialData].
  const FutureBuilder({
    required this.future,
    required this.builder,
    super.key,
    this.initialData,
  });

  /// What this widget waits on; null for nothing.
  final Future<T>? future;

  /// Builds what this widget shows from the latest snapshot.
  // called by the state, whose T is the widget's own
  // ignore: unsafe_variance
  final AsyncWidgetBuilder<T> builder;

  /// The data of the first snapshot; null for none.
  final T? initialData;

  @override
  State<FutureBuilder<T>> createState() => _FutureBuilderState<T>();
}

final class _FutureBuilderState<T> extends State<FutureBuilder<T>> {
  // the token of the latest future, which its callbacks check; null
  // without one and once disposed
  Object? _waitingOn;
  late AsyncSnapshot<T> _snapshot;

  @override
  void initState() {
    super.initState();
    final initialData = widget.initialData;
    _snapshot = initialData == null
        ? AsyncSnapshot<T>.nothing()
        : AsyncSnapshot<T>.withData(ConnectionState.none, initialData);
    _subscribe();
  }

  @override
  void didUpdateWidget(FutureBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.future == widget.future) {
      return;
    }
    if (_waitingOn != null) {
      _waitingOn = null;
      _snapshot = _snapshot.inState(ConnectionState.none);
    }
    _subscribe();
  }

  @override
  void dispose() {
    _waitingOn = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _snapshot);

  void _subscribe() {
    final future = widget.future;
    if (future == null) {
      return;
    }
    final token = Object();
    _waitingOn = token;
    unawaited(
      future.then<void>(
        (data) {
          if (mounted && _waitingOn == token) {
            setState(
              () => _snapshot = AsyncSnapshot<T>.withData(
                ConnectionState.done,
                data,
              ),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (mounted && _waitingOn == token) {
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
