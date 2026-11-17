// `twk mcp`'s protocol: initialize, tools/list, tools/call, the protocol
// version, malformed requests, and the tools' failures as results.
import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:twk_dev/src/mcp.dart';
import 'package:twk_dev/src/mcp/jsonrpc.dart';

final class _Echo implements McpTool {
  _Echo(this.name, this._run);

  @override
  final String name;

  final Future<McpResult> Function(JsonMap) _run;

  @override
  String get description => 'echoes';

  @override
  JsonMap get inputSchema => {'type': 'object'};

  @override
  Future<McpResult> call(JsonMap arguments) => _run(arguments);
}

McpServer _server() => McpServer(
  name: 'fake',
  version: '1.2.3',
  instructions: 'be kind',
  tools: [
    _Echo('echo', (a) async => McpResult('${a['text']}')),
    _Echo('fails', (_) async => const McpResult.error('no good')),
    _Echo('throws', (_) async => throw StateError('boom')),
  ],
);

Future<JsonMap> _ask(
  McpServer server,
  String method, [
  Object? params,
  Object? id = 1,
]) async {
  final reply = await server.handleLine(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': ?params,
    }),
  );
  return jsonDecode(reply!) as JsonMap;
}

JsonMap _error(JsonMap reply) => reply['error']! as JsonMap;

