// The wire between an app and a twk shell where it breaks: frames cut
// across reads and too long, a shell that doesn't answer or isn't there,
// flushes left waiting, an app that speaks no hello or an unknown frame;
// and the addresses they meet at.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/terminal/socket.dart';
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart'
    show compiledProgram, runProcess, startProcess, waitUntil;

import 'fake_link.dart';
import 'wire_client.dart';

/// A server at a new address in [dir] that hands each connection to
/// [accept]; closed when the test ends.
Future<LocalAddress> listen(
  Directory dir,
  void Function(Socket socket) accept,
) async {
  final (server, address) = await LocalAddress.bind(dir.path, 'shell');
  server.listen(accept);
  addTearDown(() async {
    await server.close();
    address.unlink();
  });
  return address;
}

/// A server whose shell welcomes an app and answers no flush: the
/// connections it took, to cut.
Future<(LocalAddress, List<Socket>)> silentShell(Directory dir) async {
  final sockets = <Socket>[];
  final address = await listen(dir, (socket) {
    sockets.add(socket);
    socket
      ..listen((_) {}, onError: (Object _) {})
      ..add(
        jsonFrame(Wire.welcome, {
          'columns': 10,
          'lines': 2,
          'eraseChar': 0x7F,
          'windows': false,
          'environment': <String, String>{},
        }),
      );
  });
  return (address, sockets);
}

