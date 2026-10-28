import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:twk/twk.dart';
import 'package:twk_ssh/twk_ssh.dart';
import 'package:twk_test/twk_test.dart';

import 'support.dart';

/// A terminal at the client's end of a shell: what the server writes is
/// fed to an emulator, and the probe's DA1 is answered as a terminal
/// does, so the app starts at once.
final class RemoteTerminal {
  RemoteTerminal._(this.shell, int columns, int rows) : vt = Vt(columns, rows) {
    shell.stdout.listen(_feed);
  }

  /// A shell of [client] on a terminal of [term], [columns] by [rows].
  static Future<RemoteTerminal> open(
    SSHClient client, {
    int columns = 100,
    int rows = 30,
    String term = 'xterm-256color',
    Map<String, String> environment = const {},
  }) async => RemoteTerminal._(
    await client.shell(
      pty: SSHPtyConfig(type: term, width: columns, height: rows),
      environment: environment,
    ),
    columns,
    rows,
  );

  final SSHSession shell;
  final Vt vt;

  /// Everything the server wrote, as Latin-1.
  final written = StringBuffer();
  var _answered = 0;

  void _feed(Uint8List bytes) {
    written.write(latin1.decode(bytes));
    vt.feed(bytes);
    final asked = '\x1b[c'.allMatches('$written').length;
    for (; _answered < asked; _answered++) {
      shell.write(utf8.encode('\x1b[?62;22c'));
    }
  }

  /// Types [text].
  void type(String text) => shell.write(utf8.encode(text));

  /// The client's window becomes [columns] by [rows].
  void resize(int columns, int rows) {
    vt.resize(columns, rows);
    shell.resizeTerminal(columns, rows);
  }

  /// Waits until a line of the screen contains [text].
  Future<void> shows(String text) => waitUntil(
    () => vt.lines.any((line) => line.contains(text)),
    '"$text" on the screen:\n${vt.lines.join('\n')}',
  );

  /// The status the session exited with.
  Future<int?> exited() async {
    await waitFor(shell.done, 'the session to end');
    return shell.exitCode;
  }
}

/// The app of the tests: who logged in, the terminal's size, a count
/// that Up raises; q quits. Its binding goes to [bound] as it is built.
final class Probe extends StatefulWidget {
  const Probe(this.session, {required this.disposed, this.bound, super.key});

  final SshSession session;
  final Completer<void> disposed;
  final void Function(AppBinding binding)? bound;

  @override
  State<Probe> createState() => _ProbeState();
}

final class _ProbeState extends State<Probe> {
  var _n = 0;

  @override
  void dispose() {
    widget.disposed.complete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.bound?.call(AppBinding.of(context));
    return _keys();
  }

  Widget _keys() => KeyBindings(
    {
      'up': () => setState(() => _n++),
      'q': () => AppBinding.of(context).quit(),
      'x': () => throw StateError('x pressed'),
    },
    child: LayoutBuilder(
      builder: (context, size) => Text(
        'user ${widget.session.user} ${size.maxW}x${size.maxH} count $_n',
      ),
    ),
  );
}

