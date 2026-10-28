// The inspector's client of an app's VM service, against a VM service of
// the test's own that answers JSON-RPC as the VM does: the isolate of the
// binding found as it registers ext.twk.tree, the answers of that one,
// its picks and no other's, the app's errors, another version, and the
// app going away.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_dev/src/app_client.dart';
import 'package:twk_test/twk_test.dart' show waitFor;
import 'package:vm_service/vm_service.dart';

/// A VM service of isolates whose `ext.twk.*` extensions [answer] answers.
final class FakeVm {
  FakeVm(this.isolates) {
    service = VmService(_in.stream, _received);
  }

  /// The extensions each isolate registered, by its id.
  final Map<String, List<String>> isolates;

  late final VmService service;

  /// What an extension answers: its result, or with `error` the error
  /// the VM sends for it.
  Json Function(String method, Map<String, Object?> params) answer = (_, _) => {
    'version': 1,
  };

  /// The extension calls, `method isolateId` each.
  final calls = <String>[];

  /// The error `getVM` answers with; null for the VM.
  Json? vmError;

  final _in = StreamController<String>();

  void _received(String message) {
    final request = jsonDecode(message) as Json;
    final params = (request['params'] as Json?) ?? const {};
    final method = request['method']! as String;
    final Json reply;
    switch (method) {
      case 'streamListen':
        reply = {
          'result': {'type': 'Success'},
        };
      case 'getVM' when vmError != null:
        reply = {'error': vmError};
      case 'getVM':
        reply = {
          'result': {
            'type': 'VM',
            'isolates': [for (final id in isolates.keys) _ref(id)],
          },
        };
      case 'getIsolate':
        final id = params['isolateId']! as String;
        reply = {
          'result': {
            ..._ref(id),
            'type': 'Isolate',
            'extensionRPCs': isolates[id],
          },
        };
      default:
        calls.add('$method ${params['isolateId']}');
        final answer = this.answer(method, params);
        reply = answer.containsKey('error')
            ? {'error': answer['error']}
            : {
                'result': {...answer, 'type': '_extensionType'},
              };
    }
    _in.add(jsonEncode({'jsonrpc': '2.0', 'id': request['id'], ...reply}));
  }

  static Json _ref(String id) => {
    'type': '@Isolate',
    'id': id,
    'name': 'main',
    'number': id.split('/').last,
    'isSystemIsolate': false,
  };

  void _event(String stream, Json event) => _in.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'method': 'streamNotify',
      'params': {
        'streamId': stream,
        'event': {'type': 'Event', 'timestamp': 0, ...event},
      },
    }),
  );

  /// The isolate [id] registers the extension [rpc].
  void register(String id, String rpc) {
    isolates[id]!.add(rpc);
    _event('Isolate', {
      'kind': 'ServiceExtensionAdded',
      'isolate': _ref(id),
      'extensionRPC': rpc,
    });
  }

  /// The isolate [id] posts the event [kind] with [data].
  void post(String id, String kind, Json data) => _event('Extension', {
    'kind': 'Extension',
    'isolate': _ref(id),
    'extensionKind': kind,
    'extensionData': data,
  });

  /// The VM goes away.
  Future<void> close() => _in.close();
}

