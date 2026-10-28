// `twk run`: an app of a package made for the test, run by the command,
// hot reloaded as its sources change and as its keys ask, its state kept;
// a reload that fails to compile said in the app's console, the app going
// on; a restart that starts it again; the app's exit code the command's.
//
// The app draws on a terminal in memory and sends each frame as a line of
// base64, which the test feeds an emulator, and takes what it is sent as
// the terminal's input. The command runs in this process (`TwkHere`), the
// app talking to the test over a socket; where the test needs a process
// of the command's own (a signal sent to it, what the app writes to the
// stdio `twk run` leaves it), it is started as a developer starts it, and
// the app uses its stdin and stdout.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:twk_dev/src/run.dart';
import 'package:twk_dev/twk_dev.dart' show runTwk;
import 'package:twk_test/twk_test.dart' show runProcess, waitFor, waitUntil;
import 'package:twk_test/vt.dart';

import 'twk.dart';

/// The app's `main`, under its [footer].
///
/// It draws on a terminal in memory and sends each frame as a line of
/// base64, the terminal's input what it is sent: over a socket to the
/// test with `--port=<port>` first, the port the test listens on, which
/// it is sent its pid on first; else on stdout, from stdin, which `twk run`
/// leaves it. With `--wait` it says it waits, and runs the app on the
/// first input, which it keeps from it; with `--kill` it kills itself.
String _main(String footer) =>
    '''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hot_app/counter.dart';
import 'package:twk/twk.dart';

import 'heading.dart';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty && args.first.startsWith('--port=')
      ? int.parse(args.first.substring(7))
      : null;
  final socket = port == null
      ? null
      : await Socket.connect(InternetAddress.loopbackIPv4, port);
  final Stream<List<int>> from = socket ?? stdin;
  final IOSink to = socket ?? stdout;
  to.writeln('pid \$pid');
  if (args.contains('--kill')) {
    Process.killPid(pid, ProcessSignal.sigkill);
  }
  final term = HeadlessTerminal(width: 60, height: 14);
  final go = Completer<void>();
  final input = from.listen(
    (bytes) => go.isCompleted ? term.input(bytes) : go.complete(),
  );
  if (args.contains('--wait')) {
    to.writeln('the app waits');
    await go.future;
  } else {
    go.complete();
  }
  var sent = 0;
  void send() {
    for (; sent < term.frames.length; sent++) {
      to.writeln(base64.encode(term.frames[sent]));
    }
  }

  final frames = Timer.periodic(const Duration(milliseconds: 20), (_) => send());
  await runApp(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [Heading(), Counter(), Footer()],
    ),
    terminal: term,
  );
  send();
  frames.cancel();
  await to.flush();
  await input.cancel();
  socket?.destroy();
}

final class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) => const Text('$footer');
}
''';

const _heading = '''
import 'package:twk/twk.dart';

final class Heading extends StatelessWidget {
  const Heading({super.key});

  @override
  Widget build(BuildContext context) => const Text('first heading');
}
''';

/// A counter that `+` adds one to, shown after [word]; with [broken] a
/// semicolon left out.
String _counter(String word, {bool broken = false}) =>
    '''
import 'package:twk/twk.dart';

final class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

final class _CounterState extends State<Counter> {
  var _count = 0;

  @override
  Widget build(BuildContext context) => InputListener(
    onEvent: (event) {
      if (event is! KeyEvent || event.char != '+') {
        return false;
      }
      setState(() => _count++)${broken ? '' : ';'}
      return true;
    },
    child: Text('$word \$_count'),
  );
}
''';

/// How long an app is given to start: `dart run` compiles it, twk with
/// it, which on a busy machine takes most of a minute.
const _start = Duration(seconds: 90);

/// What the app shows, from the frames it sends: on the stdout of a
/// `twk run` ([_Screen.of]), or over the sockets of the apps a `twk run`
/// in this process starts, one after another ([_Screen.serve]).
final class _Screen {
  /// The screen of the app whose frames are on [stdout].
  _Screen.of(Stream<List<int>> stdout) : _server = null {
    unawaited(_read(stdout).then((_) => _done.complete()));
  }

  _Screen._(ServerSocket server) : _server = server {
    server.listen((socket) {
      _socket = socket;
      _ends.add(_read(socket));
    });
  }