void main() {
  final alice = ClientKey.ed25519();
  final bob = ClientKey.ed25519();

  late List<SshSession> sessions;
  late List<Completer<void>> disposed;
  late List<Object> errors;
  late Set<AppBinding> bindings;

  setUp(() {
    bindings = {};
    sessions = [];
    disposed = [];
    errors = [];
  });

  Future<SshServer> start(List<ClientKey> keys) async {
    final server = await serveSsh(
      port: 0,
      hostKeys: [hostKey],
      authenticate: acceptKeys(keys),
      app: (session) {
        sessions.add(session);
        final done = Completer<void>();
        disposed.add(done);
        return Probe(session, disposed: done, bound: bindings.add);
      },
      onError: (e, _) => errors.add(e),
    );
    addTearDown(server.close);
    return server;
  }

  test(
    'a key logs in; the app gets the user, the size, TERM and the env',
    () async {
      final server = await start([alice]);
      final client = await connect(server, identities: [alice.pair]);
      final remote = await RemoteTerminal.open(
        client,
        term: 'xterm-kitty',
        environment: {'COLORTERM': 'truecolor', 'LANG': 'C.UTF-8'},
      );
      await remote.shows('user alice 100x30 count 0');
      final link = SshTerminalLink(sessions.single);
      expect(link.environment, {
        'COLORTERM': 'truecolor',
        'LANG': 'C.UTF-8',
        'TERM': 'xterm-kitty',
      });
      // the probe went out over the session, and the app is fullscreen
      expect('${remote.written}', contains('\x1b[c'));
      expect('${remote.written}', contains('\x1b[?1049h'));
      expect(errors, isEmpty);
    },
  );

  test('keys typed reach the app; a resize lays it out again', () async {
    final server = await start([alice]);
    final client = await connect(server, identities: [alice.pair]);
    final remote = await RemoteTerminal.open(client);
    await remote.shows('count 0');
    remote.type('\x1b[A\x1b[A');
    await remote.shows('100x30 count 2');
    remote.resize(60, 20);
    await remote.shows('60x20 count 2');
  });

  test('q quits: the terminal is restored, the channel closes with status 0, '
      'the app is unmounted', () async {
    final server = await start([alice]);
    final client = await connect(server, identities: [alice.pair]);
    final remote = await RemoteTerminal.open(client);
    await remote.shows('count 0');
    remote.type('q');
    expect(await remote.exited(), 0);
    await waitFor(disposed.single.future, 'the app to be unmounted');
    await waitFor(sessions.single.done, 'the session to be over');
    final written = '${remote.written}';
    expect(
      written.lastIndexOf('\x1b[?1049l'),
      greaterThan(written.lastIndexOf('\x1b[?1049h')),
    );
    expect(remote.vt.cursorVisible, isTrue);
    expect(remote.vt.errors, isEmpty);
    expect(errors, isEmpty);
  });

  test('two sessions at once each have an app of their own', () async {
    final server = await start([alice, bob]);
    final a = await RemoteTerminal.open(
      await connect(server, identities: [alice.pair]),
    );
    final b = await RemoteTerminal.open(
      await connect(server, user: 'bob', identities: [bob.pair]),
      columns: 70,
      rows: 10,
    );
    await a.shows('user alice 100x30 count 0');
    await b.shows('user bob 70x10 count 0');
    a.type('\x1b[A\x1b[A\x1b[A');
    b.type('\x1b[A');
    await a.shows('count 3');
    await b.shows('count 1');
    b.resize(80, 12);
    await b.shows('80x12 count 1');
    a.type('q');
    expect(await a.exited(), 0);
    // bob's goes on
    b.type('\x1b[A');
    await b.shows('80x12 count 2');
    expect(a.vt.lines.first, contains('100x30 count 3'));
    b.type('q');
    expect(await b.exited(), 0);
  });

  test(
    'a key the server does not take is refused, and no app is built',
    () async {
      final server = await start([alice]);
      final client = await connect(server, identities: [bob.pair]);
      await expectLater(
        client.authenticated,
        throwsA(isA<SSHAuthFailError>()),
      );
      expect(sessions, isEmpty);
    },
  );

  test('a session without a terminal is told so and exits with 1', () async {
    final server = await start([alice]);
    final client = await connect(server, identities: [alice.pair]);
    final run = await client.execute('count');
    final out = readUntil(run.stdout, (_) => false);
    await waitFor(run.done, 'the command to end');
    expect(run.exitCode, 1);
    expect(await out, contains('needs a terminal'));
    expect(sessions, isEmpty);
  });

  test('a client that goes away ends its app, with no error', () async {
    final server = await start([alice]);
    final client = await connect(server, identities: [alice.pair]);
    final remote = await RemoteTerminal.open(client);
    await remote.shows('count 0');
    unawaited(client.close());
    await waitFor(disposed.single.future, 'the app to be unmounted');
    await waitFor(sessions.single.done, 'the session to be over');
    expect(errors, isEmpty);
    await waitUntil(() => server.connections.isEmpty, 'the connection to go');
  });

  test(
    'an app that ends with an error exits with 1, the error to onError',
    () async {
      final server = await start([alice]);
      final client = await connect(server, identities: [alice.pair]);
      final remote = await RemoteTerminal.open(client);
      await remote.shows('count 0');
      remote.type('x');
      expect(await remote.exited(), 1);
      expect(errors, [isA<WidgetError>()]);
      final written = '${remote.written}';
      expect(
        written.lastIndexOf('\x1b[?1049l'),
        greaterThan(written.lastIndexOf('\x1b[?1049h')),
      );
    },
  );

  test("the client's environment sets none of twk's own settings, nor "
      "does the server process's: the app's environment is empty", () async {
    final server = await start([alice]);
    final client = await connect(server, identities: [alice.pair]);
    const asks = {
      'TWK_DEBUG': 'frames,overlay,console',
      'TWK_SCREEN_READER': '1',
      'TWK_EDITOR': 'vi {file}',
    };
    final remote = await RemoteTerminal.open(client, environment: asks);
    await remote.shows('count 0');
    // no frame statistics written beside the app: only the app shows
    expect(remote.vt.lines.where((l) => l.trim().isNotEmpty), [
      'user alice 100x30 count 0',
    ]);
    expect(sessions.single.environment, asks);
    final binding = bindings.single;
    expect(binding.twkApp.environment, isEmpty);
    expect(binding.twkApp.debugNames, isEmpty);
    expect(binding.twkApp.terminal.info.settings, isEmpty);
    expect(
      (binding.screenReader, binding.debug.keys, binding.debug.overlay),
      (false, false, false),
    );
  });

  test('a builder that throws: status 1, the error to onError', () async {
    final server = await serveSsh(
      port: 0,
      hostKeys: [hostKey],
      authenticate: acceptKeys([alice]),
      app: (_) => throw StateError('no app'),
      onError: (e, _) => errors.add(e),
    );
    addTearDown(server.close);
    final client = await connect(server, identities: [alice.pair]);
    final remote = await RemoteTerminal.open(client);
    expect(await remote.exited(), 1);
    expect(errors, [isA<StateError>()]);
    // the terminal was never opened: nothing was asked of it
    expect('${remote.written}', isEmpty);
  });

  test('a link refuses a session without a terminal', () async {
    final seen = Completer<SshSession>();
    final server = await serve(
      auth: acceptKeys([alice]),
      onSession: (session) async {
        seen.complete(session);
        await session.exit();
      },
    );
    final client = await connect(server, identities: [alice.pair]);
    await client.execute('x');
    final session = await seen.future;
    expect(() => SshTerminalLink(session), throwsArgumentError);
  });

  group('ssh(1)', () {
    final haveSsh = onPath('ssh') && onPath('ssh-keygen');
    late Directory dir;
    late String keyPath;
    late SshPublicKey key;

    setUpAll(() async {
      if (!haveSsh) {
        return;
      }
      dir = Directory.systemTemp.createTempSync('twk_ssh_serve');
      keyPath = '${dir.path}/id_ed25519';
      final made = await sshKeygen([
        ...['-q', '-t', 'ed25519', '-N', '', '-f', keyPath],
      ]);
      expect(made?.exitCode, 0, reason: '${made?.stderr}');
      key = SshPublicKey.parse(File('$keyPath.pub').readAsStringSync())!;
    });
    tearDownAll(() {
      if (haveSsh) {
        dir.deleteSync(recursive: true);
      }
    });

    test(
      'ssh -tt runs the app, which quits with status 0',
      skip: haveSsh ? false : 'ssh(1) or ssh-keygen is not installed',
      () async {
        final server = await serveSsh(
          port: 0,
          hostKeys: [hostKey],
          authenticate: SshAuth(publicKey: (_, k) => k == key),
          app: (session) {
            sessions.add(session);
            final done = Completer<void>();
            disposed.add(done);
            return Probe(session, disposed: done);
          },
          onError: (e, _) => errors.add(e),
        );
        addTearDown(server.close);
        final process = await startProcess(
          'ssh',
          [
            ...['-tt', '-F', '/dev/null', '-q', '-p', '${server.port}'],
            ...['-i', keyPath, '-o', 'StrictHostKeyChecking=no'],
            ...[
              '-o',
              'UserKnownHostsFile=/dev/null',
              '-o',
              'IdentitiesOnly=yes',
            ],
            ...['-o', 'IdentityAgent=none', '-o', 'BatchMode=yes'],
            ...['-o', 'LogLevel=ERROR', 'carol@127.0.0.1'],
          ],
          environment: {'TERM': 'xterm-256color'},
        );
        final written = StringBuffer();
        var answered = false;
        final shown = Completer<void>();
        final out = process.stdout.listen((bytes) {
          written.write(latin1.decode(bytes));
          if (!answered && '$written'.contains('\x1b[c')) {
            answered = true;
            process.stdin.add(utf8.encode('\x1b[?62;22c'));
          }
          if (!shown.isCompleted && '$written'.contains('count 0')) {
            shown.complete();
          }
        });
        final err = process.stderr.transform(utf8.decoder).join();
        // without a terminal of its own ssh sends a size of 0: 80 by 24
        await waitFor(shown.future, 'the app on the screen');
        expect('$written', contains('user carol 80x24 count 0'));
        expect(sessions.single.pty!.term, 'xterm-256color');
        process.stdin.add(utf8.encode('q'));
        final code = await waitFor(process.exitCode, 'ssh to end');
        await out.cancel();
        expect(code, 0, reason: await err);
        expect('$written', contains('\x1b[?1049l'));
        expect(errors, isEmpty);
      },
    );
  });
}