void main() {
  test('watchExtensions names the extensions registered already, then '
      'those to come until it is cancelled', () async {
    final vm = FakeVm({
      'isolates/1': ['ext.twk.tree'],
      'isolates/2': [],
    });
    final added = <String>[];
    var named = Completer<void>();
    final watch = await watchExtensions(vm.service, (isolate, rpc) {
      added.add('$isolate $rpc');
      named.complete();
    });
    expect(added, ['isolates/1 ext.twk.tree']);
    named = Completer<void>();
    vm.register('isolates/2', 'ext.twk.log');
    await waitFor(
      named.future,
      'watchExtensions to name ext.twk.log',
      timeout: const Duration(seconds: 5),
    );
    expect(added, ['isolates/1 ext.twk.tree', 'isolates/2 ext.twk.log']);
    await watch.cancel();
    vm.register('isolates/2', 'ext.twk.reassemble');
    // the VM is in memory: what it sends has arrived once the event queue
    // is empty
    await pumpEventQueue();
    expect(added, hasLength(2));
    await vm.close();
  });

  test('watchExtensions on a service that fails to name its isolates '
      'throws its error and names none after', () async {
    final vm = FakeVm({'isolates/1': []})
      ..vmError = {'code': -32000, 'message': 'the VM is busy'};
    final added = <String>[];
    await expectLater(
      watchExtensions(vm.service, (isolate, rpc) => added.add(rpc)),
      throwsA(isA<RPCError>()),
    );
    vm.register('isolates/1', 'ext.twk.tree');
    await pumpEventQueue();
    expect(added, isEmpty);
    await vm.close();
  });

  test('attach takes the isolate that registers ext.twk.tree, once it does, '
      'calls its extensions and gives its picks', () async {
    final vm = FakeVm({
      'isolates/1': ['ext.other'],
      'isolates/2': [],
    });
    var attached = false;
    final attaching = VmAppClient.attach(vm.service, 'the app');
    unawaited(attaching.then((_) => attached = true));
    await pumpEventQueue();
    expect(attached, isFalse);

    vm.register('isolates/2', 'ext.twk.tree');
    final app = await attaching.timeout(const Duration(seconds: 5));
    expect(app.name, 'the app');

    vm.answer = (method, params) => {
      'version': 1,
      'method': method,
      'id': params['id'],
    };
    expect(await app.call('properties', {'id': '7'}), {
      'version': 1,
      'method': 'ext.twk.properties',
      'id': '7',
    });
    expect(vm.calls, ['ext.twk.properties isolates/2']);

    final picks = app.picks.take(2).toList();
    vm
      ..post('isolates/1', 'twk.select', {'version': 1, 'x': 1, 'y': 1})
      ..post('isolates/2', 'twk.other', {'version': 1, 'x': 2, 'y': 2})
      ..post('isolates/2', 'twk.select', {'version': 1, 'x': 3, 'y': 4})
      ..post('isolates/2', 'twk.select', {'version': 1, 'x': null, 'y': null});
    expect(await picks.timeout(const Duration(seconds: 5)), [(3, 4), null]);
    await vm.close();
  });

  test('an isolate that registered ext.twk.tree before is taken at '
      'once', () async {
    final vm = FakeVm({
      'isolates/3': ['ext.twk.tree', 'ext.twk.flags'],
    });
    final app = await VmAppClient.attach(
      vm.service,
      'the app',
    ).timeout(const Duration(seconds: 5));
    await app.call('flags');
    expect(vm.calls, ['ext.twk.flags isolates/3']);
    await vm.close();
  });

  test("an error is the app's message, another version is said, and an app "
      'gone is said so', () async {
    final vm = FakeVm({
      'isolates/1': ['ext.twk.tree'],
    });
    final app = await VmAppClient.attach(vm.service, 'the app');

    vm.answer = (_, _) => {
      'error': {
        'code': -32000,
        'message': 'Server error',
        'data': {
          'details': jsonEncode({'message': 'no node 9 in the app'}),
        },
      },
    };
    await expectLater(
      app.call('layout', {'id': '9'}),
      throwsA(
        isA<AppError>().having(
          (e) => e.message,
          'message',
          'no node 9 in the app',
        ),
      ),
    );

    vm.answer = (_, _) => {'version': 2};
    await expectLater(
      app.call('tree'),
      throwsA(
        isA<AppError>().having(
          (e) => e.message,
          'message',
          'the app answers in version 2 of ext.twk, twk inspect reads 1',
        ),
      ),
    );

    await vm.close();
    await app.done.timeout(const Duration(seconds: 5));
    await expectLater(
      app.call('tree'),
      throwsA(
        isA<AppError>().having(
          (e) => e.message,
          'message',
          'the app went away',
        ),
      ),
    );
  });

  test('attach to a service that fails to name its isolates fails with '
      'its error', () async {
    final vm = FakeVm({'isolates/1': []})
      ..vmError = {'code': -32000, 'message': 'the VM is busy'};
    await expectLater(
      VmAppClient.attach(vm.service, 'the app'),
      throwsA(
        isA<AppError>().having(
          (e) => e.message,
          'message',
          contains('the VM is busy'),
        ),
      ),
    );
    await vm.close();
  });

  test('a client closed is done', () async {
    final vm = FakeVm({
      'isolates/1': ['ext.twk.tree'],
    });
    final app = await VmAppClient.attach(vm.service, 'the app');
    await app.close();
    await app.done.timeout(const Duration(seconds: 5));
    await vm.close();
  });

  test('attach to a service that goes away first is an app gone', () async {
    final vm = FakeVm({'isolates/1': []});
    final attaching = VmAppClient.attach(vm.service, 'the app');
    // attaching, it waits for the binding's isolate
    await pumpEventQueue();
    await vm.close();
    await expectLater(
      attaching,
      throwsA(
        isA<AppError>().having(
          (e) => e.message,
          'message',
          'the app went away',
        ),
      ),
    );
  });
}
