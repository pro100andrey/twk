// A terminal over a local socket: an app on Terminal.connect against a
// shell side spoken by hand, TerminalShell serving a terminal in memory,
// TerminalShell.start serving a pseudo-terminal (shell_app.dart), the
// address files, and Terminal.open finding the project's shell from a
// process of its own (socket_app.dart), also on a terminal whose raw mode
// can't be entered.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:twk_core/src/terminal/link.dart' show TerminalDeclaration;
import 'package:twk_core/src/terminal/socket.dart';
import 'package:twk_core/src/terminal/terminal.dart' show openOwnOrShell;
import 'package:twk_core/twk_core.dart';
import 'package:twk_test/twk_test.dart'
    show compiledProgram, runProcess, waitUntil;
import 'package:twk_test/vt.dart';

import 'fake_link.dart';
import 'wire_client.dart';

/// The shell's end spoken by hand: answers the hello with its size and
/// environment, the probe's DA1 query with DA1, and each flush unless
/// [holdFlushes]; keeps what the app wrote and every frame.
final class HandShell {
  HandShell._(this._server, this.address) {
    _server.listen((socket) {
      _socket = socket;
      final reader = FrameReader(_onFrame);
      socket.listen(
        reader.add,
        onError: (Object _) {},
        onDone: () {
          if (!_closed.isCompleted) {
            _closed.complete();
          }
        },
      );
    });
  }

  static Future<HandShell> start(String directory) async {
    final (server, address) = await LocalAddress.bind(directory, 'shell');
    return HandShell._(server, address);
  }

  final ServerSocket _server;
  final LocalAddress address;
  Socket? _socket;
  final _closed = Completer<void>();

  var columns = 30;
  var lines = 5;
  final environment = {'TERM': 'xterm-kitty', 'NO_COLOR': '1'};

  /// The welcome's `declares`, left out when null.
  Object? declares;
  var holdFlushes = false;

  /// Every frame from the app, in order.
  final frames = <(int, Uint8List)>[];

  /// The flushes not answered yet.
  var unanswered = 0;

  /// What the app wrote to the terminal.
  final output = BytesBuilder();

  String get text => latin1.decode(output.toBytes());

  /// Completes when the app closes the connection.
  Future<void> get closed => _closed.future;

  void _onFrame(int type, Uint8List payload) {
    frames.add((type, payload));
    switch (type) {
      case Wire.hello:
        _sendJson(Wire.welcome, {
          'columns': columns,
          'lines': lines,
          'eraseChar': 0x7F,
          'windows': false,
          'environment': environment,
          'declares': ?declares,
        });
      case Wire.output:
        output.add(payload);
        if (latin1.decode(payload).contains('\x1b[c')) {
          input('\x1b[?62c'); // DA1: the probe's answers are in
        }
      case Wire.flush:
        if (holdFlushes) {
          unanswered++;
        } else {
          _socket!.add(frame(Wire.flushed));
        }
    }
  }

  void _sendJson(int type, Object json) => _socket!.add(jsonFrame(type, json));

  /// The terminal's input.
  void input(String text) => _socket!.add(frame(Wire.input, utf8.encode(text)));

  /// The terminal was resized.
  void resize(int columns, int lines) =>
      _sendJson(Wire.size, {'columns': columns, 'lines': lines});

  void answerFlushes() {
    for (; unanswered > 0; unanswered--) {
      _socket!.add(frame(Wire.flushed));
    }
  }

  /// The shell goes away.
  void kill() => _socket!.destroy();

  Future<void> close() async {
    _socket?.destroy();
    await _server.close();
    address.unlink();
  }

  /// The types of the frames from the app, in order, outputs and flushes
  /// left out.
  List<int> get controlTypes => [
    for (final (type, _) in frames)
      if (type != Wire.output && type != Wire.flush) type,
  ];

  /// The payload of the last frame of [type].
  Uint8List last(int type) => frames.lastWhere((f) => f.$1 == type).$2;
}

/// The mouse modes [text] turns on and off, `?1002h` and the like, in
/// order.
List<String> mouseModes(String text) => [
  for (final m in RegExp(r'\x1b\[\?(100[0236])([hl])').allMatches(text))
    '?${m[1]}${m[2]}',
];

/// One line of text at the top left.
RenderText textOf(TwkApp app, String text) =>
    RenderText(text, app.screen.styles.pen(const Pen()));

