// `twk mcp` as a process: a scripted MCP client over its stdio drives a
// real app in a pseudo-terminal, on the time the server moves.
@Tags(['process'])
@TestOn('linux || mac-os')
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_test/twk_test.dart' show waitUntil;

/// A client of `twk mcp`: requests a line each, the answer of each read.
final class _Client {
  _Client._(this.process, this._lines);

  static Future<_Client> start() async {
    final process = await Process.start('dart', [
      'bin/twk.dart',
      'mcp',
    ]);
    unawaited(process.stderr.drain<void>());
    final client = _Client._(
      process,
      StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
    );
    return client;
  }

  final Process process;
  final StreamIterator<String> _lines;
  var _id = 0;

  Future<Map<String, Object?>> request(String method, [Object? params]) async {
    final id = ++_id;
    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    expect(await _lines.moveNext(), isTrue, reason: 'the server ended');
    final reply = jsonDecode(_lines.current) as Map<String, Object?>;
    expect(reply['id'], id);
    return reply;
  }

  /// The text of a tool's answer, and whether it failed.
  Future<(String, bool)> tool(String name, [Map<String, Object?>? args]) async {
    final reply = await request('tools/call', {
      'name': name,
      'arguments': ?args,
    });
    final result = reply['result']! as Map<String, Object?>;
    final text =
        ((result['content']! as List).single as Map<String, Object?>)['text']!
            as String;
    return (text, result['isError']! as bool);
  }

  /// A tool's text, that it did not fail.
  Future<String> ok(String name, [Map<String, Object?>? args]) async {
    final (text, failed) = await tool(name, args);
    expect(failed, isFalse, reason: '$name: $text');
    return text;
  }

  /// A tool's reason, that it failed.
  Future<String> fails(String name, [Map<String, Object?>? args]) async {
    final (text, failed) = await tool(name, args);
    expect(failed, isTrue, reason: '$name: $text');
    return text;
  }

  Future<void> close() async {
    await process.stdin.close();
    await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
  }
}

void main() {
  late _Client client;

  setUp(() async {
    client = await _Client.start();
    final init = await client.request('initialize', {
      'protocolVersion': '2025-06-18',
      'capabilities': <String, Object?>{},
      'clientInfo': {'name': 'test', 'version': '0'},
    });
    expect(
      (init['result']! as Map<String, Object?>)['protocolVersion'],
      '2025-06-18',
    );
    client.process.stdin.writeln(
      '{"jsonrpc":"2.0","method":"notifications/initialized"}',
    );
  });

  tearDown(() => client.close());

  test('drives an app: keys, a tap, time, the log and the exit', () async {
    final first = await client.ok('start_app', {
      'program': 'test/mcp_app.dart',
    });
    expect(first, contains('Count: 0'));
    expect(first, contains(RegExp(r'frame \d+, input read \d+ bytes, quiet')));

    final tree = await client.ok('tree');
    expect(tree, contains('Button #'));
    final shallow = await client.ok('tree', {'depth': 1});
    expect(shallow, contains('more below'));
    expect(shallow.split('\n').length, lessThan(tree.split('\n').length));

    expect(
      await client.ok('find', {
        'finder': {'text': 'Save'},
      }),
      contains("Text 'Save'"),
    );

    expect(
      await client.ok('press', {'keys': 'up up'}),
      contains('Count: 2'),
    );

    // a tap, whose timer (a notice for a second) the clock moves on
    final tapped = await client.ok('tap', {
      'finder': {'text': 'Save'},
    });
    expect(tapped, contains('Saved: 1'));
    expect(tapped, contains('Notice: saved'));
    expect(tapped, contains('not quiet (next timer in'));
    final gone = await client.ok('wait_for', {'absent': 'Notice'});
    expect(gone, isNot(contains('Notice')));
    expect(gone, contains('quiet'));

    // an app that is quiet will never change: the reason, at once
    final never = await client.fails('wait_for', {'text': 'Never there'});
    expect(never, startsWith('never:'));
    expect(never, contains('io_ms'));

    expect(await client.ok('elapse', {'ms': 500}), contains('Saved: 1'));
    expect(await client.ok('screen'), contains('Count: 2'));

    // the log comes over a socket of its own, as it comes
    final logs = StringBuffer();
    await waitUntil(() async {
      logs.writeln(await client.ok('logs'));
      return '$logs'.contains('saved 1');
    }, 'the record of the save in the log');
    expect('$logs', contains('info    saved 1'));
    expect(await client.ok('logs'), 'no log records');

    // what a failure says
    expect(
      await client.fails('tap', {
        'finder': {'text': 'Nowhere'},
      }),
      contains('matches nothing'),
    );
    expect(
      await client.fails('tap', {
        'finder': {'type': 'Text'},
      }),
      contains('matches'),
    );
    expect(
      await client.fails('find', {
        'finder': {'frobnicate': 1},
      }),
      contains('not a finder'),
    );
    expect(
      await client.fails('start_app', {'program': 'test/mcp_app.dart'}),
      contains('stop_app'),
    );

    final quit = await client.ok('press', {'keys': 'q'});
    expect(quit, contains('the app exited (0)'));
    expect(await client.ok('press', {'keys': 'up'}), contains('exited (0)'));
    expect(await client.ok('stop_app'), contains('the app had exited (0)'));
    expect(await client.fails('screen'), contains('start_app'));
  });

  test('stop_app ends a running app', () async {
    await client.ok('start_app', {'program': 'test/mcp_app.dart'});
    expect(await client.ok('stop_app'), 'the app was stopped');
    // and another can start after
    expect(
      await client.ok('start_app', {'program': 'test/mcp_app.dart'}),
      contains('Count: 0'),
    );
    await client.ok('stop_app');
  });

  test('hot_reload takes up a change of the sources', () async {
    final dir = Directory(
      p.join('.dart_tool', 'mcp_reload_${pid}_${DateTime.now().microsecond}'),
    )..createSync(recursive: true);
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File(p.join(dir.path, 'app.dart'))
      ..writeAsStringSync(File('test/mcp_app.dart').readAsStringSync());
    expect(
      await client.ok('start_app', {'program': file.path}),
      contains('Count: 0'),
    );
    await client.ok('press', {'keys': 'up'});
    file.writeAsStringSync(
      file.readAsStringSync().replaceAll("'Count: ", "'Total: "),
    );
    final reloaded = await client.ok('hot_reload');
    expect(reloaded, startsWith('hot reload:'));
    // the State is kept: the count with it, the text as the new code has it
    expect(reloaded, contains('Total: 1'));

    // a source that does not compile is the reload's failure, with why
    file.writeAsStringSync('${file.readAsStringSync()}\nint x = ;\n');
    final failed = await client.fails('hot_reload');
    expect(failed, startsWith('hot reload failed'));
    await client.ok('stop_app');
  });
}