void main() {
  group('initialize', () {
    test('answers the version asked for when it speaks it', () async {
      for (final v in McpServer.protocolVersions) {
        final r = await _ask(_server(), 'initialize', {'protocolVersion': v});
        expect((r['result']! as JsonMap)['protocolVersion'], v);
      }
    });

    test('answers the newest it speaks to a version it does not', () async {
      final r = await _ask(_server(), 'initialize', {
        'protocolVersion': '1999-01-01',
      });
      final result = r['result']! as JsonMap;
      expect(result['protocolVersion'], McpServer.protocolVersions.first);
      expect(result['serverInfo'], {'name': 'fake', 'version': '1.2.3'});
      expect(result['instructions'], 'be kind');
      expect(result['capabilities'], {
        'tools': {'listChanged': false},
      });
    });

    test('needs a protocolVersion', () async {
      final r = await _ask(_server(), 'initialize', {});
      expect(_error(r)['code'], RpcCode.invalidParams);
    });

    test('echoes the id, a string too', () async {
      final r = await _ask(_server(), 'ping', null, 'abc');
      expect(r, {'jsonrpc': '2.0', 'id': 'abc', 'result': <String, Object?>{}});
    });
  });

  test('a notification is not answered', () async {
    final server = _server();
    expect(
      await server.handleLine(
        '{"jsonrpc":"2.0","method":"notifications/initialized"}',
      ),
      isNull,
    );
    // nor is an error of one
    expect(
      await server.handleLine(
        '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"nope"}}',
      ),
      isNull,
    );
    // not even a tool call of one
    expect(
      await server.handleLine(
        '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"echo"}}',
      ),
      isNull,
    );
  });

  test('tools/list names each tool with its schema', () async {
    final r = await _ask(_server(), 'tools/list');
    final tools = (r['result']! as JsonMap)['tools']! as List<Object?>;
    expect(
      [for (final t in tools) (t! as JsonMap)['name']],
      [
        'echo',
        'fails',
        'throws',
      ],
    );
    expect(tools.first, containsPair('inputSchema', {'type': 'object'}));
    expect(tools.first, containsPair('description', 'echoes'));
  });

  group('tools/call', () {
    test('answers the text of the tool', () async {
      final r = await _ask(_server(), 'tools/call', {
        'name': 'echo',
        'arguments': {'text': 'hi'},
      });
      expect(r['result'], {
        'content': [
          {'type': 'text', 'text': 'hi'},
        ],
        'isError': false,
      });
    });

    test('a failure is a result with its reason', () async {
      final r = await _ask(_server(), 'tools/call', {'name': 'fails'});
      final result = r['result']! as JsonMap;
      expect(result['isError'], isTrue);
      expect(jsonEncode(result), contains('no good'));
    });

    test('a tool that throws is a failed result, not a dead server', () async {
      final server = _server();
      final r = await _ask(server, 'tools/call', {'name': 'throws'});
      final result = r['result']! as JsonMap;
      expect(result['isError'], isTrue);
      expect(jsonEncode(result), contains('boom'));
      expect(await _ask(server, 'ping'), contains('result'));
    });

    test('an unknown tool is invalid params', () async {
      final r = await _ask(_server(), 'tools/call', {'name': 'nope'});
      expect(_error(r)['code'], RpcCode.invalidParams);
      expect(_error(r)['message'], contains('nope'));
    });

    test(
      'a call without a name, or with arguments that are no object',
      () async {
        expect(
          _error(await _ask(_server(), 'tools/call', {}))['code'],
          RpcCode.invalidParams,
        );
        expect(
          _error(
            await _ask(_server(), 'tools/call', {
              'name': 'echo',
              'arguments': [1],
            }),
          )['code'],
          RpcCode.invalidParams,
        );
      },
    );
  });

  group('malformed requests', () {
    test('not JSON', () async {
      final r = jsonDecode((await _server().handleLine('{"jsonrpc'))!);
      expect(_error(r as JsonMap)['code'], RpcCode.parseError);
      expect(r['id'], isNull);
    });

    test('a batch, a scalar', () async {
      for (final line in ['[{"jsonrpc":"2.0","id":1,"method":"ping"}]', '7']) {
        final r = jsonDecode((await _server().handleLine(line))!) as JsonMap;
        expect(_error(r)['code'], RpcCode.invalidRequest);
      }
    });

    test('no jsonrpc version, no method, an id that is no id', () async {
      for (final line in [
        '{"id":1,"method":"ping"}',
        '{"jsonrpc":"2.0","id":1}',
        '{"jsonrpc":"2.0","id":1.5,"method":"ping"}',
        '{"jsonrpc":"2.0","id":1,"method":7}',
      ]) {
        final r = jsonDecode((await _server().handleLine(line))!) as JsonMap;
        expect(_error(r)['code'], RpcCode.invalidRequest, reason: line);
      }
    });

    test('params that are no object', () async {
      final r = await _ask(_server(), 'tools/list', [1]);
      expect(_error(r)['code'], RpcCode.invalidParams);
    });

    test('an unknown method', () async {
      final r = await _ask(_server(), 'resources/list');
      expect(_error(r)['code'], RpcCode.methodNotFound);
    });

    test('a response of the client is no request', () async {
      expect(
        await _server().handleLine('{"jsonrpc":"2.0","id":9,"result":{}}'),
        isNull,
      );
    });
  });

  test('serve answers in order, one line each, until input ends', () async {
    final gate = Completer<void>();
    final server = McpServer(
      name: 'f',
      version: '1',
      instructions: '',
      tools: [
        _Echo('slow', (_) async {
          await gate.future;
          return const McpResult('slow');
        }),
        _Echo('fast', (_) async => const McpResult('fast')),
      ],
    );
    String call(int id, String name) => jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': 'tools/call',
      'params': {'name': name},
    });
    final lines = <String>[];
    final input = StreamController<List<int>>();
    final done = server.serve(input.stream, lines.add);
    input.add(utf8.encode('${call(1, 'slow')}\n\n${call(2, 'fast')}\n'));
    await pumpEventQueue();
    expect(lines, isEmpty);
    gate.complete();
    await input.close();
    await done;
    expect([for (final l in lines) (jsonDecode(l) as JsonMap)['id']], [1, 2]);
  });

  group('the app tools', () {
    Future<String> tool(McpServer s, String name, [JsonMap? args]) async {
      final r = await _ask(s, 'tools/call', {'name': name, 'arguments': ?args});
      final result = r['result']! as JsonMap;
      expect(result['isError'], isTrue, reason: name);
      return ((result['content']! as List).single as JsonMap)['text']!
          as String;
    }

    test('are the twelve of the design, each with a schema', () async {
      final r = await _ask(twkMcpServer(), 'tools/list');
      final tools = ((r['result']! as JsonMap)['tools']! as List)
          .cast<JsonMap>();
      expect(
        [for (final t in tools) t['name']],
        [
          'start_app',
          'screen',
          'tree',
          'find',
          'press',
          'type',
          'tap',
          'wait_for',
          'elapse',
          'hot_reload',
          'logs',
          'stop_app',
        ],
      );
      for (final t in tools) {
        expect((t['inputSchema']! as JsonMap)['type'], 'object');
        expect(t['description'], isNotEmpty);
      }
    });

    test('say there is no app, and what starts one', () async {
      final s = twkMcpServer();
      for (final name in ['screen', 'tree', 'logs', 'hot_reload', 'stop_app']) {
        expect(await tool(s, name), contains('start_app'), reason: name);
      }
      expect(
        await tool(s, 'press', {'keys': 'q'}),
        contains('no app is running'),
      );
    });

    test('start_app names what is wrong with its arguments', () async {
      final s = twkMcpServer();
      expect(await tool(s, 'start_app', {}), contains('"program"'));
      expect(
        await tool(s, 'start_app', {'program': '/nonexistent/main.dart'}),
        contains('no such file'),
      );
    });
  });
}