  /// Listens for the apps, which [port] is given to; closes in the
  /// tear-down.
  static Future<_Screen> serve() async {
    final screen = _Screen._(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    addTearDown(screen._close);
    return screen;
  }

  final ServerSocket? _server;
  Socket? _socket;

  // when the connection of each app ended, in the order they connected
  final _ends = <Future<void>>[];

  /// Waits until the [n]th app to connect (from 0) has ended: closed its
  /// connection.
  Future<void> ended(int n) => _ends[n].timeout(
    const Duration(seconds: 10),
    onTimeout: () => fail('app $n did not end'),
  );

  /// The port the apps connect to: what `--port=` gives them.
  int get port => _server!.port;

  /// The pids of the apps, as each said.
  final pids = <int>[];

  final _done = Completer<void>();

  /// Completes when stdout is closed: by every process that had it.
  Future<void> get done => _done.future;

  final _vt = Vt(60, 14);
  final _other = <String>[];
  final _waits = <(Pattern, Completer<void>)>[];

  Future<void> _read(Stream<List<int>> bytes) => utf8.decoder
      .bind(bytes)
      .transform(const LineSplitter())
      .forEach((line) {
        if (line.startsWith('pid ')) {
          pids.add(int.parse(line.substring(4)));
          return;
        }
        try {
          _vt.feed(base64.decode(line));
        } on FormatException {
          _other.add(line);
        }
        _check();
      })
      .catchError((Object _) {});

  /// Types [keys]: sends them to the app connected last.
  void type(String keys) => _socket!.add(utf8.encode(keys));

  /// The rows shown, the blanks that end them left out.
  List<String> get rows => [
    for (var y = 0; y < _vt.height; y++)
      [for (var x = 0; x < _vt.width; x++) _vt.cell(x, y).text]
          .join()
          .trimRight(),
  ];

  /// Waits until a row shows [pattern], [within] a time.
  Future<void> waitFor(
    Pattern pattern, {
    Duration within = const Duration(seconds: 30),
  }) {
    final done = Completer<void>();
    _waits.add((pattern, done));
    _check();
    return done.future.timeout(
      within,
      onTimeout: () => fail(
        'no row shows $pattern:\n${rows.join('\n')}\n'
        'besides frames: ${_other.join('\n')}',
      ),
    );
  }

  /// Waits until the app says [line], not a frame, [within] a time.
  Future<void> said(
    String line, {
    Duration within = const Duration(seconds: 30),
  }) => waitUntil(
    () => _other.contains(line),
    'the app to say "$line"',
    timeout: within,
  );

  void _check() {
    final shown = rows;
    for (final w in [..._waits]) {
      if (shown.any((row) => row.contains(w.$1))) {
        _waits.remove(w);
        w.$2.complete();
      }
    }
  }

  Future<void> _close() async {
    _socket?.destroy();
    await _server?.close();
  }
}

/// `twk run` of [entry] in this process, the app given [screen]'s port and
/// [arguments]; in the tear-down the command's runner is stopped
/// ([HotRunner.stop]), which ends the app it started, and the command
/// awaited. [started] is given the command's runner before it starts the
/// app.
TwkHere _runHere(
  String entry,
  _Screen screen, [
  List<String> arguments = const [],
  void Function(HotRunner runner)? started,
]) {
  HotRunner? runner;
  var tornDown = false;
  final run = TwkHere.start(
    ['run', entry, '--port=${screen.port}', ...arguments],
    twk: (args) => _twkRun(args, (r) {
      runner = r;
      if (tornDown) {
        // before it starts any app: it starts none
        unawaited(r.stop());
      }
      started?.call(r);
    }),
  );
  addTearDown(() async {
    tornDown = true;
    await waitFor(
      runner?.stop() ?? Future<void>.value(),
      'twk run to end the app and itself: ${run.err}',
      timeout: const Duration(seconds: 20),
    );
    await waitFor(
      run.exitCode,
      'twk run to end: ${run.err}',
      timeout: const Duration(seconds: 20),
    );
  });
  return run;
}

/// The `twk` command with `run` alone, whose runner [started] is given:
/// what [runTwk] does with these [arguments].
Future<int> _twkRun(
  List<String> arguments,
  void Function(HotRunner runner) started,
) async =>
    await (CommandRunner<int>(
      'twk',
      'twk run alone.',
    )..addCommand(RunCommand(started: started))).run(arguments) ??
    0;

/// A package made for a test, in a temporary directory: `lib/counter.dart`
/// with `count`, `bin/heading.dart` and `bin/main.dart`, the app.
final class _Project {
  _Project._(this.dir);

  static Future<_Project> create() async {
    final dir = await Directory.systemTemp.createTemp('twk_run_test');
    addTearDown(() => dir.delete(recursive: true));
    final twk = p.normalize(p.join(await packageDirectory(), '..', 'twk'));
    final project = _Project._(dir)
      ..write('pubspec.yaml', '''
name: hot_app
environment:
  sdk: ^3.13.5
dependencies:
  twk:
    path: $twk
dependency_overrides:
  twk_core:
    path: $twk/../twk_core
''')
      ..write('lib/counter.dart', _counter('count'))
      ..write('bin/heading.dart', _heading)
      ..write('bin/main.dart', _main('first footer'));
    final got = await runProcess(
      Platform.resolvedExecutable,
      [
        'pub',
        'get',
        '--offline',
      ],
      workingDirectory: dir.path,
      group: true,
    );
    expect(got.exitCode, 0, reason: '${got.stdout}${got.stderr}');
    return project;
  }

  final Directory dir;

  /// The app's `main`.
  String get entry => p.join(dir.path, 'bin', 'main.dart');

