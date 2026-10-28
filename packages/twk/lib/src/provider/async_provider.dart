/// Providers of the values a future or a stream gives over time:
/// [FutureProvider], [StreamProvider].
library;

import 'dart:async';

import '../../twk.dart';

import 'inherited_provider.dart';

// Examples can assume:
// final class Cart extends ChangeNotifier {
//   final items = <String>[];
//   void add(String item) {
//     items.add(item);
//     notifyListeners();
//   }
// }
// final class Settings {
//   const Settings({this.dark = false, this.user = ''});
//   final bool dark;
//   final String user;
// }
// final class Api {
//   Api(this.settings);
//   final Settings settings;
// }
// final class Database {
//   void close() {}
// }
// late Widget app;
// late ValueNotifier<int> unread;
// late Stream<String> statusLines;
// Future<Settings> loadSettings() async => const Settings();

/// The value a [FutureProvider] or a [StreamProvider] provides in place of
/// `error`, which its future or stream gave.
typedef ErrorBuilder<T> = T Function(BuildContext context, Object? error);

/// Provides the value of a [Future]: `initialData` until it completes, then
/// what it completes with, the widgets that watch it rebuilt then.
///
/// The future is the one `create` makes, the first time the value is read
/// unless `lazy` is false; or with [FutureProvider.value] one made
/// elsewhere, listened to when this widget is placed in the tree, which a
/// new widget may replace by another. An error the future completes with
/// is replaced by what `catchError` returns for it; without one it is
/// logged at [LogLevel.error] and the value stays.
///
/// Settings loaded as the app starts, the defaults until then:
///
/// ```dart
/// FutureProvider(
///   create: (context) => loadSettings(),
///   initialData: const Settings(),
///   child: app,
/// )
/// ```
final class FutureProvider<T> extends DeferredInheritedProvider<Future<T>?, T> {
  /// Provides the value of the future `create` makes, [initialData] until
  /// it completes.
  FutureProvider({
    required super.create,
    required T initialData,
    super.key,
    ErrorBuilder<T>? catchError,
    super.updateShouldNotify,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         startListening: _futureStartListening(
           initialData: initialData,
           catchError: catchError,
         ),
       );

  /// Provides the value of `value`, a future made elsewhere,
  /// [initialData] until it completes.
  FutureProvider.value({
    required super.value,
    required T initialData,
    super.key,
    ErrorBuilder<T>? catchError,
    super.updateShouldNotify,
    super.builder,
    super.child,
  }) : super.value(
         lazy: false,
         startListening: _futureStartListening(
           initialData: initialData,
           catchError: catchError,
         ),
       );
}

/// Provides the last value of a [Stream]: `initialData` until it gives
/// one, the widgets that watch it rebuilt by each that is not `==` the one
/// before (or as `updateShouldNotify` says).
///
/// The stream is the one `create` makes, the first time the value is read
/// unless `lazy` is false; or with [StreamProvider.value] one made
/// elsewhere, which a new widget may replace by another. It is listened to
/// from the first time the value is read until it is replaced or this
/// widget leaves the tree. An error the stream gives is replaced by what
/// `catchError` returns for it; without one it is logged at
/// [LogLevel.error] and the value stays.
///
/// ```dart
/// StreamProvider.value(
///   value: statusLines,
///   initialData: 'Starting…',
///   child: Builder(builder: (context) => Text(context.watch<String>())),
/// )
/// ```
final class StreamProvider<T> extends DeferredInheritedProvider<Stream<T>?, T> {
  /// Provides the last value of the stream `create` makes, [initialData]
  /// until it gives one.
  StreamProvider({
    required super.create,
    required T initialData,
    super.key,
    ErrorBuilder<T>? catchError,
    super.updateShouldNotify,
    super.lazy,
    super.builder,
    super.child,
  }) : super(
         startListening: _streamStartListening(
           initialData: initialData,
           catchError: catchError,
         ),
       );

  /// Provides the last value of `value`, a stream made elsewhere,
  /// [initialData] until it gives one.
  StreamProvider.value({
    required super.value,
    required T initialData,
    super.key,
    ErrorBuilder<T>? catchError,
    super.updateShouldNotify,
    super.lazy,
    super.builder,
    super.child,
  }) : super.value(
         startListening: _streamStartListening(
           initialData: initialData,
           catchError: catchError,
         ),
       );
}

DeferredStartListening<Future<T>?, T> _futureStartListening<T>({
  required T initialData,
  required ErrorBuilder<T>? catchError,
}) => (element, setState, future, _) {
  if (!element.hasValue) {
    setState(initialData);
  }
  var cancelled = false;
  if (future != null) {
    unawaited(
      future.then(
        (value) {
          if (!cancelled && element.mounted) {
            setState(value);
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!cancelled && element.mounted) {
            _failed(
              element,
              setState,
              catchError,
              'FutureProvider<$T>',
              error,
              stack,
            );
          }
        },
      ),
    );
  }
  return () => cancelled = true;
};

DeferredStartListening<Stream<T>?, T> _streamStartListening<T>({
  required T initialData,
  required ErrorBuilder<T>? catchError,
}) => (element, setState, stream, _) {
  if (!element.hasValue) {
    setState(initialData);
  }
  if (stream == null) {
    return () {};
  }
  final subscription = stream.listen(
    setState,
    onError: (Object error, StackTrace stack) => _failed(
      element,
      setState,
      catchError,
      'StreamProvider<$T>',
      error,
      stack,
    ),
  );
  return () => unawaited(subscription.cancel());
};

/// Hands what [catchError] returns for [error] to [setState], or logs
/// [error] when there is no [catchError].
void _failed<T>(
  BuildContext context,
  void Function(T value) setState,
  ErrorBuilder<T>? catchError,
  String provider,
  Object error,
  StackTrace stack,
) {
  if (catchError != null) {
    setState(catchError(context, error));
    return;
  }
  log(
    'An exception was thrown by what $provider listens to, which has no '
    'catchError',
    level: LogLevel.error,
    error: error,
    stack: stack,
  );
}
