// `twk logs`: the records of a served sink as the command prints them,
// the command tailing one app after another, and the project it names.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_dev/src/logs.dart' show colorsLevels;
import 'package:twk_dev/twk_dev.dart';

final _at = DateTime(2026, 10, 19, 9, 5, 7, 42);

/// SO_LINGER, of SOL_SOCKET on Linux.
const _soLinger = 13;

/// The lines of a text as it comes, kept in [lines]; [waitFor] waits for
/// one that matches.
final class Lines {
  Lines(Stream<String> text) {
    text.transform(const LineSplitter()).listen((line) {
      lines.add(line);
      for (final w in [..._waits]) {
        if (w.$1(line)) {
          _waits.remove(w);
          w.$2.complete();
        }
      }
    });
  }

  final lines = <String>[];
  final _waits = <(bool Function(String), Completer<void>)>[];

  Future<void> waitFor(Pattern pattern) {
    bool match(String line) => line.contains(pattern);
    if (lines.any(match)) {
      return Future.value();
    }
    final done = Completer<void>();
    _waits.add((match, done));
    return done.future.timeout(const Duration(seconds: 30));
  }
}

/// `twk logs` with [arguments], run by [runTwk] in an isolate of this test
/// until the test ends: the lines it writes to stdout and to stderr, as
/// they come. An error it does not catch fails the test. Its stdout is a
/// terminal, one that takes escape sequences, with [terminal].
///
/// It is the command `dart run twk_dev:twk` runs, without a process: that
/// builds the executable first whenever a package it depends on changed,
/// which on a busy machine takes most of the test's timeout.
Future<(Lines, Lines)> startLogs(
  List<String> arguments, {
  bool terminal = false,
}) async {
  final out = StreamController<String>();
  final err = StreamController<String>();
  final port = ReceivePort()
    ..listen((message) {
      switch (message) {
        case (1, final String text):
          out.add(text);
        case (2, final String text):
          err.add(text);
        case [final error, final stack]:
          // an error the command did not catch, sent by the isolate
          registerException(
            'twk logs failed: $error',
            StackTrace.fromString('$stack'),
          );
      }
    });
  final isolate = await Isolate.spawn(_logs, (
    port.sendPort,
    ['logs', ...arguments],
    terminal,
  ), onError: port.sendPort);
  addTearDown(() async {
    isolate.kill(priority: Isolate.immediate);
    port.close();
    await out.close();
    await err.close();
  });
  return (Lines(out.stream), Lines(err.stream));
}

/// Runs `twk` on the arguments, its stdout and stderr sent to the port,
/// a terminal or not.
Future<void> _logs((SendPort, List<String>, bool) message) {
  final (port, arguments, terminal) = message;
  return IOOverrides.runZoned(
    () => runTwk(arguments),
    stdout: () => _Sent(port, 1, terminal: terminal),
    stderr: () => _Sent(port, 2, terminal: terminal),
  );
}

/// A stdout or a stderr whose text goes to [_port], tagged with [_fd]; a
/// terminal that takes escape sequences, with [terminal].
final class _Sent implements Stdout {
  _Sent(this._port, this._fd, {required this.terminal});

  final SendPort _port;
  final int _fd;
  final bool terminal;

  @override
  bool get hasTerminal => terminal;

  @override
  bool get supportsAnsiEscapes => terminal;

  @override
  void write(Object? object) => _port.send((_fd, '$object'));

  @override
  void writeln([Object? object = '']) => _port.send((_fd, '$object\n'));

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('stdout.${invocation.memberName}');
}

