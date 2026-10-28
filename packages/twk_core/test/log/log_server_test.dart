// The sink served on a local socket, as `twk logs` reads it: the token
// first, then the records kept and each one as it comes, as lines of JSON.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart' as twk_test show waitFor;

final _at = DateTime(2026, 10, 19, 9, 5, 7, 42);

LogRecord record(String message, [LogLevel level = LogLevel.info]) =>
    LogRecord(_at, level, message);

/// A client of a served sink: sends a token and keeps the records that
/// come back; [waitFor] waits for one. What it waits for comes over a
/// real socket, so each wait is bounded in real time and fails naming
/// what it waited for.
final class Client {
  Client._(this.socket, String token) {
    socket
      ..write('$token\n')
      ..cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final record = LogRecord.fromJson(
              jsonDecode(line) as Map<String, Object?>,
            );
            records.add(record);
            for (final w in [..._waits]) {
              if (w.$1 == record.message) {
                _waits.remove(w);
                w.$2.complete();
              }
            }
          }, onDone: _closed.complete);
  }

  static Future<Client> connect(LocalAddress address, [String? token]) async =>
      Client._(await address.connect(), token ?? address.token);

  final Socket socket;
  final records = <LogRecord>[];
  final _closed = Completer<void>();
  final _waits = <(String, Completer<void>)>[];

  /// Completes when the server closes the connection.
  Future<void> get closed =>
      twk_test.waitFor(_closed.future, 'the connection closed');

  List<String> get messages => [for (final r in records) r.message];

  /// Completes once a record of [message] came.
  Future<void> waitFor(String message) {
    if (messages.contains(message)) {
      return Future.value();
    }
    final done = Completer<void>();
    _waits.add((message, done));
    return twk_test.waitFor(done.future, 'the record "$message"');
  }
}

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('twk_logs');
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a record survives JSON', () {
    final full = LogRecord(
      _at,
      LogLevel.error,
      'failed',
      error: StateError('bad'),
      stack: StackTrace.fromString('#0 main (file.dart:1:2)'),
    );
    final back = LogRecord.fromJson(
      jsonDecode(jsonEncode(full.toJson())) as Map<String, Object?>,
    );
    expect('$back', '$full');
    expect(back.time, _at);
    expect(back.level, LogLevel.error);
    final plain = LogRecord.fromJson(record('plain').toJson());
    expect((plain.error, plain.stack), (null, null));
  });

  test('a client gets the records kept, then each one as it is added, '
      "until the sink stops serving; the project's address file names "
      'the socket meanwhile', () async {
    final sink = LogSink(capacity: 2)
      ..add(record('dropped'))
      ..add(record('kept 1'))
      ..add(record('kept 2', LogLevel.warning));
    final address = await sink.serve(directory: dir.path);
    final file = LocalAddress.fileOf('logs', dir.path);
    expect(LocalAddress.read(file), address);
    expect(await sink.serve(directory: dir.path), address);

    final client = await Client.connect(address);
    await client.waitFor('kept 2');
    expect(client.messages, ['kept 1', 'kept 2']);
    expect(client.records[1].level, LogLevel.warning);
    sink.add(record('live'));
    await client.waitFor('live');
    expect(client.messages, ['kept 1', 'kept 2', 'live']);

    await sink.close();
    await client.closed;
    expect(File(file).existsSync(), isFalse);
    sink.add(record('after')); // no client to write to
    await expectLater(address.connect(), throwsA(isA<SocketException>()));
  });

  test('a client without the token gets nothing', () async {
    final sink = LogSink()..add(record('secret'));
    final address = await sink.serve(directory: dir.path);
    addTearDown(sink.close);
    final client = await Client.connect(address, 'guess');
    await client.closed;
    expect(client.records, isEmpty);
  });

  test("a newer app's address file is left alone", () async {
    final older = LogSink();
    final newer = LogSink();
    await older.serve(directory: dir.path);
    final address = await newer.serve(directory: dir.path);
    await older.close();
    expect(LocalAddress.read(LocalAddress.fileOf('logs', dir.path)), address);
    await newer.close();
  });
}