void main() {
  // the programs run in processes of their own, compiled once
  late String shellApp;
  late String socketApp;
  setUpAll(() async {
    final packages = (await Isolate.packageConfig)!.toFilePath();
    const cache = '.dart_tool/twk_test/programs';
    shellApp = await compiledProgram(
      'test/terminal/shell_app.dart',
      packages: packages,
      cache: cache,
    );
    socketApp = await compiledProgram(
      'test/terminal/socket_app.dart',
      packages: packages,
      cache: cache,
    );
  });

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('twk_socket'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('an app on Terminal.connect', () {
    late HandShell shell;
    setUp(() async => shell = await HandShell.start(dir.path));
    tearDown(() => shell.close());

    test('opens with the token, takes the size and environment of the '
        "shell's terminal, enters raw mode before writing", () async {
      final term = await Terminal.connect(shell.address);
      final hello = jsonDecode(
        utf8.decode(shell.frames.first.$2),
      ) as Map<String, Object?>;
      expect(hello, {'protocol': Wire.protocol, 'token': shell.address.token});
      expect(shell.frames[1].$1, Wire.raw);
      expect(shell.frames[1].$2, [1]);
      expect((term.width, term.height), (30, 5));
      // the shell's NO_COLOR and TERM, not this process's
      expect(term.info.colorMode, ColorMode.none);
      expect(term.info.notifications, NotificationProtocol.osc99);
      expect(term.info.answeredQueries, isTrue);
      await term.close();
    });

    test('frames reach the terminal, input and resizes reach the app, and '
        'close restores the terminal and ends the connection', () async {
      final term = await Terminal.connect(shell.address);
      final app = TwkApp(term, maxFps: 1000, environment: const {});
      final events = <InputEvent>[];
      final done = app.run(textOf(app, 'hello'), events.add);
      await waitUntil(() => shell.text.contains('hello'), 'the first frame');
      final vt = Vt(30, 5, strict: false)..feed(shell.output.toBytes());
      expect(vt.lines.first, 'hello');

      shell.input('x');
      await waitUntil(() => events.isNotEmpty, 'the key');
      expect(events, [const KeyEvent(KeyCode.char, char: 'x')]);

      shell.resize(40, 6);
      await waitUntil(() => events.length > 1, 'the resize');
      expect(events.last, const ResizeEvent(40, 6));
      expect((term.width, term.height), (40, 6));

      final restore = latin1.decode(shell.last(Wire.lost));
      expect(restore, contains('\x1b[?1049l'), reason: 'leaves the alt screen');
      app.quit();
      await done;
      await shell.closed;
      expect(shell.text, endsWith(restore));
      expect(shell.last(Wire.lost), isEmpty, reason: 'restored itself');
      expect(shell.controlTypes.last, Wire.raw);
      expect(shell.last(Wire.raw), [0]);
    });

    test("TWK_SCREEN_READER and TWK_DEBUG of the shell's environment are "
        "the app's, over the process's; the rest of it is not", () async {
      shell.environment.addAll({
        'TWK_DEBUG': 'frames,rainbow',
        'TWK_SCREEN_READER': '1',
        'TWK_LOG': '/nowhere/shell.log',
      });
      final term = await Terminal.connect(shell.address);
      expect(term.info.settings, {
        'TWK_DEBUG': 'frames,rainbow',
        'TWK_SCREEN_READER': '1',
      });
      final app = TwkApp(term);
      expect(app.debugNames, {'frames', 'rainbow'});
      expect(app.framesInRow, isTrue);
      expect(app.owner.debugRepaintRainbow, isTrue);
      expect(app.environment['TWK_SCREEN_READER'], '1');
      expect(
        app.environment['TWK_LOG'],
        Platform.environment['TWK_LOG'],
        reason: "the process's",
      );
      expect(
        TwkApp(term, environment: const {}).debugNames,
        isEmpty,
        reason: 'an environment given is the whole of it',
      );
      await term.close();
    });

    test("what the shell's welcome declares the terminal does is the "
        "app's over the guess by TERM; what it declares wrong, or not at "
        'all, is guessed', () async {
      shell.declares = {
        'notifications': 'osc777',
        'progressReports': true,
        'pointerShapes': false,
        'repeatChar': false,
        'graphics': 'iterm2',
      };
      final term = await Terminal.connect(shell.address);
      final info = term.info;
      expect(info.notifications, NotificationProtocol.osc777);
      expect(info.progressReports, isTrue);
      expect(info.pointerShapes, isFalse);
      expect(info.caps.repeatChar, isFalse);
      expect(info.caps.graphics, GraphicsProtocol.iterm2);
      await term.close();

      // TERM=xterm-kitty: OSC 99, pointer shapes and REP
      for (final declares in <Object?>[
        null,
        {'notifications': 'bell', 'pointerShapes': 'no', 'repeatChar': 0},
        [true],
        'osc777',
      ]) {
        final again = await HandShell.start(dir.createTempSync().path);
        again.declares = declares;
        final guessed = await Terminal.connect(again.address);
        expect(guessed.info.notifications, NotificationProtocol.osc99);
        expect(guessed.info.pointerShapes, isTrue, reason: '$declares');
        expect(guessed.info.caps.repeatChar, isTrue, reason: '$declares');
        await guessed.close();
        await again.close();
      }
    });

    test('a flush completes once the shell has written what came '
        'before it', () async {
      final term = await Terminal.connect(shell.address);
      shell.holdFlushes = true;
      term.write(Uint8List.fromList('abc'.codeUnits));
      var flushed = false;
      final flush = term.flush().then((_) => flushed = true);
      await waitUntil(() => shell.unanswered > 0, 'the flush');
      expect((flushed, shell.unanswered), (false, 1));
      shell.answerFlushes();
      await flush;
      expect(shell.text, endsWith('abc'));
      shell.holdFlushes = false;
      await term.close();
    });

    test('the title pushed is popped by what puts the terminal back', () async {
      final term = await Terminal.connect(shell.address)
        ..setTitle('app');
      await term.flush();
      expect(latin1.decode(shell.last(Wire.lost)), endsWith(popTitleSequence));
      await term.close();
    });

    test('mouse reports switched while open are written at once and turned '
        'off by what puts the terminal back: when suspended, a switch '
        'meanwhile written when resumed, and at close', () async {
      final term = await Terminal.connect(
        shell.address,
        const TerminalOptions(mouse: false),
      );
      await term.flush();
      expect(term.mouseTracking, MouseTracking.off);
      expect(mouseModes(shell.text), isEmpty);
      List<String> lost() => mouseModes(latin1.decode(shell.last(Wire.lost)));
      expect(lost(), isEmpty);

      var from = shell.output.length;
      List<String> since() => mouseModes(shell.text.substring(from));
      term.mouseTracking = MouseTracking.buttons;
      await term.flush();
      expect(since(), ['?1000h', '?1006h']);
      expect(lost(), ['?1000l', '?1006l']);

      from = shell.output.length;
      term.mouseTracking = MouseTracking.motion;
      await term.flush();
      expect(since(), ['?1000l', '?1003h']);
      expect(lost(), ['?1003l', '?1006l']);

      from = shell.output.length;
      await term.suspend();
      term.mouseTracking = MouseTracking.drags;
      await term.flush();
      expect(since(), ['?1003l', '?1006l']);

      from = shell.output.length;
      await term.resume();
      await term.flush();
      expect(since(), ['?1002h', '?1006h']);
      expect(lost(), ['?1002l', '?1006l']);

      from = shell.output.length;
      await term.close();
      term.mouseTracking = MouseTracking.motion;
      await shell.closed;
      expect(since(), ['?1002l', '?1006l']);
      expect(term.mouseTracking, MouseTracking.drags, reason: 'closed');
    });

    test("the inline mode keeps the mouse the terminal's: a switch is "
        'ignored', () async {
      final term = await Terminal.connect(
        shell.address,
        const TerminalOptions(alternateScreen: false),
      );
      term.mouseTracking = MouseTracking.motion;
      await term.flush();
      expect(term.mouseTracking, MouseTracking.off);
      expect(mouseModes(shell.text), isEmpty);
      await term.close();
    });

    test('suspended, the terminal is put back and the console modes too; '
        'resumed, both are taken again', () async {
      final term = await Terminal.connect(shell.address);
      await term.suspend();
      await term.flush();
      expect(shell.last(Wire.lost), isEmpty);
      expect(shell.last(Wire.raw), [0]);
      await term.resume();
      await term.flush();
      expect(latin1.decode(shell.last(Wire.lost)), contains('\x1b[?1049l'));
      expect(shell.last(Wire.raw), [1]);
      await term.close();
    });

    test(
      'the shell going away ends the run with a TerminalException',
      () async {
        final term = await Terminal.connect(shell.address);
        final app = TwkApp(term, maxFps: 1000, environment: const {});
        final done = app.run(textOf(app, 'hello'), (_) {});
        await waitUntil(() => shell.text.contains('hello'), 'the first frame');
        shell.kill();
        await expectLater(
          done,
          throwsA(
            isA<TerminalException>().having(
              (e) => e.message,
              'message',
              contains('shell'),
            ),
          ),
        );
      },
    );

    test('nobody listening: a SocketException', () async {
      await shell.close();
      await expectLater(
        Terminal.connect(shell.address),
        throwsA(isA<SocketException>()),
      );
    });
  });

  test(
    'a shell closing while an app connects is no shell to the app',
    () async {
      // The connect is reset (ECONNRESET), which dart:io throws as an
      // OSError of its own, not a SocketException, when the server closes
      // between the connect and its answer: most of the time, so a few tries
      // reach it. The rest connect, and are refused once the server is gone.
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
      final file = LocalAddress.fileOf('shell', dir.path);
      var reset = 0;
      for (var i = 0; i < 200 && reset < 3; i++) {
        final (server, address) = await LocalAddress.bind(
          LocalAddress.directoryOf(dir.path),
          'shell',
        );
        address.write(file);
        final link = SocketLink.toShell(dir.path);
        // real time on purpose: a race of the connect against the close,
        // which no clock decides; the tries are what makes it bounded
        await Future<void>.delayed(Duration.zero);
        await server.close();
        try {
          expect(await link, isNull);
          reset++;
        } on TerminalException {
          // connected before the close: refused after it
        }
      }
      expect(reset, 3);
    },
    // macOS and Windows queue the connect before the close and reset what
    // follows it, never the connect: the race is Linux's
    testOn: 'linux',
  );

  test('a connect reset by a server closing is a SocketException', () async {
    // dart:io throws the reset (ECONNRESET) as a bare OSError
    var failed = 0;
    for (var i = 0; i < 200 && failed < 3; i++) {
      final (server, address) = await LocalAddress.bind(dir.path, 'reset');
      final connecting = address.connect().then<Object>(
        (socket) => socket,
        onError: (Object e) => e,
      );
      // real time on purpose: a race of the connect against the close,
      // which no clock decides; the tries are what makes it bounded
      await Future<void>.delayed(Duration.zero);
      await server.close();
      switch (await connecting) {
        case final Socket socket:
          socket.destroy();
        case final error:
          expect(error, isA<SocketException>());
          failed++;
      }
      address.unlink();
    }
    expect(failed, 3);
    // the reset of the connect: Linux's, as above
  }, testOn: 'linux');

  group('TerminalShell', () {
    late FakeLink link;
    late TerminalShell shell;
    late List<ShellEvent> events;
    late String file;

    setUp(() async {
      link = FakeLink();
      events = [];
      file = '${dir.path}/shell';
      final (server, address) = await LocalAddress.bind(dir.path, 'shell');
      address.write(file);
      shell = TerminalShell.serve(
        link,
        server,
        address,
        file: file,
        onEvent: events.add,
      );
    });
    tearDown(() => shell.stop());

    test('serves its terminal to an app: raw mode while the app has it, '
        'input and sizes passed on, frames written, put back as the app '
        'leaves it when it closes', () async {
      final term = await Terminal.connect(
        shell.address,
        const TerminalOptions(probeTimeout: Duration(milliseconds: 50)),
      );
      expect(link.raw, isTrue);
      expect(events, [ShellEvent.connected]);
      expect((term.width, term.height), (20, 4));
      final app = TwkApp(term, maxFps: 1000, environment: const {});
      final got = <InputEvent>[];
      final done = app.run(textOf(app, 'served'), got.add);
      await waitUntil(() => link.text.contains('served'), 'the first frame');
      expect(
        (Vt(20, 4, strict: false)..feed(link.output.toBytes())).lines.first,
        'served',
      );

      link.type('q');
      await waitUntil(() => got.isNotEmpty, 'the key');
      link.resize(25, 6);
      await waitUntil(() => got.length > 1, 'the resize');
      expect(got, [
        const KeyEvent(KeyCode.char, char: 'q'),
        const ResizeEvent(25, 6),
      ]);

      app.quit();
      await done;
      await waitUntil(() => !shell.serving, 'the app gone');
      expect(link.rawChanges, [true, false]);
      expect(link.text, endsWith('\x1b[?1049l'), reason: 'nothing after it');
      expect(events, [ShellEvent.connected, ShellEvent.disconnected]);
      expect(shell.serving, isFalse);
    });

    test('welcomes each app with what its terminal declares, and with no '
        'declares where it declares nothing', () async {
      Future<Map<String, Object?>> welcomed(TerminalShell shell) async {
        final app = await WireClient.connect(shell.address)
          ..hello(shell.address.token);
        await waitUntil(() => app.frames.isNotEmpty, 'the welcome');
        app.socket.destroy();
        final (type, payload) = app.frames.first;
        expect(type, Wire.welcome);
        return jsonDecode(utf8.decode(payload)) as Map<String, Object?>;
      }

      expect(await welcomed(shell), isNot(contains('declares')));

      final declaring = FakeLink(
        declaration: const TerminalDeclaration(
          notifications: NotificationProtocol.osc777,
          repeatChar: true,
        ),
      );
      final (server, address) = await LocalAddress.bind(
        dir.createTempSync().path,
        'shell',
      );
      final other = TerminalShell.serve(declaring, server, address);
      try {
        expect((await welcomed(other))['declares'], {
          'notifications': 'osc777',
          'repeatChar': true,
        });
      } finally {
        await other.stop();
        address.unlink();
      }
    });

    test('an app that goes away without restoring the terminal: what it '
        'said puts the terminal back; of a frame cut short nothing is '
        'written', () async {
      final app = await WireClient.connect(shell.address);
      app
        ..hello(shell.address.token)
        ..send(Wire.output, latin1.encode('<frame>'))
        ..send(Wire.lost, latin1.encode('<restore>'));
      await app.sync();
      expect(app.frames.first.$1, Wire.welcome);
      final cut = frame(Wire.output, latin1.encode('\x1b[?2026h<next>'));
      app.socket.add(cut.sublist(0, cut.length - 3));
      await app.socket.flush();
      app.socket.destroy();
      await waitUntil(() => events.length > 1, 'the app gone');
      expect(link.text, '<frame><restore>');
      expect(link.raw, isFalse);
      expect(events, [ShellEvent.connected, ShellEvent.disconnected]);
    });

    test('a newer app takes the terminal over: the older one is '
        'disconnected and the terminal put back for it first', () async {
      final first = await WireClient.connect(shell.address);
      first
        ..hello(shell.address.token)
        ..send(Wire.lost, latin1.encode('<first>'));
      await first.sync();
      final second = await WireClient.connect(shell.address);
      second.hello(shell.address.token);
      await first.closed;
      await waitUntil(() => second.frames.isNotEmpty, 'the welcome');
      expect(second.frames.first.$1, Wire.welcome);
      expect(link.text, '<first>');
      expect(events, [
        ShellEvent.connected,
        ShellEvent.disconnected,
        ShellEvent.connected,
      ]);
      expect(link.rawChanges, [true, false, true]);

      link.type('k');
      await waitUntil(() => second.frames.length > 1, 'the key');
      expect(second.frames.last.$1, Wire.input);
      expect(utf8.decode(second.frames.last.$2), 'k');
      second.socket.destroy();
    });

    test('a wrong token or protocol is refused, and the terminal left '
        'alone', () async {
      final wrong = await WireClient.connect(shell.address);
      wrong.hello('not the token');
      await wrong.closed;
      expect(wrong.frames.single.$1, Wire.refused);
      final newer = await WireClient.connect(shell.address);
      newer.hello(shell.address.token, protocol: Wire.protocol + 1);
      await newer.closed;
      expect(
        utf8.decode(newer.frames.single.$2),
        contains('protocol ${Wire.protocol + 1}'),
      );
      expect(link.rawChanges, isEmpty);
      expect(events, isEmpty);
      expect(link.text, isEmpty);

      await expectLater(
        Terminal.connect(
          LocalAddress(shell.address.address, shell.address.port, 'x'),
        ),
        throwsA(isA<TerminalException>()),
      );
    });

    test(
      'input while no app has the terminal in raw mode is dropped',
      () async {
        link.type('before');
        final app = await WireClient.connect(shell.address);
        app
          ..hello(shell.address.token)
          ..send(Wire.raw, const [0]);
        await app.sync();
        link.type('cooked');
        await app.sync();
        app.send(Wire.raw, const [1]);
        await app.sync();
        link.type('raw');
        List<String> inputs() => [
          for (final (type, payload) in app.frames)
            if (type == Wire.input) utf8.decode(payload),
        ];
        await waitUntil(() => inputs().isNotEmpty, 'the input');
        expect(inputs(), ['raw']);
        app.socket.destroy();
      },
    );

    test('stop disconnects the app, puts the terminal back and forgets the '
        'address file and the socket', () async {
      final app = await WireClient.connect(shell.address);
      app
        ..hello(shell.address.token)
        ..send(Wire.lost, latin1.encode('<restore>'));
      await app.sync();
      await shell.stop();
      await app.closed;
      expect(link.text, '<restore>');
      expect((link.raw, link.closed), (false, true));
      expect(File(file).existsSync(), isFalse);
      expect(File(shell.address.address.address).existsSync(), isFalse);
      await expectLater(
        shell.address.connect(),
        throwsA(isA<SocketException>()),
      );
    });
  });

  test('TerminalShell.start without a terminal: not a terminal', () async {
    // stdin and stdout are pipes, whatever runs the test
    await expectLater(
      IOOverrides.runZoned(
        () => TerminalShell.start(directory: dir.path),
        stdin: _PipeIn.new,
        stdout: _PipeOut.new,
      ),
      throwsA(
        isA<TerminalException>().having(
          (e) => e.message,
          'message',
          'not a terminal',
        ),
      ),
    );
    expect(Directory('${dir.path}/.dart_tool').existsSync(), isFalse);
  });

  test(
    "TerminalShell.start in a pseudo-terminal serves it to the project's "
    'apps, in place of a shell that went away, and refuses a second '
    'shell',
    () async {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
      // the address file of a shell that went away without forgetting it
      final file = LocalAddress.fileOf('shell', dir.path);
      final (gone, left) = await LocalAddress.bind(
        LocalAddress.directoryOf(dir.path),
        'shell',
      );
      left.write(file);
      await gone.close();
      left.unlink();
      final out = '${dir.path}/out.bin';
      final res = await runProcess(
        'python3',
        [
          File('../../tool/pty_run.py').absolute.path,
          // what a loaded machine may take to start the app, run and end it
          '--timeout',
          '120',
          '--input',
          'none',
          '--out',
          out,
          '--',
          Platform.resolvedExecutable,
          shellApp,
        ],
        workingDirectory: dir.path,
        group: true,
      );
      final said = '${res.stdout}${res.stderr}';
      expect(res.exitCode, 0, reason: said);
      // the project's directory as the app finds it, its links resolved
      // (macOS's /var is /private/var)
      expect(
        said,
        contains(
          'a second shell: a twk shell serves '
          '${dir.resolveSymbolicLinksSync()} already',
        ),
      );
      expect(said, contains('the app got 100x30'));
      expect(said, contains('the shell heard: connected, disconnected'));
      expect(File(out).readAsStringSync(), contains('from the app'));
      expect(File(file).existsSync(), isFalse);
    },
    testOn: 'linux || mac-os',
    timeout: const Timeout(Duration(minutes: 3)),
  );

  group('LocalAddress', () {
    test('an address file holds the socket and the token', () {
      final unix = LocalAddress(
        InternetAddress('/run/x.sock', type: InternetAddressType.unix),
        0,
        'abc',
      );
      expect(unix.encode(), 'unix:/run/x.sock\nabc\n');
      expect(LocalAddress.decode(unix.encode()), unix);
      final tcp = LocalAddress(InternetAddress.loopbackIPv4, 4242, 'abc');
      expect(tcp.encode(), 'tcp:127.0.0.1:4242\nabc\n');
      expect(LocalAddress.decode(tcp.encode()), tcp);
      for (final bad in ['', 'unix:/x', 'udp:1.2.3.4:5\nt', 'tcp:x:1\nt']) {
        expect(LocalAddress.decode(bad), isNull, reason: bad);
      }
    });

    test("a project's address files are beside its pubspec.yaml", () {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
      final deep = Directory('${dir.path}/lib/src')
        ..createSync(recursive: true);
      expect(LocalAddress.projectOf(deep.path), dir.path);
      final s = Platform.pathSeparator;
      expect(
        LocalAddress.fileOf('shell', deep.path),
        '${dir.path}$s.dart_tool${s}twk${s}shell',
      );
    });

    test('a socket path too long for the OS goes to a temporary '
        'directory, removed with it', () async {
      final long = '${dir.path}/${'d' * 120}';
      final (server, address) = await LocalAddress.bind(long, 'shell');
      final path = address.address.address;
      expect(path, startsWith(Directory.systemTemp.path));
      expect(utf8.encode(path).length, lessThanOrEqualTo(103));
      await server.close();
      address.unlink();
      expect(Directory(File(path).parent.path).existsSync(), isFalse);
    }, testOn: '!windows');

    test('unlinking again, with the socket and its temporary directory gone '
        'already, does nothing', () async {
      final long = '${dir.path}/${'d' * 120}';
      final (server, address) = await LocalAddress.bind(long, 'shell');
      await server.close();
      address.unlink();
      expect(address.unlink, returnsNormally);
    }, testOn: '!windows');

    test('forget leaves an address file a newer server wrote', () async {
      final file = '${dir.path}/shell';
      final (s1, older) = await LocalAddress.bind(dir.path, 'a');
      final (s2, newer) = await LocalAddress.bind(dir.path, 'b');
      older.write(file);
      newer.write(file);
      older.forget(file);
      expect(LocalAddress.read(file), newer);
      newer.forget(file);
      expect(LocalAddress.read(file), isNull);
      await s1.close();
      await s2.close();
    });
  });

  test(
    "Terminal.open without a terminal finds the project's twk shell",
    () async {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
      final link = FakeLink(columns: 33, lines: 7);
      final file = LocalAddress.fileOf('shell', dir.path);
      final (server, address) = await LocalAddress.bind(
        LocalAddress.directoryOf(dir.path),
        'shell',
      );
      address.write(file);
      final shell = TerminalShell.serve(link, server, address, file: file);
      addTearDown(shell.stop);
      final res = await runProcess(
        Platform.resolvedExecutable,
        [socketApp],
        workingDirectory: dir.path,
        // not plain, as an app in CI is, whose log this may be
        environment: {'CI': 'false'},
      );
      expect(res.stderr, '');
      expect(res.stdout, 'opened 33x7\n');
      expect(res.exitCode, 0);
      expect(link.text, contains('from the app'));
      expect(link.rawChanges, [true, false]);
    },
  );

  test('Terminal.open without a terminal or a shell, plain output refused '
      '(TWK_PLAIN=0): not a terminal', () async {
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
    final res = await runProcess(
      Platform.resolvedExecutable,
      [socketApp],
      workingDirectory: dir.path,
      environment: {'TWK_PLAIN': '0'},
    );
    expect(res.stdout, 'TerminalException: not a terminal\n');
  });

  group('TWK_SHELL', () {
    /// The project [dir] with an address file naming a shell that serves
    /// [projects]; a second shell, at an address in no file, serving
    /// [named]: its TWK_SHELL value.
    Future<String> twoShells(FakeLink projects, FakeLink named) async {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
      final file = LocalAddress.fileOf('shell', dir.path);
      final (server, address) = await LocalAddress.bind(
        LocalAddress.directoryOf(dir.path),
        'shell',
      );
      address.write(file);
      final shell = TerminalShell.serve(projects, server, address, file: file);
      addTearDown(shell.stop);
      final (other, at) = await LocalAddress.bind('${dir.path}/other', 'x');
      final second = TerminalShell.serve(named, other, at);
      addTearDown(second.stop);
      return at.toVariable();
    }

    test('Terminal.open without a terminal takes the shell it names, not '
        "the project's", () async {
      final projects = FakeLink(columns: 33, lines: 7);
      final named = FakeLink(columns: 41, lines: 9);
      final variable = await twoShells(projects, named);
      final res = await runProcess(
        Platform.resolvedExecutable,
        [socketApp],
        workingDirectory: dir.path,
        environment: {'TWK_SHELL': variable, 'CI': 'false'},
      );
      expect(res.stderr, '');
      expect(res.stdout, 'opened 41x9\n');
      expect(named.text, contains('from the app'));
      expect(projects.text, isEmpty);
    });

    test('naming a shell where nobody listens: no terminal, and not the '
        "project's", () async {
      final projects = FakeLink();
      await twoShells(projects, FakeLink());
      final (gone, at) = await LocalAddress.bind('${dir.path}/gone', 'x');
      await gone.close();
      at.unlink();
      final res = await runProcess(
        Platform.resolvedExecutable,
        [socketApp],
        workingDirectory: dir.path,
        environment: {'TWK_SHELL': at.toVariable(), 'TWK_PLAIN': '0'},
      );
      expect(
        res.stdout,
        startsWith('TerminalException: no twk shell at TWK_SHELL ($at): '),
      );
      expect(res.stdout, isNot(contains(at.token)));
      expect(projects.text, isEmpty);
    });

    test(
      'naming nothing it takes: no terminal, saying what it takes',
      () async {
        final projects = FakeLink();
        await twoShells(projects, FakeLink());
        final res = await runProcess(
          Platform.resolvedExecutable,
          [socketApp],
          workingDirectory: dir.path,
          environment: {'TWK_SHELL': '/tmp/shell.sock', 'TWK_PLAIN': '0'},
        );
        expect(
          res.stdout,
          'TerminalException: TWK_SHELL names no twk shell: it is '
          'unix:<path>#<token> or tcp:<host>:<port>#<token>\n',
        );
        expect(projects.text, isEmpty);
      },
    );

    test("empty: the project's shell, as when it is not set", () async {
      final projects = FakeLink(columns: 33, lines: 7);
      await twoShells(projects, FakeLink());
      final res = await runProcess(
        Platform.resolvedExecutable,
        [socketApp],
        workingDirectory: dir.path,
        environment: {'TWK_SHELL': '', 'CI': 'false'},
      );
      expect(res.stdout, 'opened 33x7\n');
    });

    test('is read from the environment openOwnOrShell is given only', () async {
      final projects = FakeLink(columns: 33, lines: 7);
      final named = FakeLink(columns: 41, lines: 9);
      final variable = await twoShells(projects, named);
      const options = TerminalOptions(
        probeTimeout: Duration(milliseconds: 50),
      );
      final own = FakeLink(refusesRaw: true);
      final term = await openOwnOrShell(own, options, dir.path, {
        'TWK_SHELL': variable,
      });
      expect((term.width, term.height), (41, 9));
      await term.close();
      final theProjects = await openOwnOrShell(
        FakeLink(refusesRaw: true),
        options,
        dir.path,
      );
      expect((theProjects.width, theProjects.height), (33, 7));
      await theProjects.close();
    });
  });

  group("a terminal whose raw mode can't be entered (stdin from /dev/null, "
      'which dart:io takes for a terminal)', () {
    const options = TerminalOptions(probeTimeout: Duration(milliseconds: 50));

    test("gives way to the project's twk shell", () async {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
      final shell = await HandShell.start(dir.path);
      addTearDown(shell.close);
      shell.address.write(LocalAddress.fileOf('shell', dir.path));
      final own = FakeLink(refusesRaw: true);
      final term = await openOwnOrShell(own, options, dir.path);
      expect((term.width, term.height), (30, 5));
      term.write(Uint8List.fromList('from the app'.codeUnits));
      await term.close();
      expect(shell.text, contains('from the app'));
      expect(own.output.isEmpty, isTrue);
      expect(own.closed, isTrue);
    });

    test('without a shell: not a terminal', () async {
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
      final own = FakeLink(refusesRaw: true);
      await expectLater(
        openOwnOrShell(own, options, dir.path),
        throwsA(
          isA<TerminalException>().having(
            (e) => e.message,
            'message',
            'not a terminal',
          ),
        ),
      );
      expect(own.closed, isTrue);
    });

    test(
      "an app run so in a pseudo-terminal finds the project's twk "
      'shell',
      () async {
        File('${dir.path}/pubspec.yaml').writeAsStringSync('name: app\n');
        final link = FakeLink(columns: 33, lines: 7);
        final file = LocalAddress.fileOf('shell', dir.path);
        final (server, address) = await LocalAddress.bind(
          LocalAddress.directoryOf(dir.path),
          'shell',
        );
        address.write(file);
        final shell = TerminalShell.serve(link, server, address, file: file);
        addTearDown(shell.stop);
        final out = '${dir.path}/out.bin';
        final res = await runProcess(
          'python3',
          [
            File('../../tool/pty_run.py').absolute.path,
            '--input',
            'none',
            '--out',
            out,
            '--',
            'sh',
            '-c',
            r'exec "$0" "$1" </dev/null',
            Platform.resolvedExecutable,
            socketApp,
          ],
          workingDirectory: dir.path,
          group: true,
        );
        expect(res.exitCode, 0, reason: '${res.stdout}');
        expect(File(out).readAsStringSync(), 'opened 33x7\r\n');
        expect(link.text, contains('from the app'));
        expect(link.rawChanges, [true, false]);
        // pty_run.py, sh and /dev/null
      },
      timeout: const Timeout(Duration(minutes: 3)),
      testOn: 'linux || mac-os',
    );
  });
}

/// A stdin that is a pipe: no terminal.
final class _PipeIn extends Stream<List<int>> implements Stdin {
  @override
  bool get hasTerminal => false;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<List<int>>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('stdin.${invocation.memberName}');
}

/// A stdout that is a pipe: no terminal.
final class _PipeOut implements Stdout {
  @override
  bool get hasTerminal => false;

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('stdout.${invocation.memberName}');
}