void main() {
  // the app run in a process of its own, compiled once
  late String socketApp;
  setUpAll(
    () async => socketApp = await compiledProgram(
      'test/terminal/socket_app.dart',
      packages: (await Isolate.packageConfig)!.toFilePath(),
      cache: '.dart_tool/twk_test/programs',
    ),
  );

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('twk_wire'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('FrameReader', () {
    test('cuts frames out whatever the reads split them into, one bigger '
        'than its buffer too', () {
      final big = Uint8List.fromList(List.generate(10000, (i) => i % 251));
      final bytes = [
        ...frame(Wire.output, big),
        ...frame(Wire.flush),
        ...frame(Wire.raw, const [1]),
      ];
      final frames = <(int, List<int>)>[];
      final reader = FrameReader(
        (type, payload) => frames.add((type, payload)),
      );
      for (var i = 0; i < bytes.length; i += 7) {
        reader.add(
          bytes.sublist(i, i + 7 > bytes.length ? bytes.length : i + 7),
        );
      }
      expect(frames.map((f) => f.$1), [Wire.output, Wire.flush, Wire.raw]);
      expect(frames[0].$2, big);
      expect(frames[1].$2, isEmpty);
      expect(frames[2].$2, [1]);
    });

    test('takes a read more than twice as long as its buffer at once', () {
      final big = Uint8List.fromList(List.generate(20000, (i) => i % 251));
      final frames = <(int, List<int>)>[];
      FrameReader((type, payload) => frames.add((type, payload)))
        ..add([
          ...frame(Wire.raw, const [1]),
        ])
        ..add([...frame(Wire.output, big), ...frame(Wire.flush)]);
      expect(frames.map((f) => f.$1), [Wire.raw, Wire.output, Wire.flush]);
      expect(frames[1].$2, big);
    });

    test('reads on after a frame longer than its buffer, the frames whole '
        'and their payloads their own', () {
      final big = Uint8List.fromList(List.generate(20000, (i) => i % 251));
      final frames = <(int, List<int>)>[];
      final reader = FrameReader((type, payload) => frames.add((type, payload)))
        ..add(frame(Wire.output, big))
        ..add(frame(Wire.raw, const [1]));
      final split = frame(Wire.output, const [7, 8, 9]);
      reader
        ..add(split.sublist(0, 3))
        ..add(split.sublist(3));
      expect(frames.map((f) => f.$1), [Wire.output, Wire.raw, Wire.output]);
      expect(frames[0].$2, big);
      expect(frames[1].$2, [1]);
      expect(frames[2].$2, [7, 8, 9]);
    });

    test('refuses a frame longer than the wire takes', () {
      final reader = FrameReader((_, _) => fail('no frame'));
      expect(
        () => reader.add(frameHeader(Wire.output, Wire.maxPayload + 1)),
        throwsFormatException,
      );
    });
  });

  group('SocketLink', () {
    test('a shell that sends a frame too long is gone: connecting '
        'fails', () async {
      final address = await listen(dir, (socket) {
        socket
          ..listen((_) {}, onError: (Object _) {})
          ..add(frameHeader(Wire.welcome, Wire.maxPayload + 1));
      });
      await expectLater(
        SocketLink.connect(address),
        throwsA(
          isA<TerminalException>().having(
            (e) => e.message,
            'message',
            startsWith('the shell sent'),
          ),
        ),
      );
    });

    test("a shell that doesn't answer the hello in time: connecting "
        'fails', () async {
      final address = await listen(dir, (socket) {
        socket.listen((_) {}, onError: (Object _) {});
      });
      await expectLater(
        SocketLink.connect(
          address,
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(
          isA<TerminalException>().having(
            (e) => e.message,
            'message',
            'the shell did not answer',
          ),
        ),
      );
    });

    test("an address file of a shell that isn't there any more: no "
        'shell', () async {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
      final (server, address) = await LocalAddress.bind(
        LocalAddress.directoryOf(dir.path),
        'shell',
      );
      await address.write(LocalAddress.fileOf('shell', dir.path));
      await server.close();
      address.unlink();
      expect(await SocketLink.toShell(dir.path), isNull);
    });

    test('a flush left waiting completes when the shell goes away; what '
        'is written then is dropped', () async {
      final (address, sockets) = await silentShell(dir);
      final link = await SocketLink.connect(address);
      final errors = <Object>[];
      link.input.listen(null, onError: errors.add);
      final waiting = link.flush();
      sockets.single.destroy();
      await waiting;
      await waitUntil(() => errors.isNotEmpty, 'the input ended');
      expect(errors.single, isA<TerminalException>());
      link.add(const [1, 2, 3]);
      await link.flush();
      await link.close();
    });

    test('a flush left waiting completes when the link is closed', () async {
      final (address, _) = await silentShell(dir);
      final link = await SocketLink.connect(address);
      link.input.listen(null);
      final flush = link.flush();
      await link.close();
      await flush;
    });

    test('closes when nobody listened to its input', () async {
      final (address, _) = await silentShell(dir);
      final link = await SocketLink.connect(address);
      await link.close().timeout(const Duration(seconds: 5));
    });
  });

  test("Terminal.open that fails at the project's twk shell (a trace "
      "file that can't be written) throws, and the shell's terminal is put "
      'back', () async {
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    final link = FakeLink();
    final file = LocalAddress.fileOf('shell', dir.path);
    final (server, address) = await LocalAddress.bind(
      LocalAddress.directoryOf(dir.path),
      'shell',
    );
    await address.write(file);
    final shell = TerminalShell.serve(link, server, address, file: file);
    addTearDown(shell.stop);
    final process = await startProcess(
      Platform.resolvedExecutable,
      [socketApp],
      workingDirectory: dir.path,
      environment: {'TWK_TRACE_OUTPUT': '${dir.path}/missing/out.trace'},
    );
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdout.listen(null);
    final code = await process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () => fail('Terminal.open did not end'),
    );
    expect(code, isNot(0));
    expect(await stderr, contains('PathNotFoundException'));
    await waitUntil(() => !shell.serving, 'the app gone');
    expect(link.raw, isFalse);
    expect(link.text, isEmpty);
  });

  group('TerminalShell', () {
    late FakeLink link;
    late TerminalShell shell;
    late List<ShellEvent> events;

    setUp(() async {
      link = FakeLink();
      events = [];
      final (server, address) = await LocalAddress.bind(dir.path, 'shell');
      shell = TerminalShell.serve(link, server, address, onEvent: events.add);
    });
    tearDown(() => shell.stop());

    test('says a line on the terminal', () {
      shell.say('waiting for an app\r\n');
      expect(link.text, 'waiting for an app\r\n');
    });

    test('a hello that is no JSON is refused', () async {
      final app = await WireClient.connect(shell.address);
      app.send(Wire.hello, utf8.encode('{not json'));
      await app.closed;
      expect(app.frames.single.$1, Wire.refused);
      expect(utf8.decode(app.frames.single.$2), 'no hello');
      expect(events, isEmpty);
    });

    test('an app that sends a frame of no known type is cut off, and the '
        'terminal put back', () async {
      final app = await WireClient.connect(shell.address);
      app
        ..hello(shell.address.token)
        ..send(Wire.lost, latin1.encode('<restore>'));
      await app.sync();
      app.send(99);
      await app.closed;
      expect(link.text, '<restore>');
      expect(link.raw, isFalse);
      expect(events, [ShellEvent.connected, ShellEvent.disconnected]);
    });

    test('an app that sends a frame too long is cut off', () async {
      final app = await WireClient.connect(shell.address);
      app.hello(shell.address.token);
      await app.sync();
      app.socket.add(frameHeader(Wire.output, Wire.maxPayload + 1));
      await app.closed;
      expect(events, [ShellEvent.connected, ShellEvent.disconnected]);
      expect(link.raw, isFalse);
    });

    test('stopping cuts off an app that has not said hello yet', () async {
      final silent = await WireClient.connect(shell.address);
      // taken after the silent one: once it has the terminal, the silent
      // one waits for its hello
      final app = await WireClient.connect(shell.address);
      app.hello(shell.address.token);
      await app.sync();
      await shell.stop();
      await silent.closed.timeout(
        TerminalShell.helloTimeout ~/ 2,
        onTimeout: () => fail('still connected'),
      );
      expect(silent.frames, isEmpty);
    });

    test('stops once: stopping again waits for the first', () async {
      final first = shell.stop();
      final again = shell.stop();
      await Future.wait([first, again]);
      expect(link.closed, isTrue);
      await shell.stop();
    });
  });

  group('LocalAddress', () {
    test('a directory with no pubspec.yaml above it is its own project', () {
      final deep = Directory('${dir.path}/a/b')..createSync(recursive: true);
      expect(LocalAddress.projectOf(deep.path), deep.path);
    });

    test('a socket left behind by a process that ended without closing it '
        'is replaced', () async {
      final path = '${dir.path}/svc.sock';
      // a socket bound and never closed: python's leaves its file
      final res = await runProcess('python3', [
        '-c',
        'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])',
        path,
      ]);
      expect(res.exitCode, 0, reason: '${res.stderr}');
      expect(
        FileSystemEntity.typeSync(path),
        FileSystemEntityType.unixDomainSock,
      );
      final (server, address) = await LocalAddress.bind(dir.path, 'svc');
      addTearDown(server.close);
      final accepted = server.first;
      final client = await address.connect();
      await accepted;
      client.destroy();
    }, testOn: '!windows');

    test('on one line for TWK_SHELL: the address, then the token after '
        'the last #', () {
      final unix = LocalAddress(
        InternetAddress('/run/a#b/x.sock', type: InternetAddressType.unix),
        0,
        'abc',
      );
      expect(unix.toVariable(), 'unix:/run/a#b/x.sock#abc');
      expect(LocalAddress.fromVariable(unix.toVariable()), unix);
      final tcp = LocalAddress(InternetAddress.loopbackIPv4, 4567, 'xyz');
      expect(tcp.toVariable(), 'tcp:127.0.0.1:4567#xyz');
      expect(LocalAddress.fromVariable(tcp.toVariable()), tcp);
      expect(LocalAddress.shellVariable, 'TWK_SHELL');
      for (final nothing in [
        '',
        'unix:/run/x.sock',
        'unix:/run/x.sock#',
        '#abc',
        'unix:#abc',
        'tcp:127.0.0.1#abc',
        'tcp:nohost:1#abc',
        'unix:/run/x\n.sock#abc',
        'unix:/run/x.sock#ab\rc',
        '/run/x.sock#abc',
      ]) {
        expect(LocalAddress.fromVariable(nothing), isNull, reason: nothing);
      }
    });

    test('equal addresses hash alike; one prints where it is, not its '
        'token', () {
      LocalAddress unix(String token) => LocalAddress(
        InternetAddress('/run/x.sock', type: InternetAddressType.unix),
        0,
        token,
      );
      expect(unix('abc').hashCode, unix('abc').hashCode);
      expect({unix('abc'), unix('abc'), unix('xyz')}, hasLength(2));
      expect('${unix('abc')}', 'unix:/run/x.sock');
      expect(
        '${LocalAddress(InternetAddress.loopbackIPv4, 4242, 'abc')}',
        'tcp:127.0.0.1:4242',
      );
    });
  });
}