void main() {
  test('a record: time, level padded, message and error, then the stack; '
      'colored by level', () {
    final record = LogRecord(
      _at,
      LogLevel.warning,
      'slow',
      error: 'took 3 s',
      stack: StackTrace.fromString('#0 main\n#1 run\n'),
    );
    expect(
      formatRecord(record, color: false),
      '09:05:07.042 warning slow: took 3 s\n#0 main\n#1 run',
    );
    expect(
      formatRecord(LogRecord(_at, LogLevel.info, 'hi'), color: false),
      '09:05:07.042 info    hi',
    );
    const dim = '\x1b[2m';
    const yellow = '\x1b[33m';
    const off = '\x1b[0m';
    expect(
      formatRecord(record, color: true),
      '${dim}09:05:07.042$off ${yellow}warning$off slow$yellow: took 3 s$off'
      '\n$dim#0 main$off\n$dim#1 run$off',
    );
    expect(formatLine('not json', color: true), 'not json');
  });

  test('a line of the log is its record, as formatRecord writes it; a line '
      'that is no record is itself', () {
    final record = LogRecord(_at, LogLevel.error, 'failed', error: 'disk');
    expect(
      formatLine(jsonEncode(record.toJson()), color: false),
      '09:05:07.042 error   failed: disk',
    );
    expect(formatLine('[1, 2]', color: false), '[1, 2]');
    expect(formatLine('{"level": 9}', color: false), '{"level": 9}');
  });

  test('debug is dim and error bold red', () {
    expect(
      formatRecord(LogRecord(_at, LogLevel.debug, 'x'), color: true),
      '\x1b[2m09:05:07.042\x1b[0m \x1b[2mdebug  \x1b[0m x',
    );
    expect(
      formatRecord(LogRecord(_at, LogLevel.error, 'x'), color: true),
      '\x1b[2m09:05:07.042\x1b[0m \x1b[1;31merror  \x1b[0m x',
    );
  });

  test('twk logs waits for an app, prints the records it kept and each '
      'one as it comes, and waits for the next app when it ends', () async {
    final dir = Directory.systemTemp.createTempSync('twk_logs');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    final (out, err) = await startLogs(['-C', dir.path, '--no-color']);
    await err.waitFor('waiting for an app of ${dir.path}');

    final sink = LogSink()
      ..add(LogRecord(_at, LogLevel.info, 'kept'))
      ..add(LogRecord(_at, LogLevel.error, 'failed', error: 'bad'));
    await sink.serve(directory: dir.path);
    await out.waitFor('failed');
    sink.add(LogRecord(_at, LogLevel.debug, 'live'));
    await out.waitFor('live');
    expect(out.lines, [
      '09:05:07.042 info    kept',
      '09:05:07.042 error   failed: bad',
      '09:05:07.042 debug   live',
    ]);

    await sink.close();
    await err.waitFor('the app ended');
    final next = LogSink()..add(LogRecord(_at, LogLevel.info, 'next app'));
    await next.serve(directory: dir.path);
    addTearDown(next.close);
    await out.waitFor('next app');
  });

  test('twk logs finds the project of a directory given relative and with '
      'dot segments, and names it by its absolute path, normalised', () async {
    final dir = Directory.systemTemp.createTempSync('twk_logs');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    // a project inside it, which `packages/inner/..` is not in
    Directory('${dir.path}/packages/inner').createSync(recursive: true);
    File(
      '${dir.path}/packages/inner/pubspec.yaml',
    ).writeAsStringSync('name: inner\n');
    final relative = p.relative(dir.path);
    final (_, err) = await startLogs([
      '-C',
      p.join(relative, '.', 'packages', 'inner', '..'),
      '--no-color',
    ]);
    await err.waitFor('waiting for an app');
    expect(err.lines, [
      'twk logs: waiting for an app of ${p.normalize(dir.absolute.path)}',
    ]);
  });

  test('twk logs colors the levels on a terminal whose environment takes '
      'colors and more than plain text, as twk_core tells', () {
    bool colors(Map<String, String> env, {bool terminal = true}) =>
        colorsLevels(env, outputIsTerminal: terminal);
    expect(colors({}), isTrue);
    expect(colors({}, terminal: false), isFalse);
    expect(colors({'NO_COLOR': '1'}), isFalse);
    expect(colors({'NO_COLOR': ''}), isTrue);
    expect(colors({'TERM': 'dumb'}), isFalse);
    expect(colors({'TWK_PLAIN': '1'}), isFalse);
    expect(colors({'BUILD_NUMBER': '7'}), isFalse);
    expect(colors({'CI': 'true'}), isFalse);
    expect(colors({'CI': 'true', 'TWK_PLAIN': '0'}), isTrue);
  });

  test('twk logs colors the records where stdout is a terminal that takes '
      'colors, else not, unless --color or --no-color says', () async {
    final dir = Directory.systemTemp.createTempSync('twk_logs');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    final record = LogRecord(_at, LogLevel.error, 'failed');
    final sink = LogSink()..add(record);
    await sink.serve(directory: dir.path);
    addTearDown(sink.close);
    // what the core tells of this process's environment
    final env = Platform.environment;
    final takesColors =
        colorModeFor(env) != ColorMode.none &&
        !(plainAsked(env) ?? runsInCi(env));

    for (final (options, terminal, color) in [
      (<String>[], false, false),
      (<String>[], true, takesColors),
      (['--color'], false, true),
      (['--no-color'], true, false),
    ]) {
      final (out, _) = await startLogs([
        '-C',
        dir.path,
        ...options,
      ], terminal: terminal);
      await out.waitFor('failed');
      expect(
        out.lines,
        [formatRecord(record, color: color)],
        reason: '$options, a terminal: $terminal',
      );
    }
  });

  test('twk logs takes an app that resets the connection for one that '
      'ended, and waits for the next', () async {
    final dir = Directory.systemTemp.createTempSync('twk_logs');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    // an app on TCP whose socket resets each connection once it has the
    // token: SO_LINGER on, 0 s
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final linger = Uint8List(8)
      ..buffer.asByteData().setInt32(0, 1, Endian.host);
    server.listen((socket) {
      socket.setRawOption(
        RawSocketOption(RawSocketOption.levelSocket, _soLinger, linger),
      );
      socket.listen((_) => socket.destroy(), onError: (Object _) {});
    });
    LocalAddress(
      server.address,
      server.port,
      'token',
    ).write(LocalAddress.fileOf('logs', dir.path));

    final (_, err) = await startLogs(['-C', dir.path, '--no-color']);
    await err.waitFor('the app ended');
    await server.close();
    await err.waitFor('waiting for an app');
  }, testOn: 'linux');
}
