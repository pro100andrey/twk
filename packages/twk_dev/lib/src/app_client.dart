/// A running app as `twk inspect` reaches it, through its VM service:
/// [AppClient], [VmAppClient], [AppError], and [watchExtensions].
library;

import 'dart:async';
import 'dart:convert';

import 'package:twk/twk.dart' show AppBinding;
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// A JSON object.
typedef Json = Map<String, Object?>;

/// What an app answered in place of an answer, or why it gave none.
final class AppError implements Exception {
  /// An error saying [message].
  const AppError(this.message);

  /// What the app answered, or why it gave no answer.
  final String message;

  @override
  String toString() => message;
}

/// A running app as `twk inspect` sees it: the `ext.twk.*` service
/// extensions of its binding (`AppBinding.callServiceExtension`) and the
/// cells picked on its screen.
abstract interface class AppClient {
  /// Where the app is, for the inspector to say.
  String get name;

  /// What `ext.twk.<method>` answers with [params]: a JSON object of the
  /// version this client reads ([AppBinding.serviceExtensionsVersion]). An
  /// [AppError] with the app's message when it answers with an error, and
  /// when it has gone.
  Future<Json> call(String method, [Map<String, String> params]);

  /// The cells picked on the app's screen (`twk.select`, after
  /// `ext.twk.flags` `select`): column and row, or null for a pick
  /// cancelled.
  Stream<(int, int)?> get picks;

  /// Completes when the app has gone.
  Future<void> get done;

  /// Lets the app go.
  Future<void> close();
}

/// Calls [added] with each service extension an isolate of [service]
/// registers: those registered already, then those to come until the
/// subscription answered is cancelled. Throws what the service threw
/// listening, the subscription cancelled then.
Future<StreamSubscription<Event>> watchExtensions(
  VmService service,
  void Function(String isolate, String rpc) added,
) async {
  final events = service.onIsolateEvent.listen((event) {
    final rpc = event.extensionRPC;
    if (event.kind == EventKind.kServiceExtensionAdded && rpc != null) {
      added(event.isolate!.id!, rpc);
    }
  });
  try {
    await service.streamListen(EventStreams.kIsolate);
    final vm = await service.getVM();
    for (final ref in vm.isolates ?? const <IsolateRef>[]) {
      final isolate = await service.getIsolate(ref.id!);
      for (final rpc in isolate.extensionRPCs ?? const <String>[]) {
        added(ref.id!, rpc);
      }
    }
  } on Object {
    await events.cancel();
    rethrow;
  }
  return events;
}

/// An app reached over its VM service (`package:vm_service`): the isolate
/// that registered the binding's extensions.
final class VmAppClient implements AppClient {
  VmAppClient._(this.name, this._service, this._isolate, this._events);

  /// Connects to the VM service at [uri]: its WebSocket address
  /// (`ws://127.0.0.1:8181/token=/ws`), or the one the VM prints
  /// (`http://127.0.0.1:8181/token=/`), which `convertToWebSocketUrl`
  /// makes one. Throws what connecting threw when nothing answers there.
  static Future<VmService> connect(Uri uri) => vmServiceConnectUri(
    '${convertToWebSocketUrl(serviceProtocolUrl: uri)}',
  );

  /// The app of [service], once an isolate of it has registered the
  /// binding's extensions (its first `runApp`), [name] for where it is.
  /// An [AppError] when the service goes away first.
  static Future<VmAppClient> attach(VmService service, String name) async {
    final found = Completer<String>();
    // the picks of every isolate, which the client takes its own of
    final picks = StreamController<(String, (int, int)?)>.broadcast();
    service.onExtensionEvent.listen((event) {
      if (event.extensionKind == 'twk.select') {
        final data = event.extensionData?.data;
        final x = data?['x'];
        final y = data?['y'];
        picks.add((
          event.isolate?.id ?? '',
          x is int && y is int ? (x, y) : null,
        ));
      }
    });
    unawaited(
      service.onDone.then((_) {
        if (!found.isCompleted) {
          found.completeError(const AppError('the app went away'));
        }
        unawaited(picks.close());
      }),
    );
    StreamSubscription<Event>? isolates;
    try {
      await service.streamListen(EventStreams.kExtension);
      isolates = await watchExtensions(service, (id, rpc) {
        if (rpc == 'ext.twk.tree' && !found.isCompleted) {
          found.complete(id);
        }
      });
    } on Object catch (e) {
      if (!found.isCompleted) {
        found.completeError(AppError('$e'));
      }
    }
    try {
      final isolate = await found.future;
      return VmAppClient._(name, service, isolate, picks.stream);
    } on Object {
      await service.dispose();
      rethrow;
    } finally {
      await isolates?.cancel();
    }
  }

  @override
  final String name;

  final VmService _service;
  final String _isolate;
  final Stream<(String, (int, int)?)> _events;

  @override
  Stream<(int, int)?> get picks =>
      _events.where((e) => e.$1 == _isolate).map((e) => e.$2);

  @override
  Future<void> get done => _service.onDone;

  @override
  Future<Json> call(
    String method, [
    Map<String, String> params = const {},
  ]) async {
    final Response response;
    try {
      response = await _service.callServiceExtension(
        'ext.twk.$method',
        isolateId: _isolate,
        args: params,
      );
    } on RPCError catch (e) {
      throw AppError(_messageOf(e));
    } on Object {
      throw const AppError('the app went away');
    }
    final json = {...?response.json}..remove('type');
    const version = AppBinding.serviceExtensionsVersion;
    if (json['version'] != version) {
      throw AppError(
        'the app answers in version ${json['version']} of ext.twk, '
        'twk inspect reads $version',
      );
    }
    return json;
  }

  /// The message of the app's error [e], or what the service says: a
  /// server error without the app's message is the connection's, gone.
  static String _messageOf(RPCError e) {
    try {
      final details = jsonDecode(e.details ?? '');
      if (details case {'message': final String message}) {
        return message;
      }
    } on FormatException {
      // not the app's
    }
    return e.code == RPCErrorKind.kServerError.code
        ? 'the app went away'
        : e.message;
  }

  @override
  Future<void> close() => _service.dispose();
}