  /// Writes [text] to the file at [path] in the package.
  void write(String path, String text) => File(p.join(dir.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  /// Writes [text] to a new file beside [path] and moves it to [path], as
  /// editors that save safely do.
  void replace(String path, String text) {
    final file = File(p.join(dir.path, path));
    File('${file.path}.new')
      ..writeAsStringSync(text)
      ..renameSync(file.path);
  }
}

void main() {
  test('twk run reloads the app as its sources change and as its keys ask, '
      'its state kept; says why a reload failed, the app going on; restarts '
      "it; and ends with the app's exit code", () async {
    final project = await _Project.create();
    final screen = await _Screen.serve();
    final run = _runHere(project.entry, screen);
    final type = screen.type;

    await screen.waitFor('first heading', within: _start);
    await screen.waitFor('count 0');
    type('++');
    await screen.waitFor('count 2');

    // lib/ is watched, and the app's main
    project.write('lib/counter.dart', _counter('clicks'));
    await screen.waitFor('clicks 2');
    project.replace('bin/main.dart', _main('second footer'));
    await screen.waitFor('second footer');

    // bin/heading.dart is not: Ctrl+G h reloads it
    project.write('bin/heading.dart', _heading.replaceAll('first', 'second'));
    type('\x07h');
    await screen.waitFor('second heading');
    expect(screen.rows, contains('clicks 2'));

    project.write('lib/counter.dart', _counter('taps', broken: true));
    await screen.waitFor('hot reload failed');
    // what came before is in the console with it
    final console = screen.rows.join('\n');
    expect(console, contains('hot reload: watching'));
    expect(
      console,
      matches(RegExp(r'hot reload: \d+ librar(y|ies) in \d+ ms')),
    );
    type('+');
    await screen.waitFor('clicks 3');

    project.replace('lib/counter.dart', _counter('taps'));
    await screen.waitFor('taps 3');

    // Ctrl+G H starts the app again, its state new, and reloads that one
    type('\x07H');
    await screen.waitFor('taps 0', within: _start);
    expect(screen.rows.first, 'second heading');
    expect(screen.pids, hasLength(2));
    await screen.ended(0);
    project.write('lib/counter.dart', _counter('presses'));
    await screen.waitFor('presses 0');

    type('\x03');
    expect(await run.exitCode, 0, reason: '${run.err}');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('twk run passes the arguments after the file to the app, and '
      'reloads what changed while the app started once its binding '
      'runs', () async {
    final project = await _Project.create();
    final screen = await _Screen.serve();
    late final HotRunner runner;
    _runHere(project.entry, screen, ['--wait'], (r) => runner = r);
    await screen.said('the app waits', within: _start);
    // compiled before this change, which the tool sees before the app has
    // a binding to reload: it holds the reload for the binding
    final held = runner.reloadsHeld.first;
    project.write('lib/counter.dart', _counter('clicks'));
    await waitFor(
      held,
      'twk run to hold the reload of lib/counter.dart for the binding',
      timeout: const Duration(seconds: 30),
    );
    screen.type('go');
    await screen.waitFor('clicks 0');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('a test that ends while twk run runs its app leaves no app '
      'running: the tear-down ends the process the runner started', () async {
    final project = await _Project.create();
    final screen = await _Screen.serve();
    int? app;
    // registered first, so run last: after _runHere's tear-down
    addTearDown(() {
      expect(app, isNotNull);
      expect(
        Directory('/proc/$app').existsSync(),
        isFalse,
        reason: 'the app, pid $app, outlived the test',
      );
    });
    HotRunner? runner;
    _runHere(project.entry, screen, ['--wait'], (r) => runner = r);
    // the app started, which may still compile: the test ends there
    await waitUntil(
      () => (app = runner?.appPid) != null,
      'twk run to start the app',
      timeout: _start,
    );
  }, testOn: 'linux');

  test('twk run of an app that does not compile ends with its exit code, '
      'its errors on the stderr it leaves the app', () async {
    final project = await _Project.create();
    project.write('lib/counter.dart', _counter('count', broken: true));
    final run = await startTwk(['run', project.entry]);
    final stderrText = StringBuffer();
    run.stderr.transform(utf8.decoder).listen(stderrText.write);
    final code = await run.exitCode.timeout(_start);
    expect(code, 254);
    expect('$stderrText', contains("Expected ';' after this."));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('twk run of an app that a signal ends ends with 128 and the number '
      'of the signal, as a shell does', () async {
    final project = await _Project.create();
    final screen = await _Screen.serve();
    final run = _runHere(project.entry, screen, ['--kill']);
    expect(await run.exitCode, 128 + 9);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('twk run leaves the app its stdin and stdout; stopped by SIGTERM it '
      'ends the app and then itself, with 143', () async {
    final project = await _Project.create();
    final run = await startTwk(['run', project.entry]);
    final screen = _Screen.of(run.stdout);
    await screen.waitFor('count 0', within: _start);
    run.stdin.add(utf8.encode('+'));
    await screen.waitFor('count 1');
    run.kill();
    expect(await run.exitCode, 143);
    // the app wrote to the same stdout: it is closed once both ended
    await screen.done.timeout(const Duration(seconds: 10));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
